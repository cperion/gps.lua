#!/usr/bin/env python3
import json
import os
import queue
import statistics
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUALS = os.environ.get("LUALS_BIN") or str(Path.home() / ".local/share/nvim/mason/bin/lua-language-server")
OURS = os.environ.get("PVM_LSP_BIN") or "luajit lsp/main.lua"


def gen_file(n: int) -> str:
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
    lines += [
        "",
        "local function helper(x)",
        "    if x > 0 then return x * 2 end",
        "    return 0",
        "end",
        "",
        f"for i = 1, {n} do",
        "    local _ = helper(i)",
        "end",
        "",
        f"print(v1, v{n}, M.new('a', 1))",
        "print(undefined_global)",
        "return M",
    ]
    return "\n".join(lines)


def count_lines(text: str) -> int:
    return text.count("\n") + 1


class LspProcess:
    def __init__(self, cmd: str, cwd: Path):
        self.cmd = cmd
        self.cwd = cwd
        self.proc = subprocess.Popen(
            cmd,
            cwd=str(cwd),
            shell=True,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )
        self.q = queue.Queue()
        self.next_id = 1
        self.closed = False
        self.reader = threading.Thread(target=self._read_loop, daemon=True)
        self.reader.start()
        self.err_reader = threading.Thread(target=self._drain_stderr, daemon=True)
        self.err_reader.start()

    def _drain_stderr(self):
        try:
            while True:
                chunk = self.proc.stderr.read(4096)
                if not chunk:
                    return
        except Exception:
            return

    def _read_exact(self, n: int) -> bytes:
        chunks = []
        remain = n
        while remain > 0:
            chunk = self.proc.stdout.read(remain)
            if not chunk:
                break
            chunks.append(chunk)
            remain -= len(chunk)
        return b"".join(chunks)

    def _read_loop(self):
        out = self.proc.stdout
        try:
            while True:
                headers = {}
                while True:
                    line = out.readline()
                    if not line:
                        return
                    if line in (b"\r\n", b"\n", b""):
                        break
                    s = line.decode("utf-8", "replace").strip()
                    if not s:
                        break
                    if ":" in s:
                        k, v = s.split(":", 1)
                        headers[k.lower()] = v.strip()
                length = int(headers.get("content-length", "0"))
                if length <= 0:
                    continue
                body = self._read_exact(length)
                if len(body) != length:
                    raise RuntimeError(f"short read: wanted {length} bytes, got {len(body)}")
                msg = json.loads(body.decode("utf-8", "replace"))
                self.q.put(msg)
        except Exception as e:
            self.q.put({"__reader_error__": str(e)})

    def _send(self, obj):
        body = json.dumps(obj, separators=(",", ":")).encode("utf-8")
        msg = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii") + body
        self.proc.stdin.write(msg)
        self.proc.stdin.flush()

    def notify(self, method, params):
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def request(self, method, params, timeout=20.0):
        req_id = self.next_id
        self.next_id += 1
        self._send({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params})
        deadline = time.perf_counter() + timeout
        stash = []
        while True:
            remain = deadline - time.perf_counter()
            if remain <= 0:
                raise TimeoutError(f"timeout waiting for {method} on {self.cmd}")
            msg = self.q.get(timeout=remain)
            if "__reader_error__" in msg:
                raise RuntimeError(msg["__reader_error__"])
            if msg.get("id") == req_id:
                for other in stash:
                    self.q.put(other)
                return msg
            stash.append(msg)

    def close(self):
        if self.closed:
            return
        self.closed = True
        try:
            self.request("shutdown", {}, timeout=5.0)
        except Exception:
            pass
        try:
            self.notify("exit", {})
        except Exception:
            pass
        try:
            self.proc.terminate()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=2.0)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass


def initialize(proc: LspProcess):
    proc.request("initialize", {
        "processId": 1,
        "rootUri": "file://" + str(ROOT),
        "capabilities": {
            "textDocument": {
                "diagnostic": {"dynamicRegistration": False},
                "hover": {},
                "definition": {},
                "references": {},
                "completion": {},
                "documentSymbol": {},
            }
        },
    })
    proc.notify("initialized", {})


def open_doc(proc: LspProcess, uri: str, text: str, version=1):
    proc.notify("textDocument/didOpen", {
        "textDocument": {
            "uri": uri,
            "languageId": "lua",
            "version": version,
            "text": text,
        }
    })


def change_doc(proc: LspProcess, uri: str, text: str, version: int):
    proc.notify("textDocument/didChange", {
        "textDocument": {"uri": uri, "version": version},
        "contentChanges": [{"text": text}],
    })


def req_diag(uri):
    return "textDocument/diagnostic", {"textDocument": {"uri": uri}}


def req_hover(uri, line):
    return "textDocument/hover", {"textDocument": {"uri": uri}, "position": {"line": line, "character": 6}}


def req_def(uri, line):
    return "textDocument/definition", {"textDocument": {"uri": uri}, "position": {"line": line, "character": 6}}


def req_refs(uri, line):
    return "textDocument/references", {
        "textDocument": {"uri": uri},
        "position": {"line": line, "character": 6},
        "context": {"includeDeclaration": True},
    }


