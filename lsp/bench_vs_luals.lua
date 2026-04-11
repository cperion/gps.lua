#!/usr/bin/env luajit
-- lsp/bench_vs_luals.lua
--
-- Head-to-head benchmark: our pvm LSP vs lua-language-server 3.16.4
-- Sends identical JSON-RPC messages over stdio to both servers.

package.path = "./?.lua;./?/init.lua;" .. package.path

local LUALS_BIN = os.getenv("LUALS_BIN")
    or os.getenv("HOME") .. "/.local/share/nvim/mason/bin/lua-language-server"

-- ── JSON codec (reuse ours) ────────────────────────────────
local JsonRpc = require("lsp.jsonrpc")
local json_encode = JsonRpc.json_encode
local json_decode = JsonRpc.json_decode

-- ── Subprocess JSON-RPC client ─────────────────────────────
local function rpc_client(cmd)
    local proc = io.popen(cmd, "w")  -- won't work for bidirectional
    -- We need bidirectional IO. Use a temp-file approach instead.
    if proc then proc:close() end
    return nil
end

-- Since Lua doesn't have great bidirectional pipe support,
-- let's use our own server in-process and LuaLS via a timed script.

-- ── Generate test files of various sizes ───────────────────
local function gen_file(n_locals)
    local lines = {
        "---@class TestClass",
        "---@field name string",
        "---@field id number",
        "local M = {}",
        "",
    }
    for i = 1, n_locals do
        lines[#lines + 1] = string.format("local v%d = %d", i, i)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "function M.process(x, y)"
    lines[#lines + 1] = "    return x + y"
    lines[#lines + 1] = "end"
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("print(v1, v%d)", n_locals)
    lines[#lines + 1] = "print(M.process(1, 2))"
    lines[#lines + 1] = "print(undefined_global)"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "return M"
    return table.concat(lines, "\n")
end

-- Also use a real file from the codebase
local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

-- ── Benchmark our LSP (in-process) ────────────────────────
local function bench_ours(uri, text, label)
    local lsp = require("lsp")
    local core = lsp.server()
    local C = core.engine.C

    local results = {}

    -- Cold open + parse
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    core:handle("textDocument/didOpen", {
        textDocument = { uri = uri, version = 1, text = text },
    })
    results.open_us = (os.clock() - t0) * 1e6

    -- Diagnostics (first = includes parse cache)
    t0 = os.clock()
    local d = core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    results.diag_first_us = (os.clock() - t0) * 1e6
    results.diag_count = d and d.items and #d.items or 0

    -- Diagnostics (cached)
    local iters = 1000
    collectgarbage(); collectgarbage()
    t0 = os.clock()
    for _ = 1, iters do
        core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    end
    results.diag_cached_us = (os.clock() - t0) * 1e6 / iters

    -- Hover (pick middle of file)
    local line_count = 1
    for _ in text:gmatch("\n") do line_count = line_count + 1 end
    local hover_line = math.floor(line_count / 2)

    t0 = os.clock()
    for _ = 1, iters do
        core:handle("textDocument/hover", {
            textDocument = { uri = uri },
            position = { line = hover_line, character = 6 },
        })
    end
    results.hover_us = (os.clock() - t0) * 1e6 / iters

    -- Definition
    t0 = os.clock()
    for _ = 1, iters do
        core:handle("textDocument/definition", {
            textDocument = { uri = uri },
            position = { line = hover_line, character = 6 },
        })
    end
    results.definition_us = (os.clock() - t0) * 1e6 / iters

    -- Change + re-diagnostic (incremental)
    local changed = text:gsub("undefined_global", "undefined_changed")
    local change_iters = 50
    collectgarbage(); collectgarbage()
    t0 = os.clock()
    for i = 1, change_iters do
        local ct = text:gsub("undefined_global", "undef_" .. tostring(i))
        core:handle("textDocument/didChange", {
            textDocument = { uri = uri, version = 100 + i },
            contentChanges = { { text = ct } },
        })
        core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    end
    results.change_diag_us = (os.clock() - t0) * 1e6 / change_iters

    return results
end

-- ── Benchmark LuaLS via subprocess ─────────────────────────
-- We time the full round-trip: spawn → initialize → open → diagnostic → shutdown
local function bench_luals_roundtrip(uri, text, label)
    -- Build the JSON-RPC messages
    local msg_id = 0
    local function next_id() msg_id = msg_id + 1; return msg_id end

    local function make_msg(obj)
        local body = json_encode(obj)
        return "Content-Length: " .. #body .. "\r\n\r\n" .. body
    end

    local init_id = next_id()
    local diag_id = next_id()
    local hover_id = next_id()
    local def_id = next_id()
    local shutdown_id = next_id()

    local line_count = 1
    for _ in text:gmatch("\n") do line_count = line_count + 1 end
    local hover_line = math.floor(line_count / 2)

    local messages = {
        make_msg({
            jsonrpc = "2.0", id = init_id, method = "initialize",
            params = {
                processId = nil,
                rootUri = "file://" .. os.getenv("PWD"),
                capabilities = {},
            },
        }),
        make_msg({ jsonrpc = "2.0", method = "initialized", params = {} }),
        make_msg({
            jsonrpc = "2.0", method = "textDocument/didOpen",
            params = {
                textDocument = { uri = uri, languageId = "lua", version = 1, text = text },
            },
        }),
        -- Pull diagnostics
        make_msg({
            jsonrpc = "2.0", id = diag_id, method = "textDocument/diagnostic",
            params = { textDocument = { uri = uri } },
        }),
        -- Hover
        make_msg({
            jsonrpc = "2.0", id = hover_id, method = "textDocument/hover",
            params = {
                textDocument = { uri = uri },
                position = { line = hover_line, character = 6 },
            },
        }),
        -- Definition
        make_msg({
            jsonrpc = "2.0", id = def_id, method = "textDocument/definition",
            params = {
                textDocument = { uri = uri },
                position = { line = hover_line, character = 6 },
            },
        }),
        -- Shutdown
        make_msg({ jsonrpc = "2.0", id = shutdown_id, method = "shutdown", params = {} }),
        make_msg({ jsonrpc = "2.0", method = "exit", params = {} }),
    }

    local input = table.concat(messages)

    -- Write input to temp file
    local tmp_in = os.tmpname()
    local f = io.open(tmp_in, "wb")
    f:write(input)
    f:close()

    -- Time the full round-trip
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    local cmd = string.format("%s --stdio < %s > /dev/null 2>/dev/null",
        LUALS_BIN, tmp_in)
    os.execute(cmd)
    local total_us = (os.clock() - t0) * 1e6

    os.remove(tmp_in)
    return { total_roundtrip_us = total_us }
end

-- Also time with `time` for wall-clock
local function bench_luals_wall(uri, text)
    local msg_id = 0
    local function next_id() msg_id = msg_id + 1; return msg_id end
    local function make_msg(obj)
        local body = json_encode(obj)
        return "Content-Length: " .. #body .. "\r\n\r\n" .. body
    end

    local messages = {
        make_msg({
            jsonrpc = "2.0", id = next_id(), method = "initialize",
            params = { processId = nil, rootUri = "file://" .. os.getenv("PWD"), capabilities = {} },
        }),
        make_msg({ jsonrpc = "2.0", method = "initialized", params = {} }),
        make_msg({
            jsonrpc = "2.0", method = "textDocument/didOpen",
            params = { textDocument = { uri = uri, languageId = "lua", version = 1, text = text } },
        }),
        make_msg({
            jsonrpc = "2.0", id = next_id(), method = "textDocument/diagnostic",
            params = { textDocument = { uri = uri } },
        }),
        make_msg({ jsonrpc = "2.0", id = next_id(), method = "shutdown", params = {} }),
        make_msg({ jsonrpc = "2.0", method = "exit", params = {} }),
    }

    local tmp_in = os.tmpname()
    local tmp_out = os.tmpname()
    local f = io.open(tmp_in, "wb")
    f:write(table.concat(messages))
    f:close()

    -- Use /usr/bin/time for wall clock
    local cmd = string.format(
        "{ time %s --stdio < %s > %s 2>/dev/null ; } 2>&1",
        LUALS_BIN, tmp_in, tmp_out)
    local p = io.popen(cmd)
    local time_out = p:read("*a")
    p:close()

    -- Parse response to count diagnostics
    local resp_f = io.open(tmp_out, "r")
    local resp = resp_f and resp_f:read("*a") or ""
    if resp_f then resp_f:close() end

    os.remove(tmp_in)
    os.remove(tmp_out)

    -- Extract real time
    local real = time_out:match("real%s+(%d+m[%d%.]+s)") or time_out:match("(%d+%.%d+)")
    return real or time_out:gsub("%s+", " "):sub(1, 60), resp:sub(1, 200)
end

-- ══════════════════════════════════════════════════════════════
--  Run benchmarks
-- ══════════════════════════════════════════════════════════════

print("=" .. ("="):rep(70))
print("  pvm-lsp vs lua-language-server " .. "3.16.4")
print("=" .. ("="):rep(70))

local sizes = { 50, 200, 500 }
local real_files = {
    { "pvm.lua", read_file("pvm.lua") },
    { "triplet.lua", read_file("triplet.lua") },
    { "asdl_context.lua", read_file("asdl_context.lua") },
    { "lsp/semantics.lua", read_file("lsp/semantics.lua") },
}

-- ── Our LSP ────────────────────────────────────────────────
print("\n── pvm-lsp (in-process, LuaJIT) ──")
print(string.format("  %-30s %8s %8s %8s %8s %8s %8s  %s",
    "file", "open", "diag1st", "diag$", "hover$", "def$", "chg+dg", "diags"))

for _, n in ipairs(sizes) do
    local text = gen_file(n)
    local label = n .. " locals"
    local r = bench_ours("file:///gen_" .. n .. ".lua", text, label)
    print(string.format("  %-30s %7.0fus %7.0fus %7.1fus %7.1fus %7.1fus %7.0fus  %d",
        label, r.open_us, r.diag_first_us, r.diag_cached_us,
        r.hover_us, r.definition_us, r.change_diag_us, r.diag_count))
end

for _, rf in ipairs(real_files) do
    if rf[2] then
        local r = bench_ours("file:///" .. rf[1], rf[2], rf[1])
        local lines = 1; for _ in rf[2]:gmatch("\n") do lines = lines + 1 end
        print(string.format("  %-30s %7.0fus %7.0fus %7.1fus %7.1fus %7.1fus %7.0fus  %d",
            rf[1] .. " (" .. lines .. "L)", r.open_us, r.diag_first_us, r.diag_cached_us,
            r.hover_us, r.definition_us, r.change_diag_us, r.diag_count))
    end
end

-- ── LuaLS ──────────────────────────────────────────────────
print("\n── lua-language-server 3.16.4 (subprocess, full round-trip) ──")
print("  (initialize → didOpen → diagnostic → shutdown)")
print(string.format("  %-30s %s", "file", "wall time"))

for _, n in ipairs(sizes) do
    local text = gen_file(n)
    local uri = "file://" .. os.getenv("PWD") .. "/gen_" .. n .. ".lua"
    -- Write temp file so LuaLS can find it
    local tmp = "gen_" .. n .. ".lua"
    local f = io.open(tmp, "w"); f:write(text); f:close()
    local wall, _ = bench_luals_wall(uri, text)
    os.remove(tmp)
    print(string.format("  %-30s %s", n .. " locals", wall))
end

for _, rf in ipairs(real_files) do
    if rf[2] then
        local uri = "file://" .. os.getenv("PWD") .. "/" .. rf[1]
        local wall, _ = bench_luals_wall(uri, rf[2])
        local lines = 1; for _ in rf[2]:gmatch("\n") do lines = lines + 1 end
        print(string.format("  %-30s %s", rf[1] .. " (" .. lines .. "L)", wall))
    end
end

print("\n── Notes ──")
print("  pvm-lsp: in-process LuaJIT, no startup cost, measures pure operation time")
print("  LuaLS: subprocess, includes startup/init/shutdown overhead")
print("  'diag$' = cached diagnostic (same file, no changes)")
print("  'chg+dg' = change one line + re-diagnostic")
print("  LuaLS wall time = total time for init→open→diag→shutdown round-trip")
