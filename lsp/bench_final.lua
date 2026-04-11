#!/usr/bin/env luajit
-- lsp/bench_final.lua — Final head-to-head comparison
package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local function gen_file(n)
    local lines = {
        "---@class TestClass", "---@field name string", "---@field id number",
        "local M = {}", "",
    }
    for i = 1, n do lines[#lines + 1] = string.format("local v%d = %d", i, i) end
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
    local t = f:read("*a"); f:close(); return t
end

local function count_lines(text)
    local n = 1; for _ in text:gmatch("\n") do n = n + 1 end; return n
end

-- Full server round-trip: create server, open, diagnostic, hover, def, change+diag
local function bench_roundtrip(uri, text)
    local lsp = require("lsp")
    local core = lsp.server()

    local t0 = os.clock()

    -- Initialize (no-op for us but included for fairness)
    core:handle("textDocument/didOpen", {
        textDocument = { uri = uri, version = 1, text = text },
    })
    local d = core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    local line_count = count_lines(text)
    core:handle("textDocument/hover", {
        textDocument = { uri = uri },
        position = { line = math.floor(line_count/2), character = 6 },
    })
    core:handle("textDocument/definition", {
        textDocument = { uri = uri },
        position = { line = math.floor(line_count/2), character = 6 },
    })

    local total_ms = (os.clock() - t0) * 1e3

    -- Now measure change + re-diagnostic
    t0 = os.clock()
    local changed = text:gsub("undefined_global", "undefined_xxx")
    core:handle("textDocument/didChange", {
        textDocument = { uri = uri, version = 2 },
        contentChanges = { { text = changed } },
    })
    core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    local change_ms = (os.clock() - t0) * 1e3

    -- Cached diagnostic
    local N = 2000
    collectgarbage(); collectgarbage()
    t0 = os.clock()
    for _ = 1, N do
        core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    end
    local cached_us = (os.clock() - t0) * 1e6 / N

    return total_ms, change_ms, cached_us
end

-- ══════════════════════════════════════════════════════════════

local test_cases = {
    { "50 locals",   gen_file(50),   "file:///gen50.lua" },
    { "200 locals",  gen_file(200),  "file:///gen200.lua" },
    { "500 locals",  gen_file(500),  "file:///gen500.lua" },
    { "1000 locals", gen_file(1000), "file:///gen1000.lua" },
}
for _, name in ipairs({"pvm.lua", "triplet.lua", "asdl_context.lua", "lsp/semantics.lua", "lsp/parser.lua"}) do
    local text = read_file(name)
    if text then
        test_cases[#test_cases + 1] = { name, text, "file://"..name }
    end
end

print(string.format("\n%s", ("="):rep(80)))
print("  pvm-lsp vs lua-language-server 3.16.4")
print(("="):rep(80))
print(string.format("\n  %-26s %6s │ %9s %9s %9s │ %9s",
    "", "lines", "open+ops", "chg+diag", "diag(hit)", "LuaLS"))
print("  " .. ("-"):rep(26) .. " " .. ("-"):rep(6) ..
    " │ " .. ("-"):rep(9) .. " " .. ("-"):rep(9) .. " " .. ("-"):rep(9) ..
    " │ " .. ("-"):rep(9))

-- LuaLS numbers from bench_luals.sh (run separately since it's a subprocess)
local luals_times = {
    ["50 locals"]          = 138,
    ["200 locals"]         = 137,
    ["500 locals"]         = 136,
    ["1000 locals"]        = 134,
    ["pvm.lua"]            = 140,
    ["triplet.lua"]        = 136,
    ["asdl_context.lua"]   = 32,
    ["lsp/semantics.lua"]  = 139,
    ["lsp/parser.lua"]     = 134,
}

for _, tc in ipairs(test_cases) do
    local label, text, uri = tc[1], tc[2], tc[3]
    local lines = count_lines(text)
    local total_ms, change_ms, cached_us = bench_roundtrip(uri, text)
    local luals_ms = luals_times[label] or -1

    local speedup = ""
    if luals_ms > 0 then
        speedup = string.format("  %5.0fx", luals_ms / total_ms)
    end

    print(string.format("  %-26s %5dL │ %7.1f ms %7.1f ms %7.1f µs │ %7d ms%s",
        label, lines, total_ms, change_ms, cached_us, luals_ms, speedup))
end

print(string.format("\n  %-26s %6s │ %9s %9s %9s │ %9s",
    "", "", "pvm-lsp", "pvm-lsp", "pvm-lsp", "LuaLS"))
print("\n  open+ops  = didOpen + diagnostic + hover + definition (cold)")
print("  chg+diag  = didChange(1 line) + diagnostic (incremental)")
print("  diag(hit) = diagnostic on unchanged file (pure cache)")
print("  LuaLS     = full subprocess: init → open → diag → hover → def → shutdown")
