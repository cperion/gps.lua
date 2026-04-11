#!/usr/bin/env python3
"""
Fair LSP benchmark with bidirectional IO.
Starts each server, keeps it running, measures per-request round-trip.
"""

import subprocess
import json
import time
import sys
import os

LUALS = os.path.expanduser("~/.local/share/nvim/mason/bin/lua-language-server")
PVM_LSP = ["luajit", "lsp/main.lua"]

def make_msg(obj):
    body = json.dumps(obj)
    header = f"Content-Length: {len(body)}\r\n\r\n"
    return (header + body).encode()

def read_response(proc, timeout=10.0):
    """Read one JSON-RPC response from the server's stdout."""
    # Read headers
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
    
    for line in buf.decode().split("\r\n"):
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
    import select
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
        return 0  # notification, no response expected
    
    # Read responses until we get the one with our id
    while True:
        resp = read_response(proc, timeout=10.0)
        if resp is None:
            return -1
        if resp.get("id") == expect_id:
            return (time.monotonic() - t0) * 1000  # ms
        # else it's a notification, keep reading

def start_server(cmd):
    return subprocess.Popen(
        cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        bufsize=0
    )

def bench_server(cmd, label, uri, text):
    proc = start_server(cmd)
    results = {}
    lines = text.count("\n") + 1
    mid = lines // 2
    
    try:
        # Initialize
        t0 = time.monotonic()
        ms = send_and_measure(proc, {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"processId": os.getpid(), "rootUri": f"file://{os.getcwd()}", "capabilities": {}}
        }, expect_id=1)
        results["init"] = ms
        
        # Initialized notification
        proc.stdin.write(make_msg({"jsonrpc": "2.0", "method": "initialized", "params": {}}))
        proc.stdin.flush()
        
        # didOpen
        proc.stdin.write(make_msg({
            "jsonrpc": "2.0", "method": "textDocument/didOpen",
            "params": {"textDocument": {"uri": uri, "languageId": "lua", "version": 1, "text": text}}
        }))
        proc.stdin.flush()
        
        # Give server time to process didOpen
        time.sleep(0.1)
        drain_notifications(proc, timeout=0.2)
        
        results["startup"] = (time.monotonic() - t0) * 1000
        
        # Now measure individual queries
        req_id = 10
        
        def query(method, params):
            nonlocal req_id
            req_id += 1
            msg = {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}
            return send_and_measure(proc, msg, expect_id=req_id)
        
        # Warm queries (first call may include analysis)
        results["diag_cold"] = query("textDocument/diagnostic", {"textDocument": {"uri": uri}})
        results["hover_cold"] = query("textDocument/hover", {
            "textDocument": {"uri": uri}, "position": {"line": mid, "character": 6}})
        results["def_cold"] = query("textDocument/definition", {
            "textDocument": {"uri": uri}, "position": {"line": mid, "character": 6}})
        
        # Cached queries (server already analyzed)
        N = 20
        diag_times = []
        hover_times = []
        def_times = []
        comp_times = []
        sym_times = []
        
        for _ in range(N):
            diag_times.append(query("textDocument/diagnostic", {"textDocument": {"uri": uri}}))
            hover_times.append(query("textDocument/hover", {
                "textDocument": {"uri": uri}, "position": {"line": mid, "character": 6}}))
            def_times.append(query("textDocument/definition", {
                "textDocument": {"uri": uri}, "position": {"line": mid, "character": 6}}))
            comp_times.append(query("textDocument/completion", {
                "textDocument": {"uri": uri}, "position": {"line": mid, "character": 0}}))
            sym_times.append(query("textDocument/documentSymbol", {"textDocument": {"uri": uri}}))
        
        results["diag_warm"] = sorted(diag_times)[N//2]
        results["hover_warm"] = sorted(hover_times)[N//2]
        results["def_warm"] = sorted(def_times)[N//2]
        results["comp_warm"] = sorted(comp_times)[N//2]
        results["sym_warm"] = sorted(sym_times)[N//2]
        
        # Incremental: change + query
        change_times = []
        for i in range(5):
            changed = text.replace("undefined_global", f"undef_{i}", 1) if "undefined_global" in text else text[:-5] + str(i)
            t0 = time.monotonic()
            proc.stdin.write(make_msg({
                "jsonrpc": "2.0", "method": "textDocument/didChange",
                "params": {"textDocument": {"uri": uri, "version": 100+i},
                           "contentChanges": [{"text": changed}]}
            }))
            proc.stdin.flush()
            drain_notifications(proc, timeout=0.05)
            ms = query("textDocument/diagnostic", {"textDocument": {"uri": uri}})
            change_times.append((time.monotonic() - t0) * 1000)
        
        results["change_diag"] = sorted(change_times)[len(change_times)//2]
        
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
        except:
            proc.kill()
    
    return results

def read_file(path):
    try:
        with open(path) as f:
            return f.read()
    except:
        return None

def gen_file(n):
    lines = [
        "---@class TestClass", "---@field name string", "---@field id number",
        "local M = {}", "",
        "---@param name string", "---@param id number", "---@return TestClass",
        "function M.new(name, id)", "    return { name = name, id = id }", "end", "",
    ]
    for i in range(1, n+1):
        lines.append(f"local v{i} = {i}")
    lines += ["", f"print(v1, v{n})", "print(undefined_global)", "return M"]
    return "\n".join(lines)

# ══════════════════════════════════════════════════════════════

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

header = f"  {'file':<24s} {'lines':>5s} │ {'startup':>8s} {'diag':>8s} {'hover':>8s} {'go-def':>8s} {'compl':>8s} {'syms':>8s} {'chg+dg':>8s}"
sep = "  " + "-"*24 + " " + "-"*5 + " │ " + ("-"*8 + " ")*7

for server_label, server_cmd in [("pvm-lsp", PVM_LSP), ("LuaLS 3.16.4", [LUALS, "--stdio"])]:
    print(f"\n  ── {server_label} ──")
    print(header)
    print(sep)
    
    for label, text, uri in test_cases:
        lines = text.count("\n") + 1
        r = bench_server(server_cmd, label, uri, text)
        
        if "error" in r:
            print(f"  {label:<24s} {lines:5d} │ ERROR: {r['error'][:50]}")
            continue
        
        def fmt(key, default="  N/A"):
            v = r.get(key)
            if v is None or v < 0:
                return f"{default:>8s}"
            if v < 1:
                return f"{v*1000:6.0f} µs"
            return f"{v:6.1f} ms"
        
        print(f"  {label:<24s} {lines:5d} │ {fmt('startup')} {fmt('diag_warm')} {fmt('hover_warm')} {fmt('def_warm')} {fmt('comp_warm')} {fmt('sym_warm')} {fmt('change_diag')}")

print()
print("  startup  = init + didOpen + settle time")
print("  diag..syms = median of 20 cached round-trips (server already analyzed file)")
print("  chg+dg   = didChange(1 line) + diagnostic round-trip")
print("=" * 110)
