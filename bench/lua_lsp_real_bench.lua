#!/usr/bin/env luajit
-- lua_lsp_real_bench.lua
--
-- Bench and sanity-check the real parser + LSP core pipeline.

package.path = "./?.lua;./?/init.lua;" .. package.path

local Server = require("bench.lua_lsp_server_core_v1")
local Parser = require("bench.lua_lsp_parser_treesitter_nvim_v1").new()

local core = Server.new({
    parse = Parser.parse,
    position_to_anchor = Parser.position_to_anchor,
    adapter_opts = { anchor_to_range = Parser.anchor_to_range },
})

local function gen_lua(n)
    local t = { "---@class User" }
    for i = 1, n do
        t[#t + 1] = string.format("local v%d = %d", i, i)
    end
    t[#t + 1] = string.format("print(v1, v%d)", n)
    t[#t + 1] = "print(v2, missing_name)"
    return table.concat(t, "\n")
end

local function bench_us(iters, fn)
    for _ = 1, math.min(5, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, iters do fn() end
    return (os.clock() - t0) * 1e6 / iters
end

local function bench_scale()
    print("== parse/change/diagnostic scaling (real parser) ==")
    for _, n in ipairs({ 100, 500, 1000, 2000 }) do
        local uri = "file:///scale_" .. tostring(n) .. ".lua"
        local txt = gen_lua(n)
        local it = (n <= 500) and 4 or 2

        local ver = 0
        local open_us = bench_us(it, function()
            ver = ver + 1
            core:did_open({ textDocument = { uri = uri, version = ver, text = txt } })
        end)

        local chver = 0
        local change_us = bench_us(it, function()
            chver = chver + 1
            local changed = txt:gsub("missing_name", "missing_name" .. tostring(chver))
            core:did_change({
                textDocument = { uri = uri, version = 100 + chver },
                contentChanges = { { text = changed } },
            })
        end)

        core:did_open({ textDocument = { uri = uri, version = 999, text = txt } })
        local diag_us = bench_us(20, function()
            core:diagnostic({ textDocument = { uri = uri } })
        end)

        print(string.format("lines=%-5d open=%8.1f us  change=%8.1f us  diagnostic=%8.1f us",
            n + 3, open_us, change_us, diag_us))
    end
end

local function bench_queries(n)
    local uri = "file:///query.lua"
    local txt = gen_lua(n)
    core:did_open({ textDocument = { uri = uri, version = 1, text = txt } })

    print("\n== query latency on large file ==")
    local hover_us = bench_us(2000, function()
        core:hover({ textDocument = { uri = uri }, position = { line = n + 1, character = 7 } })
    end)
    local def_us = bench_us(2000, function()
        core:definition({ textDocument = { uri = uri }, position = { line = n + 1, character = 7 } })
    end)
    local refs_us = bench_us(1000, function()
        core:references({ textDocument = { uri = uri }, position = { line = n + 1, character = 7 }, context = { includeDeclaration = true } })
    end)

    print(string.format("hover=%6.2f us  definition=%6.2f us  references=%6.2f us", hover_us, def_us, refs_us))

    local d = core:to_lsp(core:diagnostic({ textDocument = { uri = uri } }))
    local h = core:to_lsp(core:hover({ textDocument = { uri = uri }, position = { line = n + 1, character = 7 } }))
    local def = core:to_lsp(core:definition({ textDocument = { uri = uri }, position = { line = n + 1, character = 7 } }))

    print("\n== sanity ==")
    print("diagnostics:", #d.items)
    print("hover nil?", h == nil)
    print("definition count:", #def)
    if #d.items > 0 then
        print("first diagnostic:", d.items[1].code, d.items[1].message)
    end
end

print("lua-lsp real parser benchmark")
bench_scale()
bench_queries(2000)
