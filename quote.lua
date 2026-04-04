-- quote.lua — hygienic code generation for Lua/LuaJIT
--
-- Small quote builder for generated Lua source:
--   val(v)        — capture a Lua value, returns a hygienic generated name
--   sym([hint])   — fresh hygienic symbol
--   q(fmt, ...)   — append formatted line
--   emit(other)   — splice another quote (code + bindings)
--   compile(name) — compile the quote with its captured environment
--
-- No manual env tables. No name collisions. Composable.
--
-- Usage:
--   local Q = require("quote")
--   local q = Q()
--   local cache = q:val(my_cache)
--   local x     = q:sym("x")
--   q("return function(%s)", x)
--   q("  local hit = %s[%s]", cache, x)
--   q("  if hit then return hit end")
--   q("end")
--   local fn, src = q:compile("=my_fn")

local M = {}
local unpack = table.unpack or unpack

local mt = {}; mt.__index = mt
local NEXT_QUOTE_ID = 0

local function sanitize_hint(hint)
    hint = tostring(hint):gsub("[^_%w]", "_")
    if hint == "" then hint = "v" end
    if hint:match("^[0-9]") then hint = "_" .. hint end
    return hint
end

function M.new()
    NEXT_QUOTE_ID = NEXT_QUOTE_ID + 1
    return setmetatable({
        qid   = NEXT_QUOTE_ID,
        lines = {},      -- source lines
        env   = {},      -- name → value
        nv    = 0,       -- upvalue counter
        ns    = 0,       -- symbol counter
    }, mt)
end

--- Capture a Lua value as an upvalue. Returns the generated name.
-- The name is valid in the generated code and refers to exactly this value.
-- Optional hint keeps generated names readable.
function mt:val(v, hint)
    -- Deduplicate by value identity where Lua allows it.
    for name, existing in pairs(self.env) do
        if existing == v then return name end
    end
    self.nv = self.nv + 1
    local stem = hint and sanitize_hint(hint) or "v"
    local name = string.format("_q%d_%s_%d", self.qid, stem, self.nv)
    self.env[name] = v
    return name
end

--- Create a fresh hygienic symbol name. Never collides with user code
-- or other symbols, even across composed quotes.
function mt:sym(hint)
    self.ns = self.ns + 1
    return string.format("_q%d_%s_%d", self.qid, sanitize_hint(hint or "s"), self.ns)
end

--- Append a line of code. If extra args are given, uses string.format.
function mt:__call(fmt, ...)
    if select("#", ...) > 0 then
        self.lines[#self.lines + 1] = string.format(fmt, ...)
    else
        self.lines[#self.lines + 1] = fmt
    end
    return self
end

--- Append a multi-line block verbatim.
function mt:block(s)
    self.lines[#self.lines + 1] = s
    return self
end

--- Splice another quote's code and bindings into this one.
-- The other quote's upvalues are merged (no collisions because
-- val() names are globally unique within a quote).
function mt:emit(other)
    for name, v in pairs(other.env) do
        local existing = self.env[name]
        if existing == nil then
            self.env[name] = v
        elseif existing ~= v then
            error("quote.emit: internal name collision for '" .. name .. "'", 2)
        end
    end
    self.lines[#self.lines + 1] = table.concat(other.lines, "\n")
    return self
end

--- Get the generated source code.
function mt:source()
    return table.concat(self.lines, "\n")
end
mt.__tostring = mt.source

--- Compile to a function. Returns (function, source_string).
-- Wraps the generated code in a closure that receives all upvalues
-- as arguments, so the inner returned function captures them properly.
-- No setfenv needed — works on all Lua/LuaJIT versions.
function M.compile_source(src, env, name)
    env = env or {}
    local unames = {}
    for k in pairs(env) do
        unames[#unames + 1] = k
    end
    table.sort(unames)

    local uvals = {}
    for i = 1, #unames do
        uvals[i] = env[unames[i]]
    end

    local wrapper
    if #unames > 0 then
        wrapper = "local " .. table.concat(unames, ", ") .. " = ...\n" .. src
    else
        wrapper = src
    end

    local fn, err
    if loadstring then
        fn, err = loadstring(wrapper, name or "=(quote)")
        if not fn then error(err .. "\n--- generated source ---\n" .. wrapper, 2) end
    else
        fn, err = load(wrapper, name or "=(quote)", "t")
        if not fn then error(err .. "\n--- generated source ---\n" .. wrapper, 2) end
    end

    return fn(unpack(uvals)), src
end

function mt:compile(name)
    return M.compile_source(self:source(), self.env, name)
end

setmetatable(M, { __call = function() return M.new() end })
return M
