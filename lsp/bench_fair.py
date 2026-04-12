#!/usr/bin/env python3
"""
Fair LSP benchmark with bidirectional stdio.
Starts each server, keeps it running, measures per-request round-trip.

Now also emits paper-friendly tables:
  - Markdown: lsp/bench_out/paper_tables.md
  - LaTeX:    lsp/bench_out/paper_tables.tex
  - CSV:      lsp/bench_out/warm_table.csv
              lsp/bench_out/startup_incremental_table.csv
              lsp/bench_out/speedup_summary.csv
"""

import argparse
import csv
import json
import math
import os
import select
import statistics
import subprocess
import sys
import time
from pathlib import Path

LUALS = os.path.expanduser("~/.local/share/nvim/mason/bin/lua-language-server")
PVM_LSP = ["luajit", "lsp/main.lua"]


# ---------- JSON-RPC IO ----------

def make_msg(obj):
    body = json.dumps(obj)
    header = f"Content-Length: {len(body)}\r\n\r\n"
    return (header + body).encode()


def read_response(proc, timeout=10.0):
    """Read one JSON-RPC response from the server's stdout."""
    headers = {}
    deadline = time.monotonic() + timeout
    buf = b""

    while time.monotonic() < deadline:
        b = proc.stdout.read(1)
        if not b:
            return None
        buf += b
        if buf.endswith(b"\r\n\r\n"):
            break

    for line in buf.decode(errors="replace").split("\r\n"):
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()

    length = int(headers.get("content-length", 0))
    if length == 0:
        return None

    body = b""
    while len(body) < length:
        chunk = proc.stdout.read(length - len(body))
        if not chunk:
            return None
        body += chunk

    return json.loads(body)


def drain_notifications(proc, timeout=0.05):
    """Read any pending notifications (non-blocking-ish)."""
    results = []
    while True:
        ready, _, _ = select.select([proc.stdout], [], [], timeout)
        if not ready:
            break
        resp = read_response(proc, timeout=1.0)
        if resp:
            results.append(resp)
        else:
            break
    return results


def send_and_measure(proc, msg_obj, expect_id=None):
    """Send a message and measure time to get the response with matching id."""
    data = make_msg(msg_obj)
    t0 = time.monotonic()
    proc.stdin.write(data)
    proc.stdin.flush()

    if expect_id is None:
        return 0.0  # notification, no response expected

    while True:
        resp = read_response(proc, timeout=20.0)
        if resp is None:
            return -1.0
        if resp.get("id") == expect_id:
            return (time.monotonic() - t0) * 1000.0  # ms
        # else: notification or another response; keep reading


def start_server(cmd):
    return subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )


# ---------- Benchmark core ----------

