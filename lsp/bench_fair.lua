#!/usr/bin/env luajit
-- lsp/bench_fair.lua
--
-- FAIR benchmark: both servers run as subprocesses over stdio JSON-RPC.
-- Same messages, same measurement method, same IPC overhead.

package.path = "./?.lua;./?/init.lua;" .. package.path

local json_encode = require("lsp.jsonrpc").json_encode

local LUALS = os.getenv("HOME") .. "/.local/share/nvim/mason/bin/lua-language-server"
local PVM_LSP = "luajit lsp/main.lua"

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local t = f:read("*a"); f:close(); return t
end

local function count_lines(text)
    local n = 1; for _ in text:gmatch("\n") do n = n + 1 end; return n
end

local function gen_file(n)
    local lines = {
        "---@class TestClass", "---@field name string", "---@field id number",
        "local M = {}", "",
        "---@param name string", "---@param id number", "---@return TestClass",
        "function M.new(name, id)", "    return { name = name, id = id }", "end", "",
    }
    for i = 1, n do lines[#lines + 1] = string.format("local v%d = %d", i, i) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("print(v1, v%d)", n)
    lines[#lines + 1] = "print(undefined_global)"
    lines[#lines + 1] = "return M"
    return table.concat(lines, "\n")
end

local function make_msg(obj)
    local body = json_encode(obj)
    return "Content-Length: " .. #body .. "\r\n\r\n" .. body
end

-- Build a full session: init → open → diag → hover → def → refs → compl → syms → shutdown
local function build_session(uri, text)
    local lines = count_lines(text)
    local mid = math.floor(lines / 2)
    local id = 0
    local function nid() id = id + 1; return id end

    return table.concat({
        make_msg({ jsonrpc="2.0", id=nid(), method="initialize",
            params={ processId=1, rootUri="file://"..os.getenv("PWD"),
                capabilities={ textDocument={ diagnostic={dynamicRegistration=false} } } } }),
        make_msg({ jsonrpc="2.0", method="initialized", params={} }),
        make_msg({ jsonrpc="2.0", method="textDocument/didOpen",
            params={ textDocument={ uri=uri, languageId="lua", version=1, text=text } } }),
        -- small sleep to let server process didOpen
        make_msg({ jsonrpc="2.0", id=nid(), method="textDocument/diagnostic",
            params={ textDocument={ uri=uri } } }),
        make_msg({ jsonrpc="2.0", id=nid(), method="textDocument/hover",
            params={ textDocument={ uri=uri }, position={ line=mid, character=6 } } }),
        make_msg({ jsonrpc="2.0", id=nid(), method="textDocument/definition",
            params={ textDocument={ uri=uri }, position={ line=mid, character=6 } } }),
        make_msg({ jsonrpc="2.0", id=nid(), method="textDocument/references",
            params={ textDocument={ uri=uri }, position={ line=mid, character=6 },
                context={ includeDeclaration=true } } }),
        make_msg({ jsonrpc="2.0", id=nid(), method="textDocument/completion",
            params={ textDocument={ uri=uri }, position={ line=mid, character=0 } } }),
        make_msg({ jsonrpc="2.0", id=nid(), method="textDocument/documentSymbol",
            params={ textDocument={ uri=uri } } }),
        make_msg({ jsonrpc="2.0", id=nid(), method="shutdown" }),
        make_msg({ jsonrpc="2.0", method="exit" }),
    }), id
end

local function run_server(cmd, input_data, timeout_s)
    local tmp_in = os.tmpname()
    local tmp_out = os.tmpname()
    local f = io.open(tmp_in, "wb"); f:write(input_data); f:close()

    local t0_ns = tonumber(io.popen("date +%s%N"):read("*l"))
    os.execute(string.format("timeout %d bash -c '%s < %s > %s 2>/dev/null'",
        timeout_s or 30, cmd, tmp_in, tmp_out))
    local t1_ns = tonumber(io.popen("date +%s%N"):read("*l"))
    local wall_ms = (t1_ns - t0_ns) / 1e6

    -- Count responses
    local out_f = io.open(tmp_out, "r")
    local out_data = out_f and out_f:read("*a") or ""
    if out_f then out_f:close() end
    local resp_count = 0
    for _ in out_data:gmatch("Content%-Length:") do resp_count = resp_count + 1 end

    -- Measure response sizes
    local total_bytes = #out_data

    os.remove(tmp_in)
    os.remove(tmp_out)
    return wall_ms, resp_count, total_bytes
end

-- ══════════════════════════════════════════════════════════════

print(("═"):rep(100))
print("  FAIR BENCHMARK: both servers as stdio subprocesses")
print("  Same JSON-RPC messages, same IPC overhead, same measurement")
print(("═"):rep(100))
print()
print("  pvm-lsp: luajit lsp/main.lua --stdio")
print("  LuaLS:   lua-language-server 3.16.4 --stdio")
print()

local test_cases = {}
for _, n in ipairs({50, 100, 200, 500}) do
    test_cases[#test_cases + 1] = { string.format("%d locals", n), gen_file(n), "file:///gen_"..n..".lua" }
end
for _, name in ipairs({"pvm.lua", "triplet.lua", "asdl_context.lua", "lsp/semantics.lua", "lsp/parser.lua", "ui/demo/app.lua", "ui/session.lua"}) do
    local text = read_file(name)
    if text then
        test_cases[#test_cases + 1] = { name, text, "file://"..os.getenv("PWD").."/"..name }
    end
end

print(string.format("  %-24s %5s │ %9s %5s │ %9s %5s │ %7s",
    "file", "lines", "pvm-lsp", "resps", "LuaLS", "resps", "factor"))
print("  " .. ("-"):rep(24) .. " " .. ("-"):rep(5) ..
    " │ " .. ("-"):rep(9) .. " " .. ("-"):rep(5) ..
    " │ " .. ("-"):rep(9) .. " " .. ("-"):rep(5) ..
    " │ " .. ("-"):rep(7))

for _, tc in ipairs(test_cases) do
    local label, text, uri = tc[1], tc[2], tc[3]
    local lines = count_lines(text)
    local session, req_count = build_session(uri, text)

    -- Run each 3 times, take median
    local pvm_times, luals_times = {}, {}

    for trial = 1, 3 do
        local ms, resps = run_server(PVM_LSP, session, 30)
        pvm_times[trial] = { ms = ms, resps = resps }
    end

    for trial = 1, 3 do
        local ms, resps = run_server(LUALS .. " --stdio", session, 30)
        luals_times[trial] = { ms = ms, resps = resps }
    end

    table.sort(pvm_times, function(a,b) return a.ms < b.ms end)
    table.sort(luals_times, function(a,b) return a.ms < b.ms end)

    local pvm = pvm_times[2]    -- median
    local luals = luals_times[2] -- median

    local factor = (luals.ms > 0 and pvm.ms > 0) and luals.ms / pvm.ms or 0

    print(string.format("  %-24s %5d │ %7.0f ms %5d │ %7.0f ms %5d │ %5.1fx",
        label, lines, pvm.ms, pvm.resps, luals.ms, luals.resps, factor))
end

print()
print("  Session: initialize → didOpen → diagnostic → hover → definition →")
print("           references → completion → documentSymbol → shutdown")
print("  Measurement: wall-clock time for full subprocess lifecycle")
print("  Factor: LuaLS / pvm-lsp (>1 means pvm-lsp is faster)")
print(("═"):rep(100))
