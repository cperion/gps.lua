#!/usr/bin/env luajit
-- lsp/test_server.lua
--
-- End-to-end test of the full LSP server stack:
--   OpenDoc → lex phase → parse doc → semantics → adapter → server → LSP response

package.path = "./?.lua;./?/init.lua;" .. package.path

local lsp = require("lsp")
local pvm = require("pvm")

local core = lsp.server()
local uri = "file:///demo.lua"

-- ── Test 1: didOpen + diagnostics ──────────────────────────
print("=== Test 1: didOpen + diagnostics ===")
local txt1 = table.concat({
    "---@class User",
    "---@field name string",
    "---@field id number",
    "local M = {}",
    "",
    "function M.new(name, id)",
    "    return { name = name, id = id }",
    "end",
    "",
    "local x = 42",
    "print(x, undefined_var)",
}, "\n")

core:handle("textDocument/didOpen", {
    textDocument = { uri = uri, version = 1, text = txt1 },
})

local d1 = core:to_lsp(core:handle("textDocument/diagnostic", { textDocument = { uri = uri } }))
print("diagnostics:", #d1.items)
for i = 1, #d1.items do
    print(string.format("  [%d] %s: %s (L%d:%d)",
        d1.items[i].severity, d1.items[i].code, d1.items[i].message,
        d1.items[i].range.start.line, d1.items[i].range.start.character))
end
-- Should find 'undefined_var' as undefined global
local found_undef = false
for i = 1, #d1.items do
    if d1.items[i].code == "undefined-global" and d1.items[i].message:match("undefined_var") then
        found_undef = true
    end
end
assert(found_undef, "should find undefined global 'undefined_var'")
print("OK!")

-- ── Test 2: hover ──────────────────────────────────────────
print("\n=== Test 2: hover ===")
-- Hover over 'x' at line 9 (0-indexed)
local h1 = core:to_lsp(core:handle("textDocument/hover", {
    textDocument = { uri = uri },
    position = { line = 9, character = 6 },
}))
print("hover:", h1 and h1.contents and h1.contents.value or "<nil>")
-- hover result may or may not resolve depending on anchor positions

-- ── Test 3: didChange + re-diagnostics ─────────────────────
print("\n=== Test 3: didChange ===")
local txt2 = table.concat({
    "---@class User",
    "---@field name string",
    "---@field id number",
    "local M = {}",
    "",
    "function M.new(name, id)",
    "    return { name = name, id = id }",
    "end",
    "",
    "local x = 42",
    "local y = 100",  -- added
    "print(x, y)",    -- fixed: y instead of undefined_var
}, "\n")

core:handle("textDocument/didChange", {
    textDocument = { uri = uri, version = 2 },
    contentChanges = { { text = txt2 } },
})

local d2 = core:to_lsp(core:handle("textDocument/diagnostic", { textDocument = { uri = uri } }))
print("diagnostics after fix:", #d2.items)
for i = 1, #d2.items do
    print(string.format("  [%d] %s: %s", d2.items[i].severity, d2.items[i].code, d2.items[i].message))
end
-- Should have fewer/no undefined-global diagnostics
local still_undef = false
for i = 1, #d2.items do
    if d2.items[i].code == "undefined-global" and d2.items[i].message:match("undefined_var") then
        still_undef = true
    end
end
assert(not still_undef, "undefined_var should be gone after fix")
print("OK!")

-- ── Test 4: definition ─────────────────────────────────────
print("\n=== Test 4: definition ===")
local def = core:to_lsp(core:handle("textDocument/definition", {
    textDocument = { uri = uri },
    position = { line = 11, character = 7 }, -- 'x' in print(x, y)
}))
print("definition locations:", type(def) == "table" and #def or 0)

-- ── Test 5: references ─────────────────────────────────────
print("\n=== Test 5: references ===")
local refs = core:to_lsp(core:handle("textDocument/references", {
    textDocument = { uri = uri },
    position = { line = 11, character = 7 },
    context = { includeDeclaration = true },
}))
print("references:", type(refs) == "table" and #refs or 0)

-- ── Test 6: ranged didChange ───────────────────────────────
print("\n=== Test 6: ranged didChange ===")
local uri_range = "file:///range.lua"
local txt_range = table.concat({
    "local x = 1",
    "print(x)",
}, "\n")
core:handle("textDocument/didOpen", {
    textDocument = { uri = uri_range, version = 1, text = txt_range },
})
-- Rename declaration x -> y using range patch only.
core:handle("textDocument/didChange", {
    textDocument = { uri = uri_range, version = 2 },
    contentChanges = {
        {
            range = {
                start = { line = 0, character = 6 },
                ["end"] = { line = 0, character = 7 },
            },
            text = "y",
        },
    },
})
local d_range = core:to_lsp(core:handle("textDocument/diagnostic", { textDocument = { uri = uri_range } }))
print("range diagnostics:", #d_range.items)
assert(#d_range.items >= 1, "range didChange should affect diagnostics")
print("OK!")

-- ── Test 7: workspace methods ──────────────────────────────
print("\n=== Test 7: workspace methods ===")
local ws_syms = core:to_lsp(core:handle("workspace/symbol", { query = "x" }))
print("workspace symbols:", type(ws_syms) == "table" and #ws_syms or 0)
assert(type(ws_syms) == "table", "workspace/symbol should return a list")
local ws_diag = core:to_lsp(core:handle("workspace/diagnostic", {}))
print("workspace diagnostics docs:", ws_diag and ws_diag.items and #ws_diag.items or 0)
assert(ws_diag and ws_diag.items and #ws_diag.items >= 1, "workspace/diagnostic should include docs")
print("OK!")

-- ── Test 8: cross-file module-aware definition/references ─
print("\n=== Test 8: cross-file module-aware ===")
local uri_a = "file:///mod_a.lua"
local uri_b = "file:///mod_b.lua"
core:handle("textDocument/didOpen", {
    textDocument = {
        uri = uri_a,
        version = 1,
        text = table.concat({
            "local M = {}",
            "function M.foo() end",
            "return M",
        }, "\n"),
    },
})
core:handle("textDocument/didOpen", {
    textDocument = {
        uri = uri_b,
        version = 1,
        text = table.concat({
            "local m = require(\"mod_a\")",
            "print(m.foo)",
        }, "\n"),
    },
})
local def_cf = core:to_lsp(core:handle("textDocument/definition", {
    textDocument = { uri = uri_b },
    position = { line = 1, character = 8 }, -- foo
}))
print("cross-file definition locations:", type(def_cf) == "table" and #def_cf or 0)
assert(type(def_cf) == "table" and #def_cf >= 1, "cross-file definition should find module export")
local refs_cf = core:to_lsp(core:handle("textDocument/references", {
    textDocument = { uri = uri_b },
    position = { line = 1, character = 8 },
    context = { includeDeclaration = true },
}))
print("cross-file references:", type(refs_cf) == "table" and #refs_cf or 0)
assert(type(refs_cf) == "table" and #refs_cf >= 1, "cross-file references should include module field hits")
print("OK!")

-- ── Test 9: code actions / semantic tokens / inlay / format / sighelp ─
print("\n=== Test 9: extra editor features ===")
local uri_feat = "file:///features2.lua"
local txt_feat = table.concat({
    "local function add(a, b)",
    "    return a + b",
    "end",
    "local x = 42   ",
    "print(add(1, x, missing_name))",
}, "\n")
core:handle("textDocument/didOpen", {
    textDocument = { uri = uri_feat, version = 1, text = txt_feat },
})

local sig = core:to_lsp(core:handle("textDocument/signatureHelp", {
    textDocument = { uri = uri_feat },
    position = { line = 4, character = 12 },
}))
print("signatureHelp signatures:", sig and sig.signatures and #sig.signatures or 0)
assert(sig and sig.signatures and #sig.signatures >= 1, "signatureHelp should return at least one signature")
assert(sig.signatures[1].label and sig.signatures[1].label:match("add%(") , "signatureHelp label should include callee name")

local st = core:to_lsp(core:handle("textDocument/semanticTokens/full", {
    textDocument = { uri = uri_feat },
}))
print("semantic tokens ints:", st and st.data and #st.data or 0)
assert(st and st.data and #st.data > 0, "semantic tokens should not be empty")

local hints = core:to_lsp(core:handle("textDocument/inlayHint", {
    textDocument = { uri = uri_feat },
    range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 10, character = 0 },
    },
}))
print("inlay hints:", type(hints) == "table" and #hints or 0)
assert(type(hints) == "table" and #hints >= 1, "inlay hints should include inferred types")

local actions = core:to_lsp(core:handle("textDocument/codeAction", {
    textDocument = { uri = uri_feat },
    range = {
        start = { line = 4, character = 16 },
        ["end"] = { line = 4, character = 28 },
    },
    context = { diagnostics = {} },
}))
print("code actions:", type(actions) == "table" and #actions or 0)
local has_local_fix, has_import_fix = false, false
if type(actions) == "table" then
    for i = 1, #actions do
        if actions[i].title and actions[i].title:match("Create local") then has_local_fix = true end
        if actions[i].title and actions[i].title:match("Import module") then has_import_fix = true end
    end
end
assert(has_local_fix, "code actions should include local quickfix")
assert(has_import_fix, "code actions should include import quickfix")

local fmt = core:to_lsp(core:handle("textDocument/formatting", {
    textDocument = { uri = uri_feat },
    options = { tabSize = 4, insertSpaces = true },
}))
print("format edits:", type(fmt) == "table" and #fmt or 0)
assert(type(fmt) == "table" and #fmt >= 1, "formatting should return at least one edit")

local rfmt = core:to_lsp(core:handle("textDocument/rangeFormatting", {
    textDocument = { uri = uri_feat },
    options = { tabSize = 4, insertSpaces = true },
    range = {
        start = { line = 3, character = 0 },
        ["end"] = { line = 4, character = 0 },
    },
}))
print("range format edits:", type(rfmt) == "table" and #rfmt or 0)
assert(type(rfmt) == "table" and #rfmt >= 1, "range formatting should return at least one edit")
print("OK!")

-- ── Test 10: parity gap methods ────────────────────────────
print("\n=== Test 10: parity gap methods ===")

local uri_types = "file:///types.lua"
local txt_types = table.concat({
    "---@class Parent",
    "---@field id number",
    "local Parent = {}",
    "---@class Child: Parent",
    "---@field name string",
    "local Child = {}",
    "---@return Child",
    "function Child:get_child()",
    "    return self",
    "end",
    "---@return Parent",
    "function Child:get_parent()",
    "    return self",
    "end",
    "---@alias Kid Child",
    "---@type Kid",
    "local kid = Child",
    "local x = kid:get_child()",
    "print(x:get_parent())",
}, "\n")
core:handle("textDocument/didOpen", {
    textDocument = { uri = uri_types, version = 1, text = txt_types },
})

local decl = core:to_lsp(core:handle("textDocument/declaration", {
    textDocument = { uri = uri_types },
    position = { line = 17, character = 10 },
}))
print("declaration locations:", type(decl) == "table" and #decl or 0)
assert(type(decl) == "table" and #decl >= 1, "declaration should resolve kid declaration")

local impl = core:to_lsp(core:handle("textDocument/implementation", {
    textDocument = { uri = uri_types },
    position = { line = 3, character = 17 }, -- Parent in Child: Parent
}))
print("implementation locations:", type(impl) == "table" and #impl or 0)
assert(type(impl) == "table" and #impl >= 1, "implementation should find Child for Parent")

local tdef = core:to_lsp(core:handle("textDocument/typeDefinition", {
    textDocument = { uri = uri_types },
    position = { line = 17, character = 10 }, -- kid usage
}))
print("typeDefinition locations:", type(tdef) == "table" and #tdef or 0)
assert(type(tdef) == "table" and #tdef >= 1, "typeDefinition should resolve Kid/Child type")

local tdef_method = core:to_lsp(core:handle("textDocument/typeDefinition", {
    textDocument = { uri = uri_types },
    position = { line = 18, character = 12 }, -- get_parent in x:get_parent()
}))
print("typeDefinition (method) locations:", type(tdef_method) == "table" and #tdef_method or 0)
assert(type(tdef_method) == "table" and #tdef_method >= 1, "typeDefinition should resolve method return type")

local st_range = core:to_lsp(core:handle("textDocument/semanticTokens/range", {
    textDocument = { uri = uri_feat },
    range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 2, character = 0 },
    },
}))
print("semantic tokens range ints:", st_range and st_range.data and #st_range.data or 0)
assert(st_range and st_range.data, "semanticTokens/range should return data")

local folds = core:to_lsp(core:handle("textDocument/foldingRange", {
    textDocument = { uri = uri_feat },
}))
print("folding ranges:", type(folds) == "table" and #folds or 0)
assert(type(folds) == "table", "foldingRange should return list")

local sels = core:to_lsp(core:handle("textDocument/selectionRange", {
    textDocument = { uri = uri_feat },
    positions = { { line = 4, character = 11 } },
}))
print("selection ranges:", type(sels) == "table" and #sels or 0)
assert(type(sels) == "table" and #sels >= 1, "selectionRange should return entries")

local lenses = core:to_lsp(core:handle("textDocument/codeLens", {
    textDocument = { uri = uri_feat },
}))
print("code lenses:", type(lenses) == "table" and #lenses or 0)
assert(type(lenses) == "table", "codeLens should return list")

local uri_color = "file:///colors.lua"
core:handle("textDocument/didOpen", {
    textDocument = { uri = uri_color, version = 1, text = "local c = 0xff00aaff\n" },
})
local cols = core:to_lsp(core:handle("textDocument/documentColor", {
    textDocument = { uri = uri_color },
}))
print("document colors:", type(cols) == "table" and #cols or 0)
assert(type(cols) == "table" and #cols >= 1, "documentColor should detect at least one color")

local comp_items = core:to_lsp(core:handle("textDocument/completion", {
    textDocument = { uri = uri_feat },
    position = { line = 4, character = 6 },
}))
local first_item = (comp_items and comp_items.items and comp_items.items[1]) or { label = "x", kind = 6 }
local comp_resolved = core:to_lsp(core:handle("completionItem/resolve", first_item))
print("completion resolve label:", comp_resolved and comp_resolved.label or "")
assert(comp_resolved and comp_resolved.label, "completionItem/resolve should echo item")

local first_action = (type(actions) == "table" and actions[1]) or {
    title = "dummy",
    kind = "quickfix",
    edit = { changes = { [uri_feat] = {} } },
}
local action_resolved = core:to_lsp(core:handle("codeAction/resolve", first_action))
print("codeAction resolve title:", action_resolved and action_resolved.title or "")
assert(action_resolved and action_resolved.title, "codeAction/resolve should echo action")

local action_doc_changes = core:to_lsp(core:handle("codeAction/resolve", {
    title = "docChanges",
    kind = "quickfix",
    edit = {
        documentChanges = {
            {
                textDocument = { uri = uri_feat, version = 2 },
                edits = {
                    {
                        range = {
                            start = { line = 0, character = 0 },
                            ["end"] = { line = 0, character = 0 },
                        },
                        newText = "-- note\n",
                    }
                },
            }
        }
    }
}))
assert(action_doc_changes and action_doc_changes.edit
    and action_doc_changes.edit.changes
    and action_doc_changes.edit.changes[uri_feat]
    and #action_doc_changes.edit.changes[uri_feat] == 1,
    "codeAction/resolve should accept documentChanges fallback")

core:handle("textDocument/didSave", {
    textDocument = { uri = uri_feat },
})
local exec_res = core:to_lsp(core:handle("workspace/executeCommand", {
    command = "lua.solve",
    arguments = {},
}))
print("executeCommand result:", exec_res)
assert(exec_res == "ok" or exec_res == "unsupported", "executeCommand should return status")
print("OK!")

-- ── Test 11: didClose ──────────────────────────────────────
print("\n=== Test 11: didClose ===")
core:handle("textDocument/didClose", {
    textDocument = { uri = uri },
})
core:handle("textDocument/didClose", {
    textDocument = { uri = uri_range },
})
core:handle("textDocument/didClose", {
    textDocument = { uri = uri_a },
})
core:handle("textDocument/didClose", {
    textDocument = { uri = uri_b },
})
core:handle("textDocument/didClose", {
    textDocument = { uri = uri_feat },
})
core:handle("textDocument/didClose", {
    textDocument = { uri = uri_types },
})
core:handle("textDocument/didClose", {
    textDocument = { uri = uri_color },
})
print("OK!")

-- ── Test 12: benchmark ─────────────────────────────────────
print("\n=== Test 12: benchmark ===")
local function bench(name, n, fn)
    for _ = 1, 5 do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, n do fn() end
    local us = (os.clock() - t0) * 1e6 / n
    print(string.format("  %-35s %8.1f us", name, us))
end

-- Generate larger file
local big = { "---@class BigClass" }
for i = 1, 500 do big[#big + 1] = string.format("local v%d = %d", i, i) end
big[#big + 1] = "print(v1, v500)"
big[#big + 1] = "print(v2, missing_name)"
local big_txt = table.concat(big, "\n")
local big_uri = "file:///big.lua"

core:handle("textDocument/didOpen", {
    textDocument = { uri = big_uri, version = 1, text = big_txt },
})

bench("diagnostic (500 locals, first)", 10, function()
    core:handle("textDocument/diagnostic", { textDocument = { uri = big_uri } })
end)

bench("diagnostic (500 locals, cached)", 1000, function()
    core:handle("textDocument/diagnostic", { textDocument = { uri = big_uri } })
end)

-- Change one line and re-diagnostic
local function change_and_diag(ver)
    local changed = big_txt:gsub("missing_name", "missing_" .. tostring(ver))
    core:handle("textDocument/didChange", {
        textDocument = { uri = big_uri, version = 100 + ver },
        contentChanges = { { text = changed } },
    })
    return core:handle("textDocument/diagnostic", { textDocument = { uri = big_uri } })
end

bench("change+diagnostic (500 locals)", 10, function()
    change_and_diag(math.random(10000))
end)

print("\nAll server tests passed!")
