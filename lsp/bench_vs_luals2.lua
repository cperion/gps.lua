#!/usr/bin/env luajit
-- lsp/bench_vs_luals2.lua
--
-- Proper bidirectional benchmark: reads actual responses from LuaLS.
-- Uses luajit's io.popen workaround via a helper script.

package.path = "./?.lua;./?/init.lua;" .. package.path

local JsonRpc = require("lsp.jsonrpc")
local json_encode = JsonRpc.json_encode
local json_decode = JsonRpc.json_decode

local LUALS_BIN = os.getenv("LUALS_BIN")
    or os.getenv("HOME") .. "/.local/share/nvim/mason/bin/lua-language-server"

-- ── Generate test files ────────────────────────────────────
local function gen_file(n)
    local lines = {
        "---@class TestClass",
        "---@field name string",
        "---@field id number",
        "local M = {}",
        "",
    }
    for i = 1, n do
        lines[#lines + 1] = string.format("local v%d = %d", i, i)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "function M.process(x, y)"
    lines[#lines + 1] = "    return x + y"
    lines[#lines + 1] = "end"
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("print(v1, v%d)", n)
    lines[#lines + 1] = "print(undefined_global)"
    lines[#lines + 1] = "return M"
    return table.concat(lines, "\n")
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a"); f:close()
    return text
end

-- ── Build a helper script that does the bidirectional IO ───
local function bench_luals_proper(uri, text, label)
    -- Write a Lua script that acts as an LSP client
    local client_script = string.format([=[
local io = require("io")
local os = require("os")

local function write_msg(obj)
    local json = require("cjson")
    local body = json.encode(obj)
    io.stdout:write("Content-Length: " .. #body .. "\r\n\r\n" .. body)
    io.stdout:flush()
end

local function read_msg()
    local headers = {}
    while true do
        local line = io.stdin:read("*l")
        if not line or line == "" or line == "\r" then break end
        line = line:gsub("\r$", "")
        local k, v = line:match("^([^:]+):%%s*(.*)")
        if k then headers[k:lower()] = v end
    end
    local len = tonumber(headers["content-length"])
    if not len then return nil end
    local body = io.stdin:read(len)
    if not body then return nil end
    local json = require("cjson")
    return json.decode(body)
end

-- We can't easily use cjson in a piped context. Use a simpler approach.
]=], "")

    -- Actually, let's use a shell pipeline approach instead.
    -- Write all messages to a file, pipe through LuaLS, capture output, measure.
    
    local function make_msg(obj)
        local body = json_encode(obj)
        return "Content-Length: " .. #body .. "\r\n\r\n" .. body
    end

    local id = 0
    local function nid() id = id + 1; return id end

    local line_count = 1
    for _ in text:gmatch("\n") do line_count = line_count + 1 end

    local msgs = table.concat({
        make_msg({ jsonrpc="2.0", id=nid(), method="initialize",
            params={ processId=vim and vim.fn.getpid() or 1, rootUri="file://"..os.getenv("PWD"),
                capabilities={textDocument={diagnostic={dynamicRegistration=false}}} } }),
        make_msg({ jsonrpc="2.0", method="initialized", params={} }),
        make_msg({ jsonrpc="2.0", method="textDocument/didOpen",
            params={ textDocument={ uri=uri, languageId="lua", version=1, text=text } } }),
        -- Wait a bit then request diagnostics
        make_msg({ jsonrpc="2.0", id=nid(), method="textDocument/diagnostic",
            params={ textDocument={ uri=uri } } }),
        make_msg({ jsonrpc="2.0", id=nid(), method="textDocument/hover",
            params={ textDocument={ uri=uri }, position={ line=math.floor(line_count/2), character=6 } } }),
        make_msg({ jsonrpc="2.0", id=nid(), method="textDocument/definition",
            params={ textDocument={ uri=uri }, position={ line=math.floor(line_count/2), character=6 } } }),
        make_msg({ jsonrpc="2.0", id=nid(), method="shutdown" }),
        make_msg({ jsonrpc="2.0", method="exit" }),
    })

    local tmp_in = os.tmpname()
    local tmp_out = os.tmpname()
    local f = io.open(tmp_in, "wb"); f:write(msgs); f:close()

    -- Use /usr/bin/time for precise wall-clock measurement
    local cmd = string.format(
        "/usr/bin/time -f '%%e' %s --stdio < %s > %s 2>&1",
        LUALS_BIN, tmp_in, tmp_out)
    local p = io.popen(cmd)
    local time_output = p:read("*a") or ""
    p:close()

    -- Parse wall time (last line should be seconds)
    local wall_s = tonumber(time_output:match("([%d%.]+)%s*$"))

    -- Count response messages
    local out_f = io.open(tmp_out, "r")
    local out_data = out_f and out_f:read("*a") or ""
    if out_f then out_f:close() end

    local resp_count = 0
    for _ in out_data:gmatch("Content%-Length:") do resp_count = resp_count + 1 end

    os.remove(tmp_in)
    os.remove(tmp_out)

    return wall_s, resp_count
end

-- ── Our LSP benchmark ──────────────────────────────────────
local function bench_ours(uri, text)
    local lsp = require("lsp")
    local core = lsp.server()

    local results = {}

    -- Open (includes parse)
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    core:handle("textDocument/didOpen", {
        textDocument = { uri = uri, version = 1, text = text },
    })
    results.open_ms = (os.clock() - t0) * 1e3

    -- Diagnostic first
    t0 = os.clock()
    core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    results.diag_ms = (os.clock() - t0) * 1e3

    -- Diagnostic cached
    local N = 5000
    t0 = os.clock()
    for _ = 1, N do
        core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    end
    results.diag_cached_us = (os.clock() - t0) * 1e6 / N

    -- Change + diagnostic
    t0 = os.clock()
    local ct = text:gsub("undefined_global", "undefined_xxx")
    core:handle("textDocument/didChange", {
        textDocument = { uri = uri, version = 2 },
        contentChanges = { { text = ct } },
    })
    core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    results.change_diag_ms = (os.clock() - t0) * 1e3

    results.total_ms = results.open_ms + results.diag_ms

    return results
end

-- ══════════════════════════════════════════════════════════════
print(string.format("\n%s", ("="):rep(75)))
print("  pvm-lsp vs lua-language-server 3.16.4 — head-to-head")
print(("="):rep(75))

local test_cases = {
    { "50 locals",   gen_file(50),  "file:///gen50.lua" },
    { "200 locals",  gen_file(200), "file:///gen200.lua" },
    { "500 locals",  gen_file(500), "file:///gen500.lua" },
    { "1000 locals", gen_file(1000), "file:///gen1000.lua" },
}

-- Add real files
for _, name in ipairs({"pvm.lua", "triplet.lua", "asdl_context.lua", "lsp/semantics.lua", "lsp/parser.lua"}) do
    local text = read_file(name)
    if text then
        local lines = 1; for _ in text:gmatch("\n") do lines = lines + 1 end
        test_cases[#test_cases + 1] = { name.." ("..lines.."L)", text, "file://"..os.getenv("PWD").."/"..name }
    end
end

print(string.format("\n  %-28s │ %10s %10s %10s │ %10s %6s",
    "", "open+diag", "diag(hit)", "chg+diag", "LuaLS wall", "resps"))
print("  " .. ("-"):rep(28) .. "─┼─" .. ("-"):rep(35) .. "─┼─" .. ("-"):rep(18))

for _, tc in ipairs(test_cases) do
    local label, text, uri = tc[1], tc[2], tc[3]

    -- Our LSP
    local ours = bench_ours(uri, text)

    -- LuaLS
    local luals_s, luals_resps = bench_luals_proper(uri, text, label)
    local luals_ms = luals_s and (luals_s * 1000) or -1

    print(string.format("  %-28s │ %8.1f ms %8.1f µs %8.1f ms │ %8.1f ms %4d",
        label,
        ours.total_ms,
        ours.diag_cached_us,
        ours.change_diag_ms,
        luals_ms,
        luals_resps))
end

print("\n  pvm-lsp: open+diag = cold parse + first diagnostic")
print("  pvm-lsp: diag(hit) = cached diagnostic, no changes")
print("  pvm-lsp: chg+diag = change 1 line + re-diagnostic")
print("  LuaLS: wall = total init→open→diag→hover→def→shutdown")
