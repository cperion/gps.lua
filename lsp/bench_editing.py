#!/usr/bin/env python3
"""
Realistic editing session benchmark.
Simulates actual editing: open file, make a series of edits, query after each.
Measures how each server responds to continuous changes.
"""

import subprocess, json, time, os, sys, select

LUALS = os.path.expanduser("~/.local/share/nvim/mason/bin/lua-language-server")
PVM_LSP = ["luajit", "lsp/main.lua"]

def make_msg(obj):
    body = json.dumps(obj)
    return f"Content-Length: {len(body)}\r\n\r\n".encode() + body.encode()

def read_response(proc, timeout=10.0):
    headers = {}
    deadline = time.monotonic() + timeout
    buf = b""
    while time.monotonic() < deadline:
        b = proc.stdout.read(1)
        if not b: return None
        buf += b
        if buf.endswith(b"\r\n\r\n"): break
    for line in buf.decode().split("\r\n"):
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    length = int(headers.get("content-length", 0))
    if length == 0: return None
    body = b""
    while len(body) < length:
        chunk = proc.stdout.read(length - len(body))
        if not chunk: return None
        body += chunk
    return json.loads(body)

def drain(proc, timeout=0.05):
    results = []
    while True:
        ready, _, _ = select.select([proc.stdout], [], [], timeout)
        if not ready: break
        r = read_response(proc, timeout=1.0)
        if r: results.append(r)
        else: break
    return results

def send(proc, obj):
    proc.stdin.write(make_msg(obj))
    proc.stdin.flush()

def request(proc, obj, rid):
    obj["id"] = rid
    t0 = time.monotonic()
    send(proc, obj)
    while True:
        resp = read_response(proc, timeout=10.0)
        if resp is None: return -1
        if resp.get("id") == rid:
            return (time.monotonic() - t0) * 1000
        # notification, keep reading

def start(cmd):
    return subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, bufsize=0)

def read_file(path):
    with open(path) as f: return f.read()

def simulate_editing_session(cmd, label, uri, text):
    """Simulate: open → 10 edits with diag+hover after each → close"""
    proc = start(cmd)
    rid = [0]
    def nid(): rid[0] += 1; return rid[0]

    results = {"edits": []}
    lines = text.split("\n")
    mid = len(lines) // 2

    try:
        # Init
        request(proc, {"jsonrpc":"2.0","method":"initialize",
            "params":{"processId":os.getpid(),"rootUri":f"file://{os.getcwd()}","capabilities":{}}}, nid())
        send(proc, {"jsonrpc":"2.0","method":"initialized","params":{}})

        # Open
        t0 = time.monotonic()
        send(proc, {"jsonrpc":"2.0","method":"textDocument/didOpen",
            "params":{"textDocument":{"uri":uri,"languageId":"lua","version":1,"text":text}}})
        time.sleep(0.15)
        drain(proc, 0.1)

        # First diagnostic (cold)
        cold_ms = request(proc, {"jsonrpc":"2.0","method":"textDocument/diagnostic",
            "params":{"textDocument":{"uri":uri}}}, nid())
        results["cold_diag_ms"] = cold_ms
        results["open_to_ready_ms"] = (time.monotonic() - t0) * 1000

        # Simulate 10 edits: change a line, then query diag + hover
        current = text
        for i in range(10):
            # Make an edit: change the last meaningful line
            if "undefined_global" in current:
                new_text = current.replace("undefined_global", f"undef_edit_{i}")
            else:
                new_text = current.rstrip() + f"\n-- edit {i}"
            current = new_text

            t_edit = time.monotonic()

            # Send change
            send(proc, {"jsonrpc":"2.0","method":"textDocument/didChange",
                "params":{"textDocument":{"uri":uri,"version":10+i},
                           "contentChanges":[{"text":new_text}]}})

            # Immediately request diagnostic
            diag_ms = request(proc, {"jsonrpc":"2.0","method":"textDocument/diagnostic",
                "params":{"textDocument":{"uri":uri}}}, nid())

            # Then hover
            hover_ms = request(proc, {"jsonrpc":"2.0","method":"textDocument/hover",
                "params":{"textDocument":{"uri":uri},"position":{"line":mid,"character":6}}}, nid())

            # Then completion
            comp_ms = request(proc, {"jsonrpc":"2.0","method":"textDocument/completion",
                "params":{"textDocument":{"uri":uri},"position":{"line":mid,"character":0}}}, nid())

            total_ms = (time.monotonic() - t_edit) * 1000
            drain(proc, 0.01)

            results["edits"].append({
                "diag_ms": diag_ms,
                "hover_ms": hover_ms,
                "comp_ms": comp_ms,
                "total_ms": total_ms,
            })

        # Shutdown
        request(proc, {"jsonrpc":"2.0","method":"shutdown"}, nid())
        send(proc, {"jsonrpc":"2.0","method":"exit"})

    except Exception as e:
        results["error"] = str(e)
    finally:
        try: proc.terminate(); proc.wait(timeout=2)
        except: proc.kill()

    return results

