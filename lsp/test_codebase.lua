#!/usr/bin/env luajit
-- Test the LSP on every .lua file in the codebase
package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local lsp = require("lsp")

local ctx = lsp.context()
local C = ctx.Lua
local parser_engine = lsp.parser(ctx)
local sem = lsp.semantics(ctx)

-- Collect all .lua files
local function collect_files(dir)
    local out = {}
    local p = io.popen('find "' .. dir .. '" -name "*.lua" -not -path "*/archive/*" 2>/dev/null')
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

local files = collect_files(".")
table.sort(files)

print(string.format("Found %d .lua files\n", #files))

local pass, fail, skip = 0, 0, 0
local errors = {}

for _, path in ipairs(files) do
    local f = io.open(path, "r")
    if not f then
        skip = skip + 1
    else
        local text = f:read("*a")
        f:close()
        
        local uri = "file://" .. path
        local source = C.OpenDoc(uri, 0, text)
        
        -- Test 1: lex
        local lex_ok, lex_err = pcall(function()
            local tokens = pvm.drain(parser_engine.lexer.lex(source))
            assert(#tokens > 0, "no tokens")
        end)
        
        -- Test 2: parse
        local parse_ok, parse_result, parse_err
        if lex_ok then
            parse_ok, parse_err = pcall(function()
                local r = pvm.one(parser_engine.parse(source))
                parse_result = r
                assert(r, "no parsed doc")
                assert(#r.items > 0, "no items")
            end)
        end
        
        -- Test 3: semantics (diagnostics)
        local sem_ok, sem_err, diag_count
        if parse_ok and parse_result then
            sem_ok, sem_err = pcall(function()
                local sdoc = sem:compile(parse_result)
                local diags = pvm.drain(sem.diagnostics(sdoc))
                diag_count = #diags
            end)
        end
        
        -- Test 4: symbol index
        local idx_ok, idx_err, sym_count
        if parse_ok and parse_result then
            idx_ok, idx_err = pcall(function()
                local idx = sem:index(sem:compile(parse_result))
                sym_count = #idx.symbols
            end)
        end
        
        local short = path:gsub("^%./", "")
        local lines = 0
        for _ in text:gmatch("\n") do lines = lines + 1 end
        lines = lines + 1
        
        if lex_ok and parse_ok and sem_ok and idx_ok then
            pass = pass + 1
            local pe = (parse_result.status and parse_result.status.kind == "ParseError") and parse_result.status.message or ""
            local pe_str = (pe and pe ~= "") and (" PARSE_ERR:" .. pe:sub(1,40)) or ""
            print(string.format("  ✓ %-50s %4d lines  %3d items  %3d syms  %3d diags%s",
                short, lines,
                #parse_result.items,
                sym_count or 0,
                diag_count or 0,
                pe_str))
        else
            fail = fail + 1
            local stage = (not lex_ok) and "LEX" or (not parse_ok) and "PARSE" or (not sem_ok) and "SEM" or "IDX"
            local err = (not lex_ok) and lex_err or (not parse_ok) and parse_err or (not sem_ok) and sem_err or idx_err
            local err_short = tostring(err):gsub("\n.*", ""):sub(1, 80)
            print(string.format("  ✗ %-50s %4d lines  %s: %s", short, lines, stage, err_short))
            errors[#errors + 1] = { path = short, stage = stage, err = tostring(err) }
        end
        
        -- Reset caches between files to avoid cross-contamination
        parser_engine.lexer.lex:reset()
        parser_engine.lexer.lex_with_positions:reset()
        parser_engine.parse:reset()
        sem:reset()
    end
end

print("\n══════════════════════════════════════════════")
print(string.format("  PASS: %d   FAIL: %d   SKIP: %d   TOTAL: %d", pass, fail, skip, #files))
print("══════════════════════════════════════════════")

if #errors > 0 then
    print("\n── Error details ──")
    for i = 1, math.min(10, #errors) do
        local e = errors[i]
        print(string.format("\n%s [%s]:", e.path, e.stage))
        -- Print first 3 lines of error
        local n = 0
        for line in e.err:gmatch("[^\n]+") do
            n = n + 1
            if n <= 3 then print("  " .. line) end
        end
    end
end
