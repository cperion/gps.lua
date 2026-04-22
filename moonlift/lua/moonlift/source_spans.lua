local M = {}

local IndexMT = {}
IndexMT.__index = IndexMT

local function token_end_col(tok)
    local raw = tok and tok.raw or ""
    local n = #raw
    if n <= 1 then
        return tok.col
    end
    return tok.col + n - 1
end

function M.new(text)
    return setmetatable({
        text = text,
        by_path = {},
    }, IndexMT)
end

function M.record(index, path, first_tok, last_tok, tag)
    if index == nil or path == nil or first_tok == nil then
        return
    end
    last_tok = last_tok or first_tok
    index.by_path[path] = {
        path = path,
        tag = tag,
        line = first_tok.line,
        col = first_tok.col,
        end_line = last_tok.line,
        end_col = token_end_col(last_tok),
        offset = first_tok.offset,
        finish = last_tok.finish,
    }
end

function M.alias(index, alias_path, target_path)
    if index == nil or alias_path == nil or target_path == nil then
        return
    end
    local span = index.by_path[target_path]
    if span ~= nil then
        index.by_path[alias_path] = span
    end
end

function M.lookup(index, path)
    if index == nil then return nil end
    return index.by_path[path]
end

function IndexMT:get(path)
    return self.by_path[path]
end

function IndexMT:paths()
    local out = {}
    for k in pairs(self.by_path) do
        out[#out + 1] = k
    end
    table.sort(out)
    return out
end

return M
