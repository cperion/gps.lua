-- bench/lua_lsp_nvim_dump.lua
--
-- Run inside Neovim headless:
--   nvim --headless -u NONE -n -l bench/lua_lsp_nvim_dump.lua <path.lua>
--
-- Prints one JSON object to stdout with a CST dump.

local src_path = (type(arg) == "table" and arg[1]) or vim.fn.argv()[1]
if not src_path or src_path == "" then
    io.stdout:write(vim.json.encode({ ok = false, error = "missing source path" }))
    vim.cmd("qa!")
    return
end

local lines = vim.fn.readfile(src_path)
local source = table.concat(lines, "\n")

local ok, parser = pcall(vim.treesitter.get_string_parser, source, "lua")
if not ok then
    io.stdout:write(vim.json.encode({ ok = false, error = tostring(parser) }))
    vim.cmd("qa!")
    return
end

local tree = parser:parse()[1]
if not tree then
    io.stdout:write(vim.json.encode({ ok = false, error = "no parse tree" }))
    vim.cmd("qa!")
    return
end

local function dump(node)
    local sr, sc, er, ec = node:range()
    local out = {
        type = node:type(),
        named = node:named(),
        range = { sr, sc, er, ec },
        children = {},
    }

    local i = 0
    for child, field in node:iter_children() do
        i = i + 1
        local c = dump(child)
        c.field = field
        out.children[i] = c
    end

    return out
end

local root = tree:root()
io.stdout:write(vim.json.encode({ ok = true, tree = dump(root) }))
vim.cmd("qa!")