# ══════════════════════════════════════════════════════════════

print("=" * 110)
print("  EDITING SESSION BENCHMARK: 10 consecutive edits, diag+hover+completion after each")
print("  Both servers as subprocesses, bidirectional stdio, real JSON-RPC")
print("=" * 110)

test_cases = [
    ("100 locals", None, "file:///gen100.lua"),
    ("pvm.lua", "pvm.lua", None),
    ("triplet.lua", "triplet.lua", None),
    ("lsp/semantics.lua", "lsp/semantics.lua", None),
    ("lsp/parser.lua", "lsp/parser.lua", None),
]

def gen_file(n):
    lines = ["---@class T","---@field name string","local M = {}","",
             "function M.new(name)","    return {name=name}","end",""]
    for i in range(1, n+1): lines.append(f"local v{i} = {i}")
    lines += ["", f"print(v1, v{n})", "print(undefined_global)", "return M"]
    return "\n".join(lines)

for label, path, uri in test_cases:
    if path:
        text = read_file(path)
        uri = f"file://{os.getcwd()}/{path}"
    else:
        text = gen_file(100)

    lines = text.count("\n") + 1
    print(f"\n  ── {label} ({lines} lines) ──")
    print(f"  {'edit#':>5s} │ {'pvm diag':>9s} {'pvm hovr':>9s} {'pvm comp':>9s} {'pvm totl':>9s} │ {'lua diag':>9s} {'lua hovr':>9s} {'lua comp':>9s} {'lua totl':>9s}")
    print(f"  " + "-"*5 + " │ " + ("-"*9 + " ")*4 + "│ " + ("-"*9 + " ")*4)

    pvm_r = simulate_editing_session(PVM_LSP, "pvm-lsp", uri, text)
    lua_r = simulate_editing_session([LUALS, "--stdio"], "LuaLS", uri, text)

    for i in range(10):
        pe = pvm_r["edits"][i] if i < len(pvm_r.get("edits",[])) else {}
        le = lua_r["edits"][i] if i < len(lua_r.get("edits",[])) else {}

        def fmt(v):
            if not v or v < 0: return "     N/A"
            if v < 1: return f" {v*1000:5.0f} µs"
            return f" {v:5.1f} ms"

        print(f"  {i+1:5d} │{fmt(pe.get('diag_ms'))}{fmt(pe.get('hover_ms'))}{fmt(pe.get('comp_ms'))}{fmt(pe.get('total_ms'))} │{fmt(le.get('diag_ms'))}{fmt(le.get('hover_ms'))}{fmt(le.get('comp_ms'))}{fmt(le.get('total_ms'))}")

    # Summary
    pvm_diags = [e["diag_ms"] for e in pvm_r.get("edits",[]) if e.get("diag_ms",0)>0]
    lua_diags = [e["diag_ms"] for e in lua_r.get("edits",[]) if e.get("diag_ms",0)>0]
    pvm_totals = [e["total_ms"] for e in pvm_r.get("edits",[]) if e.get("total_ms",0)>0]
    lua_totals = [e["total_ms"] for e in lua_r.get("edits",[]) if e.get("total_ms",0)>0]

    if pvm_diags and lua_diags:
        pm, lm = sorted(pvm_diags)[len(pvm_diags)//2], sorted(lua_diags)[len(lua_diags)//2]
        pt, lt = sorted(pvm_totals)[len(pvm_totals)//2], sorted(lua_totals)[len(lua_totals)//2]
        print(f"  {'median':>5s} │   diag {pm:6.1f} ms          total {pt:6.1f} ms │   diag {lm:6.1f} ms          total {lt:6.1f} ms")
        if pm > 0: print(f"         │   diag speedup: {lm/pm:.1f}x          total speedup: {lt/pt:.1f}x")

print()
print("=" * 110)
