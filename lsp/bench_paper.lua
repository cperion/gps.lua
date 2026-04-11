#!/usr/bin/env luajit
-- lsp/bench_paper.lua
--
-- Comprehensive benchmark for the paper: pvm-lsp vs lua-language-server 3.16.4
-- Tests every operation at multiple file sizes, on synthetic and real files.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local lsp = require("lsp")

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
    }
    for i = 1, n do
        lines[#lines + 1] = string.format("local v%d = %d", i, i)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "local function helper(x)"
    lines[#lines + 1] = "    if x > 0 then return x * 2 end"
    lines[#lines + 1] = "    return 0"
    lines[#lines + 1] = "end"
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("for i = 1, %d do", n)
    lines[#lines + 1] = "    local _ = helper(i)"
    lines[#lines + 1] = "end"
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("print(v1, v%d, M.new('a', 1))", n)
    lines[#lines + 1] = "print(undefined_global)"
    lines[#lines + 1] = "return M"
    return table.concat(lines, "\n")
end

-- ── Benchmark harness ──────────────────────────────────────

local function bench(n, fn)
    -- warmup
    for _ = 1, math.min(10, n) do fn() end
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = os.clock()
    for _ = 1, n do fn() end
    return (os.clock() - t0) * 1e6 / n  -- microseconds
end

local function bench_one(fn)
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = os.clock()
    fn()
    return (os.clock() - t0) * 1e6
end

-- ── pvm-lsp benchmark ──────────────────────────────────────

local function bench_pvm(uri, text, label)
    local r = {}
    local lines = count_lines(text)
    r.lines = lines

    -- Cold open (fresh server each time)
    r.cold_open_us = bench(3, function()
        local c = lsp.server()
        c:handle("textDocument/didOpen", { textDocument = { uri = uri, version = 1, text = text } })
    end)

    -- Cold open + first diagnostic
    r.cold_diag_us = bench(3, function()
        local c = lsp.server()
        c:handle("textDocument/didOpen", { textDocument = { uri = uri, version = 1, text = text } })
        c:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    end)

    -- Now set up a warm server
    local core = lsp.server()
    core:handle("textDocument/didOpen", { textDocument = { uri = uri, version = 1, text = text } })

    -- Warm all caches
    local mid = math.floor(lines / 2)
    for _ = 1, 50 do
        core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
        core:handle("textDocument/hover", { textDocument = { uri = uri }, position = { line = mid, character = 6 } })
        core:handle("textDocument/definition", { textDocument = { uri = uri }, position = { line = mid, character = 6 } })
        core:handle("textDocument/references", { textDocument = { uri = uri }, position = { line = mid, character = 6 }, context = { includeDeclaration = true } })
        core:handle("textDocument/completion", { textDocument = { uri = uri }, position = { line = mid, character = 0 } })
        core:handle("textDocument/documentSymbol", { textDocument = { uri = uri } })
    end

    local N = 5000

    r.diag_cached_us = bench(N, function()
        core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    end)

    r.hover_cached_us = bench(N, function()
        core:handle("textDocument/hover", { textDocument = { uri = uri }, position = { line = mid, character = 6 } })
    end)

    r.def_cached_us = bench(N, function()
        core:handle("textDocument/definition", { textDocument = { uri = uri }, position = { line = mid, character = 6 } })
    end)

    r.refs_cached_us = bench(N, function()
        core:handle("textDocument/references", { textDocument = { uri = uri }, position = { line = mid, character = 6 }, context = { includeDeclaration = true } })
    end)

    r.comp_cached_us = bench(N, function()
        core:handle("textDocument/completion", { textDocument = { uri = uri }, position = { line = mid, character = 0 } })
    end)

    r.syms_cached_us = bench(N, function()
        core:handle("textDocument/documentSymbol", { textDocument = { uri = uri } })
    end)

    -- Incremental: change last line + full re-diagnostic
    r.incr_change_us = bench(20, function()
        local changed = text:sub(1, -20) .. tostring(math.random(999999))
        core:handle("textDocument/didChange", {
            textDocument = { uri = uri, version = math.random(999999) },
            contentChanges = { { text = changed } },
        })
        core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    end)

    -- Incremental: change middle line + hover at that line
    r.incr_hover_us = bench(20, function()
        local changed = text:sub(1, -20) .. tostring(math.random(999999))
        core:handle("textDocument/didChange", {
            textDocument = { uri = uri, version = math.random(999999) },
            contentChanges = { { text = changed } },
        })
        core:handle("textDocument/hover", { textDocument = { uri = uri }, position = { line = mid, character = 6 } })
    end)

    -- Count diagnostics and symbols
    local d = core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    r.diag_count = d and d.items and #d.items or 0
    local s = core:handle("textDocument/documentSymbol", { textDocument = { uri = uri } })
    r.sym_count = s and s.items and #s.items or 0
    local c = core:handle("textDocument/completion", { textDocument = { uri = uri }, position = { line = mid, character = 0 } })
    r.comp_count = c and c.items and #c.items or 0
    local idx = core.engine:index(core:_doc(uri).file)
    r.symbol_count = #idx.symbols

    return r
end

-- ── LuaLS benchmark via subprocess ─────────────────────────

local LUALS = os.getenv("HOME") .. "/.local/share/nvim/mason/bin/lua-language-server"

local json_encode = lsp.JsonRpc.json_encode

local function bench_luals(uri, text, label)
    local function make_msg(obj)
        local body = json_encode(obj)
        return "Content-Length: " .. #body .. "\r\n\r\n" .. body
    end

    local lines = count_lines(text)
    local mid = math.floor(lines / 2)
    local id = 0
    local function nid() id = id + 1; return id end

    local msgs = table.concat({
        make_msg({ jsonrpc="2.0", id=nid(), method="initialize",
            params={ processId=1, rootUri="file://"..os.getenv("PWD"), capabilities={} } }),
        make_msg({ jsonrpc="2.0", method="initialized", params={} }),
        make_msg({ jsonrpc="2.0", method="textDocument/didOpen",
            params={ textDocument={ uri=uri, languageId="lua", version=1, text=text } } }),
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
    })

    local tmp_in = os.tmpname()
    local tmp_out = os.tmpname()
    local f = io.open(tmp_in, "wb"); f:write(msgs); f:close()

    -- Run 3 times, take median
    local times = {}
    for trial = 1, 3 do
        local t0_ns = tonumber(io.popen("date +%s%N"):read("*l"))
        os.execute(string.format("timeout 30 %s --stdio < %s > %s 2>/dev/null", LUALS, tmp_in, tmp_out))
        local t1_ns = tonumber(io.popen("date +%s%N"):read("*l"))
        times[trial] = (t1_ns - t0_ns) / 1000  -- microseconds
    end
    table.sort(times)
    local wall_us = times[2]  -- median

    -- Count responses
    local out_f = io.open(tmp_out, "r")
    local out_data = out_f and out_f:read("*a") or ""
    if out_f then out_f:close() end
    local resp_count = 0
    for _ in out_data:gmatch("Content%-Length:") do resp_count = resp_count + 1 end

    os.remove(tmp_in)
    os.remove(tmp_out)

    return { wall_us = wall_us, responses = resp_count }
end

-- ══════════════════════════════════════════════════════════════
--  Run all benchmarks
-- ══════════════════════════════════════════════════════════════

print(("═"):rep(120))
print("  pvm-lsp vs lua-language-server 3.16.4 — comprehensive benchmark")
print(("═"):rep(120))

local test_cases = {}
for _, n in ipairs({50, 100, 200, 500}) do
    test_cases[#test_cases + 1] = { string.format("%d locals", n), gen_file(n), "file:///gen_"..n..".lua" }
end
for _, name in ipairs({
    "pvm.lua", "triplet.lua", "asdl_context.lua", "quote.lua",
    "lsp/semantics.lua", "lsp/parser.lua", "lsp/lexer.lua",
    "ui/demo/app.lua", "ui/session.lua", "ui/draw.lua",
}) do
    local text = read_file(name)
    if text then test_cases[#test_cases + 1] = { name, text, "file://"..os.getenv("PWD").."/"..name } end
end

-- ── Table 1: Cold start ────────────────────────────────────
print("\n┌─ Table 1: Cold Start (ms) ─────────────────────────────────────────────────┐")
print(string.format("│ %-24s %5s │ %9s %9s │ %9s %5s │ %7s │",
    "file", "lines", "pvm open", "pvm diag", "LuaLS", "resps", "factor"))
print("│" .. ("-"):rep(118) .. "│")

for _, tc in ipairs(test_cases) do
    local label, text, uri = tc[1], tc[2], tc[3]
    local p = bench_pvm(uri, text, label)
    local l = bench_luals(uri, text, label)
    local factor = l.wall_us > 0 and l.wall_us / p.cold_diag_us or 0
    print(string.format("│ %-24s %5d │ %7.1f ms %7.1f ms │ %7.1f ms %5d │ %5.1fx  │",
        label, p.lines,
        p.cold_open_us / 1000,
        p.cold_diag_us / 1000,
        l.wall_us / 1000,
        l.responses,
        factor))
end
print("└" .. ("─"):rep(118) .. "┘")

-- ── Table 2: Cached queries ────────────────────────────────
print("\n┌─ Table 2: Cached Query Latency (µs) — file unchanged ─────────────────────────────────────┐")
print(string.format("│ %-24s %5s │ %8s %8s %8s %8s %8s %8s │",
    "file", "lines", "diag", "hover", "go-def", "refs", "compl", "symbols"))
print("│" .. ("-"):rep(96) .. "│")

for _, tc in ipairs(test_cases) do
    local label, text, uri = tc[1], tc[2], tc[3]
    local p = bench_pvm(uri, text, label)
    print(string.format("│ %-24s %5d │ %6.1f µs %6.1f µs %6.1f µs %6.1f µs %6.1f µs %6.1f µs │",
        label, p.lines,
        p.diag_cached_us, p.hover_cached_us, p.def_cached_us,
        p.refs_cached_us, p.comp_cached_us, p.syms_cached_us))
end
print("└" .. ("─"):rep(96) .. "┘")

-- ── Table 3: Incremental ──────────────────────────────────
print("\n┌─ Table 3: Incremental Edit (ms) — change 1 line ──────────────────────────┐")
print(string.format("│ %-24s %5s │ %10s %10s │",
    "file", "lines", "chg+diag", "chg+hover"))
print("│" .. ("-"):rep(60) .. "│")

for _, tc in ipairs(test_cases) do
    local label, text, uri = tc[1], tc[2], tc[3]
    local p = bench_pvm(uri, text, label)
    print(string.format("│ %-24s %5d │ %8.1f ms %8.1f ms │",
        label, p.lines,
        p.incr_change_us / 1000,
        p.incr_hover_us / 1000))
end
print("└" .. ("─"):rep(60) .. "┘")

-- ── Table 4: Feature coverage ──────────────────────────────
print("\n┌─ Table 4: Analysis Output ─────────────────────────────────────────────────┐")
print(string.format("│ %-24s %5s │ %6s %6s %6s %6s │",
    "file", "lines", "syms", "diags", "d.syms", "compl"))
print("│" .. ("-"):rep(68) .. "│")

for _, tc in ipairs(test_cases) do
    local label, text, uri = tc[1], tc[2], tc[3]
    local p = bench_pvm(uri, text, label)
    print(string.format("│ %-24s %5d │ %6d %6d %6d %6d │",
        label, p.lines,
        p.symbol_count, p.diag_count, p.sym_count, p.comp_count))
end
print("└" .. ("─"):rep(68) .. "┘")

-- ── Summary ────────────────────────────────────────────────
print("\n" .. ("═"):rep(120))
print("  Notes:")
print("    pvm-lsp: in-process LuaJIT, measures pure operation time")
print("    LuaLS 3.16.4: subprocess, init → open → diag → hover → def → refs → compl → syms → shutdown")
print("    'cached': same file, no changes since last query — pure pvm cache hit")
print("    'chg+diag': didChange(1 line) + diagnostic — incremental re-analysis")
print("    factor: LuaLS wall / pvm cold_diag (higher = pvm faster)")
print(("═"):rep(120))
