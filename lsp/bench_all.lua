#!/usr/bin/env luajit
-- lsp/bench_all.lua — Benchmark every feature on real codebase files
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

local function bench(n, fn)
    for _ = 1, math.min(5, n) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, n do fn() end
    return (os.clock() - t0) * 1e6 / n
end

local files = {
    { "pvm.lua",            read_file("pvm.lua") },
    { "triplet.lua",        read_file("triplet.lua") },
    { "asdl_context.lua",   read_file("asdl_context.lua") },
    { "lsp/semantics.lua",  read_file("lsp/semantics.lua") },
    { "lsp/parser.lua",     read_file("lsp/parser.lua") },
    { "ui/demo/app.lua",    read_file("ui/demo/app.lua") },
    { "ui/session.lua",     read_file("ui/session.lua") },
}

print(string.format("\n%s", ("═"):rep(105)))
print("  pvm-lsp full feature benchmark — every operation, real files")
print(("═"):rep(105))

print(string.format("\n  %-22s %5s │ %8s %8s %8s %8s %8s %8s %8s %8s",
    "file", "lines",
    "open", "diag$", "hover$", "def$", "refs$", "comp$", "syms$", "chg+dg"))
print("  " .. ("-"):rep(22) .. " " .. ("-"):rep(5) ..
    " │ " .. string.rep(("-"):rep(8) .. " ", 8))

for _, entry in ipairs(files) do
    local name, text = entry[1], entry[2]
    if not text then goto continue end
    local lines = count_lines(text)
    local uri = "file:///" .. name

    local core = lsp.server()
    local C = core.engine.C

    -- Cold open
    local open_us = bench(5, function()
        -- Reset everything for a true cold measurement
        core = lsp.server()
        core:handle("textDocument/didOpen", {
            textDocument = { uri = uri, version = 1, text = text },
        })
        core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    end)

    -- Now set up a warm server for cached benchmarks
    core = lsp.server()
    core:handle("textDocument/didOpen", {
        textDocument = { uri = uri, version = 1, text = text },
    })
    -- Warm all caches
    core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    core:handle("textDocument/hover", {
        textDocument = { uri = uri }, position = { line = math.floor(lines/2), character = 6 },
    })
    core:handle("textDocument/definition", {
        textDocument = { uri = uri }, position = { line = math.floor(lines/2), character = 6 },
    })
    core:handle("textDocument/references", {
        textDocument = { uri = uri }, position = { line = math.floor(lines/2), character = 6 },
        context = { includeDeclaration = true },
    })
    core:handle("textDocument/completion", {
        textDocument = { uri = uri }, position = { line = math.floor(lines/2), character = 0 },
    })
    core:handle("textDocument/documentSymbol", { textDocument = { uri = uri } })

    local N = 5000

    local diag_us = bench(N, function()
        core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    end)

    local hover_us = bench(N, function()
        core:handle("textDocument/hover", {
            textDocument = { uri = uri }, position = { line = math.floor(lines/2), character = 6 },
        })
    end)

    local def_us = bench(N, function()
        core:handle("textDocument/definition", {
            textDocument = { uri = uri }, position = { line = math.floor(lines/2), character = 6 },
        })
    end)

    local refs_us = bench(N, function()
        core:handle("textDocument/references", {
            textDocument = { uri = uri }, position = { line = math.floor(lines/2), character = 6 },
            context = { includeDeclaration = true },
        })
    end)

    local comp_us = bench(N, function()
        core:handle("textDocument/completion", {
            textDocument = { uri = uri }, position = { line = math.floor(lines/2), character = 0 },
        })
    end)

    local syms_us = bench(N, function()
        core:handle("textDocument/documentSymbol", { textDocument = { uri = uri } })
    end)

    -- Change + rediagnostic
    local chg_us = bench(20, function()
        local changed = text:gsub("local", "local", 1) -- force different text
        core:handle("textDocument/didChange", {
            textDocument = { uri = uri, version = math.random(99999) },
            contentChanges = { { text = text:sub(1, -10) .. tostring(math.random(99999)) } },
        })
        core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    end)

    print(string.format("  %-22s %5d │ %6.0f ms %6.1f µs %6.1f µs %6.1f µs %6.1f µs %6.1f µs %6.1f µs %6.0f ms",
        name, lines,
        open_us / 1000,
        diag_us, hover_us, def_us, refs_us, comp_us, syms_us,
        chg_us / 1000))

    ::continue::
end

print(string.format("\n  %-22s %5s │ %8s %8s %8s %8s %8s %8s %8s %8s",
    "", "",
    "cold", "cached", "cached", "cached", "cached", "cached", "cached", "increm"))

-- Summary
print(("\n" .. ("═"):rep(105)))
print("  open     = cold start: parse + full semantic analysis + first diagnostic")
print("  diag$    = diagnostic on unchanged file (pure pvm cache hit)")
print("  hover$   = hover on unchanged file")
print("  def$     = goto definition on unchanged file")
print("  refs$    = find references on unchanged file")
print("  comp$    = completion on unchanged file")
print("  syms$    = document symbols on unchanged file")
print("  chg+dg   = change last line + full re-diagnostic (incremental)")
print(("═"):rep(105))