def bench_server(cmd, uri, text, warm_samples=20):
    proc = start_server(cmd)
    results = {}
    lines = text.count("\n") + 1
    mid = lines // 2

    try:
        # Initialize
        t0 = time.monotonic()
        ms = send_and_measure(
            proc,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": os.getpid(),
                    "rootUri": f"file://{os.getcwd()}",
                    "capabilities": {},
                },
            },
            expect_id=1,
        )
        results["init"] = ms

        # Initialized notification
        proc.stdin.write(make_msg({"jsonrpc": "2.0", "method": "initialized", "params": {}}))
        proc.stdin.flush()

        # didOpen
        proc.stdin.write(
            make_msg(
                {
                    "jsonrpc": "2.0",
                    "method": "textDocument/didOpen",
                    "params": {
                        "textDocument": {
                            "uri": uri,
                            "languageId": "lua",
                            "version": 1,
                            "text": text,
                        }
                    },
                }
            )
        )
        proc.stdin.flush()

        time.sleep(0.1)
        drain_notifications(proc, timeout=0.2)

        results["startup"] = (time.monotonic() - t0) * 1000.0

        req_id = 10

        def query(method, params):
            nonlocal req_id
            req_id += 1
            msg = {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}
            return send_and_measure(proc, msg, expect_id=req_id)

        # Cold/warm-up calls
        results["diag_cold"] = query("textDocument/diagnostic", {"textDocument": {"uri": uri}})
        results["hover_cold"] = query(
            "textDocument/hover",
            {"textDocument": {"uri": uri}, "position": {"line": mid, "character": 6}},
        )
        results["def_cold"] = query(
            "textDocument/definition",
            {"textDocument": {"uri": uri}, "position": {"line": mid, "character": 6}},
        )

        # Cached queries (median)
        N = warm_samples
        diag_times = []
        hover_times = []
        def_times = []
        comp_times = []
        sym_times = []

        for _ in range(N):
            diag_times.append(query("textDocument/diagnostic", {"textDocument": {"uri": uri}}))
            hover_times.append(
                query(
                    "textDocument/hover",
                    {"textDocument": {"uri": uri}, "position": {"line": mid, "character": 6}},
                )
            )
            def_times.append(
                query(
                    "textDocument/definition",
                    {"textDocument": {"uri": uri}, "position": {"line": mid, "character": 6}},
                )
            )
            comp_times.append(
                query(
                    "textDocument/completion",
                    {"textDocument": {"uri": uri}, "position": {"line": mid, "character": 0}},
                )
            )
            sym_times.append(query("textDocument/documentSymbol", {"textDocument": {"uri": uri}}))

        results["diag_warm"] = sorted(diag_times)[N // 2]
        results["hover_warm"] = sorted(hover_times)[N // 2]
        results["def_warm"] = sorted(def_times)[N // 2]
        results["comp_warm"] = sorted(comp_times)[N // 2]
        results["sym_warm"] = sorted(sym_times)[N // 2]

        # Incremental: change + diagnostic round-trip
        change_times = []
        for i in range(5):
            changed = (
                text.replace("undefined_global", f"undef_{i}", 1)
                if "undefined_global" in text
                else text[:-5] + str(i)
            )
            t0 = time.monotonic()
            proc.stdin.write(
                make_msg(
                    {
                        "jsonrpc": "2.0",
                        "method": "textDocument/didChange",
                        "params": {
                            "textDocument": {"uri": uri, "version": 100 + i},
                            "contentChanges": [{"text": changed}],
                        },
                    }
                )
            )
            proc.stdin.flush()
            drain_notifications(proc, timeout=0.05)
            _ = query("textDocument/diagnostic", {"textDocument": {"uri": uri}})
            change_times.append((time.monotonic() - t0) * 1000.0)

        results["change_diag"] = sorted(change_times)[len(change_times) // 2]

        # Shutdown
        send_and_measure(proc, {"jsonrpc": "2.0", "id": 999, "method": "shutdown"}, expect_id=999)
        proc.stdin.write(make_msg({"jsonrpc": "2.0", "method": "exit"}))
        proc.stdin.flush()

    except Exception as e:
        results["error"] = str(e)
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2)
        except Exception:
            proc.kill()

    return results


# ---------- Formatting / paper tables ----------

def read_file(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return None


def gen_file(n):
    lines = [
        "---@class TestClass",
        "---@field name string",
        "---@field id number",
        "local M = {}",
        "",
        "---@param name string",
        "---@param id number",
        "---@return TestClass",
        "function M.new(name, id)",
        "    return { name = name, id = id }",
        "end",
        "",
    ]
    for i in range(1, n + 1):
        lines.append(f"local v{i} = {i}")
    lines += ["", f"print(v1, v{n})", "print(undefined_global)", "return M"]
    return "\n".join(lines)


def fmt_human_ms(v):
    if v is None or v < 0:
        return "  N/A"
    if v < 1:
        return f"{v * 1000:6.0f} µs"
    return f"{v:6.1f} ms"


def fmt_num(v, digits=3):
    if v is None or v < 0:
        return ""
    return f"{v:.{digits}f}"


def speedup(pvm_v, luals_v):
    if pvm_v is None or luals_v is None or pvm_v <= 0 or luals_v <= 0:
        return None
    return luals_v / pvm_v


def geomean(xs):
    vals = [x for x in xs if x is not None and x > 0]
    if not vals:
        return None
    return math.exp(sum(math.log(x) for x in vals) / len(vals))


def latex_escape(s):
    return (
        s.replace("\\", "\\textbackslash{}")
        .replace("_", "\\_")
        .replace("%", "\\%")
        .replace("&", "\\&")
        .replace("#", "\\#")
    )


def build_paired_rows(test_cases, results, pvm_label, luals_label):
    pvm_rows = {r["file"]: r for r in results.get(pvm_label, [])}
    luals_rows = {r["file"]: r for r in results.get(luals_label, [])}
    out = []
    for label, text, _uri in test_cases:
        out.append(
            {
                "file": label,
                "lines": text.count("\n") + 1,
                "pvm": pvm_rows.get(label),
                "luals": luals_rows.get(label),
            }
        )
    return out


def write_paper_tables(out_dir, test_cases, results, pvm_label, luals_label):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    paired = build_paired_rows(test_cases, results, pvm_label, luals_label)

    # --- Table A: warm cached ops ---
    warm_metrics = [
        ("diag_warm", "diag"),
        ("hover_warm", "hover"),
        ("def_warm", "go-def"),
        ("comp_warm", "compl"),
        ("sym_warm", "syms"),
    ]

    warm_rows = []
    for row in paired:
        p = row["pvm"] or {}
        l = row["luals"] or {}
        rec = {"file": row["file"], "lines": row["lines"]}
        for k, short in warm_metrics:
            pv = p.get(k)
            lv = l.get(k)
            rec[f"{short}_pvm_ms"] = pv
            rec[f"{short}_luals_ms"] = lv
            rec[f"{short}_speedup"] = speedup(pv, lv)
        warm_rows.append(rec)

    # --- Table B: startup + incremental ---
    startup_rows = []
    for row in paired:
        p = row["pvm"] or {}
        l = row["luals"] or {}
        sp = p.get("startup")
        sl = l.get("startup")
        cp = p.get("change_diag")
        cl = l.get("change_diag")
        startup_rows.append(
            {
                "file": row["file"],
                "lines": row["lines"],
                "startup_pvm_ms": sp,
                "startup_luals_ms": sl,
                "startup_speedup": speedup(sp, sl),
                "chgdiag_pvm_ms": cp,
                "chgdiag_luals_ms": cl,
                "chgdiag_speedup": speedup(cp, cl),
            }
        )

    # --- Summary geomean speedups ---
    summary_rows = []
    for k, short in warm_metrics:
        g = geomean([r[f"{short}_speedup"] for r in warm_rows])
        summary_rows.append({"metric": short, "geomean_speedup": g})
    summary_rows.append(
        {
            "metric": "startup",
            "geomean_speedup": geomean([r["startup_speedup"] for r in startup_rows]),
        }
    )
    summary_rows.append(
        {
            "metric": "chg+dg",
            "geomean_speedup": geomean([r["chgdiag_speedup"] for r in startup_rows]),
        }
    )

    # ---------- CSV ----------
    warm_csv = out_dir / "warm_table.csv"
    with warm_csv.open("w", newline="") as f:
        fieldnames = ["file", "lines"]
        for _k, short in warm_metrics:
            fieldnames += [f"{short}_pvm_ms", f"{short}_luals_ms", f"{short}_speedup"]
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in warm_rows:
            w.writerow(r)

    startup_csv = out_dir / "startup_incremental_table.csv"
    with startup_csv.open("w", newline="") as f:
        fieldnames = [
            "file",
            "lines",
            "startup_pvm_ms",
            "startup_luals_ms",
            "startup_speedup",
            "chgdiag_pvm_ms",
            "chgdiag_luals_ms",
            "chgdiag_speedup",
        ]
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in startup_rows:
            w.writerow(r)

    summary_csv = out_dir / "speedup_summary.csv"
    with summary_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["metric", "geomean_speedup"])
        w.writeheader()
        for r in summary_rows:
            w.writerow(r)

    # ---------- Markdown ----------
    md = []
    md.append("# pvm-lsp vs LuaLS — paper tables\n")
    md.append(f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
    md.append("All times are milliseconds (ms), medians of warm cached round-trips unless noted.\n")

    md.append("## Table A — Warm cached requests (ms)\n")
    md.append(
        "| file | lines | diag pvm | diag LuaLS | diag x | hover pvm | hover LuaLS | hover x | def pvm | def LuaLS | def x | comp pvm | comp LuaLS | comp x | syms pvm | syms LuaLS | syms x |"
    )
    md.append(
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
    )
    for r in warm_rows:
        md.append(
            "| {file} | {lines} | {dpm} | {dlm} | {dx} | {hpm} | {hlm} | {hx} | {fpm} | {flm} | {fx} | {cpm} | {clm} | {cx} | {spm} | {slm} | {sx} |".format(
                file=r["file"],
                lines=r["lines"],
                dpm=fmt_num(r["diag_pvm_ms"]),
                dlm=fmt_num(r["diag_luals_ms"]),
                dx=fmt_num(r["diag_speedup"], 2),
                hpm=fmt_num(r["hover_pvm_ms"]),
                hlm=fmt_num(r["hover_luals_ms"]),
                hx=fmt_num(r["hover_speedup"], 2),
                fpm=fmt_num(r["go-def_pvm_ms"]),
                flm=fmt_num(r["go-def_luals_ms"]),
                fx=fmt_num(r["go-def_speedup"], 2),
                cpm=fmt_num(r["compl_pvm_ms"]),
                clm=fmt_num(r["compl_luals_ms"]),
                cx=fmt_num(r["compl_speedup"], 2),
                spm=fmt_num(r["syms_pvm_ms"]),
                slm=fmt_num(r["syms_luals_ms"]),
                sx=fmt_num(r["syms_speedup"], 2),
            )
        )

    md.append("\n## Table B — Startup and incremental edit+diagnostic (ms)\n")
    md.append(
        "| file | lines | startup pvm | startup LuaLS | startup x | chg+dg pvm | chg+dg LuaLS | chg+dg x |"
    )
    md.append("|---|---:|---:|---:|---:|---:|---:|---:|")
    for r in startup_rows:
        md.append(
            "| {file} | {lines} | {sp} | {sl} | {sx} | {cp} | {cl} | {cx} |".format(
                file=r["file"],
                lines=r["lines"],
                sp=fmt_num(r["startup_pvm_ms"]),
                sl=fmt_num(r["startup_luals_ms"]),
                sx=fmt_num(r["startup_speedup"], 2),
                cp=fmt_num(r["chgdiag_pvm_ms"]),
                cl=fmt_num(r["chgdiag_luals_ms"]),
                cx=fmt_num(r["chgdiag_speedup"], 2),
            )
        )

    md.append("\n## Table C — Geometric mean speedup (LuaLS / pvm-lsp)\n")
    md.append("| metric | geomean speedup x |")
    md.append("|---|---:|")
    for r in summary_rows:
        md.append(f"| {r['metric']} | {fmt_num(r['geomean_speedup'], 2)} |")

    md_path = out_dir / "paper_tables.md"
    md_path.write_text("\n".join(md) + "\n")

    # ---------- LaTeX ----------
    tex = []
    tex.append("% Auto-generated by lsp/bench_fair.py")
    tex.append("% Times in ms, speedup = LuaLS / pvm-lsp")

    tex.append("\\begin{table*}[t]")
    tex.append("\\centering")
    tex.append("\\small")
    tex.append("\\begin{tabular}{l r r r r r r r r r r r r r r r r}")
    tex.append("\\toprule")
    tex.append(
        "File & Lines & Diag$_{pvm}$ & Diag$_{luals}$ & $\\times$ & Hover$_{pvm}$ & Hover$_{luals}$ & $\\times$ & Def$_{pvm}$ & Def$_{luals}$ & $\\times$ & Comp$_{pvm}$ & Comp$_{luals}$ & $\\times$ & Sym$_{pvm}$ & Sym$_{luals}$ & $\\times$ \\\\"
    )
    tex.append("\\midrule")
    for r in warm_rows:
        tex.append(
            "{file} & {lines} & {dpm} & {dlm} & {dx} & {hpm} & {hlm} & {hx} & {fpm} & {flm} & {fx} & {cpm} & {clm} & {cx} & {spm} & {slm} & {sx} \\\\".format(
                file=latex_escape(r["file"]),
                lines=r["lines"],
                dpm=fmt_num(r["diag_pvm_ms"]),
                dlm=fmt_num(r["diag_luals_ms"]),
                dx=fmt_num(r["diag_speedup"], 2),
                hpm=fmt_num(r["hover_pvm_ms"]),
                hlm=fmt_num(r["hover_luals_ms"]),
                hx=fmt_num(r["hover_speedup"], 2),
                fpm=fmt_num(r["go-def_pvm_ms"]),
                flm=fmt_num(r["go-def_luals_ms"]),
                fx=fmt_num(r["go-def_speedup"], 2),
                cpm=fmt_num(r["compl_pvm_ms"]),
                clm=fmt_num(r["compl_luals_ms"]),
                cx=fmt_num(r["compl_speedup"], 2),
                spm=fmt_num(r["syms_pvm_ms"]),
                slm=fmt_num(r["syms_luals_ms"]),
                sx=fmt_num(r["syms_speedup"], 2),
            )
        )
    tex.append("\\bottomrule")
    tex.append("\\end{tabular}")
    tex.append("\\caption{Warm cached LSP request latency (ms). Speedup is LuaLS / pvm-lsp.}")
    tex.append("\\label{tab:warm-lsp}")
    tex.append("\\end{table*}")

    tex.append("")
    tex.append("\\begin{table}[t]")
    tex.append("\\centering")
    tex.append("\\small")
    tex.append("\\begin{tabular}{l r r r r r r r}")
    tex.append("\\toprule")
    tex.append("File & Lines & Startup$_{pvm}$ & Startup$_{luals}$ & $\\times$ & Chg+Diag$_{pvm}$ & Chg+Diag$_{luals}$ & $\\times$ \\\\")
    tex.append("\\midrule")
    for r in startup_rows:
        tex.append(
            "{file} & {lines} & {sp} & {sl} & {sx} & {cp} & {cl} & {cx} \\\\".format(
                file=latex_escape(r["file"]),
                lines=r["lines"],
                sp=fmt_num(r["startup_pvm_ms"]),
                sl=fmt_num(r["startup_luals_ms"]),
                sx=fmt_num(r["startup_speedup"], 2),
                cp=fmt_num(r["chgdiag_pvm_ms"]),
                cl=fmt_num(r["chgdiag_luals_ms"]),
                cx=fmt_num(r["chgdiag_speedup"], 2),
            )
        )
    tex.append("\\bottomrule")
    tex.append("\\end{tabular}")
    tex.append("\\caption{Startup and incremental edit+diagnostic latency (ms). Speedup is LuaLS / pvm-lsp.}")
    tex.append("\\label{tab:startup-incremental}")
    tex.append("\\end{table}")

    tex.append("")
    tex.append("\\begin{table}[t]")
    tex.append("\\centering")
    tex.append("\\small")
    tex.append("\\begin{tabular}{l r}")
    tex.append("\\toprule")
    tex.append("Metric & Geomean speedup ($\\times$) \\\\")
    tex.append("\\midrule")
    for r in summary_rows:
        tex.append(f"{latex_escape(r['metric'])} & {fmt_num(r['geomean_speedup'], 2)} \\\\")
    tex.append("\\bottomrule")
    tex.append("\\end{tabular}")
    tex.append("\\caption{Geometric mean speedup (LuaLS / pvm-lsp).}")
    tex.append("\\label{tab:geomean-speedup}")
    tex.append("\\end{table}")

    tex_path = out_dir / "paper_tables.tex"
    tex_path.write_text("\n".join(tex) + "\n")

    return {
        "md": str(md_path),
        "tex": str(tex_path),
        "warm_csv": str(warm_csv),
        "startup_csv": str(startup_csv),
        "summary_csv": str(summary_csv),
    }


def main():
    parser = argparse.ArgumentParser(description="Fair stdio LSP benchmark + paper tables")
    parser.add_argument("--samples", type=int, default=20, help="warm cached samples per operation")
    parser.add_argument("--out-dir", default="lsp/bench_out", help="output directory for paper tables")
    parser.add_argument("--luals", default=LUALS, help="path to lua-language-server executable")
    args = parser.parse_args()

    luals_cmd = [args.luals, "--stdio"]

    print("=" * 110)
    print("  FAIR BENCHMARK: bidirectional stdio, per-request round-trip")
    print("  Both servers running as subprocesses with identical JSON-RPC messages")
    print("=" * 110)

    test_cases = [
        ("100 locals", gen_file(100), "file:///gen100.lua"),
        ("200 locals", gen_file(200), "file:///gen200.lua"),
    ]

    for name in ["pvm.lua", "triplet.lua", "asdl_context.lua", "lsp/semantics.lua", "lsp/parser.lua"]:
        text = read_file(name)
        if text:
            test_cases.append((name, text, f"file://{os.getcwd()}/{name}"))

    header = (
        f"  {'file':<24s} {'lines':>5s} │ {'startup':>8s} {'diag':>8s} {'hover':>8s} "
        f"{'go-def':>8s} {'compl':>8s} {'syms':>8s} {'chg+dg':>8s}"
    )
    sep = "  " + "-" * 24 + " " + "-" * 5 + " │ " + ("-" * 8 + " ") * 7

    servers = [
        ("pvm-lsp", PVM_LSP),
        ("LuaLS 3.16.4", luals_cmd),
    ]

    results = {label: [] for label, _ in servers}

    for server_label, server_cmd in servers:
        print(f"\n  ── {server_label} ──")
        print(header)
        print(sep)

        for label, text, uri in test_cases:
            lines = text.count("\n") + 1
            r = bench_server(server_cmd, uri, text, warm_samples=args.samples)
            rec = {"file": label, "lines": lines}
            rec.update(r)
            results[server_label].append(rec)

            if "error" in r:
                print(f"  {label:<24s} {lines:5d} │ ERROR: {r['error'][:50]}")
                continue

            print(
                f"  {label:<24s} {lines:5d} │ {fmt_human_ms(r.get('startup'))} "
                f"{fmt_human_ms(r.get('diag_warm'))} {fmt_human_ms(r.get('hover_warm'))} "
                f"{fmt_human_ms(r.get('def_warm'))} {fmt_human_ms(r.get('comp_warm'))} "
                f"{fmt_human_ms(r.get('sym_warm'))} {fmt_human_ms(r.get('change_diag'))}"
            )

    print()
    print("  startup  = init + didOpen + settle time")
    print(f"  diag..syms = median of {args.samples} cached round-trips (server already analyzed file)")
    print("  chg+dg   = didChange(1 line) + diagnostic round-trip")
    print("=" * 110)

    out_paths = write_paper_tables(
        out_dir=args.out_dir,
        test_cases=test_cases,
        results=results,
        pvm_label="pvm-lsp",
        luals_label="LuaLS 3.16.4",
    )

    print("\nPaper tables written:")
    print(f"  Markdown: {out_paths['md']}")
    print(f"  LaTeX:    {out_paths['tex']}")
    print(f"  CSV warm: {out_paths['warm_csv']}")
    print(f"  CSV s+i:  {out_paths['startup_csv']}")
    print(f"  CSV sum:  {out_paths['summary_csv']}")


if __name__ == "__main__":
    main()