def req_comp(uri, line):
    return "textDocument/completion", {"textDocument": {"uri": uri}, "position": {"line": line, "character": 0}}


def req_symbols(uri):
    return "textDocument/documentSymbol", {"textDocument": {"uri": uri}}


def timed_request(proc: LspProcess, method: str, params: dict) -> float:
    t0 = time.perf_counter()
    proc.request(method, params)
    return (time.perf_counter() - t0) * 1e6


def median_us(samples):
    return statistics.median(samples)


def bench_cold(cmd: str, uri: str, text: str, method: str, params: dict, trials=5):
    times = []
    for _ in range(trials):
        p = LspProcess(cmd, ROOT)
        try:
            t0 = time.perf_counter()
            initialize(p)
            open_doc(p, uri, text, 1)
            p.request(method, params)
            times.append((time.perf_counter() - t0) * 1e6)
        finally:
            p.close()
    return median_us(times)


def bench_warm(cmd: str, uri: str, text: str):
    p = LspProcess(cmd, ROOT)
    try:
        initialize(p)
        open_doc(p, uri, text, 1)
        lines = count_lines(text)
        mid = max(0, lines // 2)

        requests = {
            "diag": req_diag(uri),
            "hover": req_hover(uri, mid),
            "def": req_def(uri, mid),
            "refs": req_refs(uri, mid),
            "comp": req_comp(uri, mid),
            "syms": req_symbols(uri),
        }

        for _ in range(5):
            for method, params in requests.values():
                p.request(method, params)

        out = {}
        for name, (method, params) in requests.items():
            samples = [timed_request(p, method, params) for _ in range(30)]
            out[name] = median_us(samples)

        changed = text.replace("undefined_global", "undefined_changed")
        samples = []
        for i in range(1, 11):
            new_text = changed.replace("undefined_changed", f"undefined_{i}")
            t0 = time.perf_counter()
            change_doc(p, uri, new_text, 1 + i)
            p.request(*req_diag(uri))
            samples.append((time.perf_counter() - t0) * 1e6)
        out["chg_diag"] = median_us(samples)
        return out
    finally:
        p.close()


def bench_case(label: str, text: str, uri: str):
    lines = count_lines(text)
    cold_method, cold_params = req_diag(uri)
    return {
        "label": label,
        "lines": lines,
        "ours_cold": bench_cold(OURS, uri, text, cold_method, cold_params),
        "luals_cold": bench_cold(f"{LUALS} --stdio", uri, text, cold_method, cold_params),
        "ours_warm": bench_warm(OURS, uri, text),
        "luals_warm": bench_warm(f"{LUALS} --stdio", uri, text),
    }


def print_table(results):
    print("=" * 132)
    print("  apples-to-apples stdio benchmark — same protocol, same requests, same persistent-session model")
    print("=" * 132)
    print()
    print("Cold round-trip: spawn + initialize + didOpen + textDocument/diagnostic")
    print(f"  {'file':28} {'lines':>6} | {'ours':>10} {'LuaLS':>10} {'factor':>8}")
    print("  " + "-" * 72)
    for r in results:
        factor = (r['luals_cold'] / r['ours_cold']) if r['ours_cold'] > 0 else 0.0
        print(f"  {r['label'][:28]:28} {r['lines']:6d} | {r['ours_cold']/1000:8.1f} ms {r['luals_cold']/1000:8.1f} ms {factor:7.2f}x")

    print()
    print("Warm persistent session: median request latency over stdio")
    print(f"  {'file':28} {'diag':>9} {'hover':>9} {'def':>9} {'refs':>9} {'comp':>9} {'syms':>9} {'chg+diag':>10}")
    print("  " + "-" * 108)
    for r in results:
        o = r['ours_warm']
        l = r['luals_warm']
        print(f"  {r['label'][:28]:28} ours  {o['diag']:7.1f}µs {o['hover']:7.1f}µs {o['def']:7.1f}µs {o['refs']:7.1f}µs {o['comp']:7.1f}µs {o['syms']:7.1f}µs {o['chg_diag']/1000:8.1f}ms")
        print(f"  {'':28} luals {l['diag']:7.1f}µs {l['hover']:7.1f}µs {l['def']:7.1f}µs {l['refs']:7.1f}µs {l['comp']:7.1f}µs {l['syms']:7.1f}µs {l['chg_diag']/1000:8.1f}ms")


def main():
    cases = [
        ("50 locals", gen_file(50), "file:///bench_50.lua"),
        ("200 locals", gen_file(200), "file:///bench_200.lua"),
        ("500 locals", gen_file(500), "file:///bench_500.lua"),
    ]
    for name in ["pvm.lua", "triplet.lua", "asdl_context.lua", "lsp/semantics.lua"]:
        path = ROOT / name
        if path.exists():
            cases.append((name, path.read_text(), "file://" + str(path)))

    results = []
    for label, text, uri in cases:
        print(f"benchmarking {label}...", file=sys.stderr)
        results.append(bench_case(label, text, uri))
    print_table(results)


if __name__ == "__main__":
    main()
