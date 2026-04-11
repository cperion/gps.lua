-- iter2.lua — ASDL/PVM-backed iterator pipelines
--
-- A smaller, typed/interned sibling of iterkit.lua.
--
-- Public shape:
--   local it = require("iter2")
--   local p = it.range(1, 1000)
--                :filter(function(x) return x % 2 == 1 end, "odd")
--                :map(function(x) return x * x end, "square")
--                :take(10)
--   local out = p:collect()        -- compiled on first use, then cached
--   local fast = p:compile()       -- optional explicit compiled handle
--   print(fast:collect())
--   print(p:source("collect"))
--
-- Internally:
--   * pipeline nodes are ASDL constructors (typed + interned)
--   * passes are pvm.verb dispatches on metatable identity
--   * reducers are pvm.lower memo boundaries

local pvm = require("pvm")
local Quote = require("quote")

local it = {}

local ctx = pvm.context():Define [[
module Iter2 {
    Pipe = Range(number lo, number hi, number step) unique
         | Array(table data) unique
         | Chars(string str) unique
         | Once(any val) unique
         | Rep(any val, number n) unique
         | Empty
         | Map(function fn, string? fn_name, Iter2.Pipe src) unique
         | Filter(function fn, string? fn_name, Iter2.Pipe src) unique
         | Take(number n, Iter2.Pipe src) unique
         | Skip(number n, Iter2.Pipe src) unique
         | TakeWhile(function fn, string? fn_name, Iter2.Pipe src) unique
         | SkipWhile(function fn, string? fn_name, Iter2.Pipe src) unique
         | Chain(Iter2.Pipe left, Iter2.Pipe right) unique
         | Enumerate(number start, Iter2.Pipe src) unique
         | Scan(function fn, any init, string? fn_name, Iter2.Pipe src) unique
         | Dedup(Iter2.Pipe src) unique
         | Tap(function fn, string? fn_name, Iter2.Pipe src) unique
}
]]

local I = ctx.Iter2
local Pipe = I.Pipe
local Range, Array, Chars, Once, Rep, Empty = I.Range, I.Array, I.Chars, I.Once, I.Rep, I.Empty
local Map, Filter, Take, Skip = I.Map, I.Filter, I.Take, I.Skip
local TakeWhile, SkipWhile, Chain = I.TakeWhile, I.SkipWhile, I.Chain
local Enumerate, Scan, Dedup, Tap = I.Enumerate, I.Scan, I.Dedup, I.Tap

-- ═══════════════════════════════════════════════════════════
--  DSL
-- ═══════════════════════════════════════════════════════════

function it.range(a, b, s)
    if b == nil then a, b = 1, a end
    return Range(a, b, s or 1)
end

function it.from(t) return Array(t) end
function it.chars(s) return Chars(s) end
function it.once(v) return Once(v) end
function it.rep(v, n) return Rep(v, n) end
function it.empty() return Empty end

function Pipe:map(fn, name) return Map(fn, name, self) end
function Pipe:filter(fn, name) return Filter(fn, name, self) end
function Pipe:take(n) return Take(n, self) end
function Pipe:skip(n) return Skip(n, self) end
function Pipe:take_while(fn, name) return TakeWhile(fn, name, self) end
function Pipe:skip_while(fn, name) return SkipWhile(fn, name, self) end
function Pipe:chain(other) return Chain(self, other) end
function Pipe:enumerate(start) return Enumerate(start or 1, self) end
function Pipe:scan(fn, init, name) return Scan(fn, init, name, self) end
function Pipe:dedup() return Dedup(self) end
function Pipe:tap(fn, name) return Tap(fn, name, self) end

-- ═══════════════════════════════════════════════════════════
--  ANALYSES / REWRITES
-- ═══════════════════════════════════════════════════════════

local function fn_label(node)
    return node.fn_name or "fn"
end

local depth = pvm.verb("depth", {
    [Range] = function() return 1 end,
    [Array] = function() return 1 end,
    [Chars] = function() return 1 end,
    [Once]  = function() return 1 end,
    [Rep]   = function() return 1 end,
    [Empty] = function() return 1 end,
    [Map] = function(n) return 1 + n.src:depth() end,
    [Filter] = function(n) return 1 + n.src:depth() end,
    [Take] = function(n) return 1 + n.src:depth() end,
    [Skip] = function(n) return 1 + n.src:depth() end,
    [TakeWhile] = function(n) return 1 + n.src:depth() end,
    [SkipWhile] = function(n) return 1 + n.src:depth() end,
    [Enumerate] = function(n) return 1 + n.src:depth() end,
    [Scan] = function(n) return 1 + n.src:depth() end,
    [Dedup] = function(n) return 1 + n.src:depth() end,
    [Tap] = function(n) return 1 + n.src:depth() end,
    [Chain] = function(n)
        local dl, dr = n.left:depth(), n.right:depth()
        return 1 + (dl > dr and dl or dr)
    end,
}, { cache = true })

local node_count = pvm.verb("node_count", {
    [Range] = function() return 1 end,
    [Array] = function() return 1 end,
    [Chars] = function() return 1 end,
    [Once]  = function() return 1 end,
    [Rep]   = function() return 1 end,
    [Empty] = function() return 1 end,
    [Map] = function(n) return 1 + n.src:node_count() end,
    [Filter] = function(n) return 1 + n.src:node_count() end,
    [Take] = function(n) return 1 + n.src:node_count() end,
    [Skip] = function(n) return 1 + n.src:node_count() end,
    [TakeWhile] = function(n) return 1 + n.src:node_count() end,
    [SkipWhile] = function(n) return 1 + n.src:node_count() end,
    [Enumerate] = function(n) return 1 + n.src:node_count() end,
    [Scan] = function(n) return 1 + n.src:node_count() end,
    [Dedup] = function(n) return 1 + n.src:node_count() end,
    [Tap] = function(n) return 1 + n.src:node_count() end,
    [Chain] = function(n) return 1 + n.left:node_count() + n.right:node_count() end,
}, { cache = true })

local describe = pvm.verb("describe", {
    [Range] = function(n)
        return n.step == 1
            and string.format("range(%s, %s)", tostring(n.lo), tostring(n.hi))
            or string.format("range(%s, %s, %s)", tostring(n.lo), tostring(n.hi), tostring(n.step))
    end,
    [Array] = function(n) return string.format("array[%d]", #n.data) end,
    [Chars] = function(n) return string.format("chars(%q)", n.str) end,
    [Once]  = function(n) return "once(" .. tostring(n.val) .. ")" end,
    [Rep]   = function(n) return string.format("rep(%s, %s)", tostring(n.val), tostring(n.n)) end,
    [Empty] = function() return "empty()" end,
    [Map] = function(n) return n.src:describe() .. " -> map(" .. fn_label(n) .. ")" end,
    [Filter] = function(n) return n.src:describe() .. " -> filter(" .. fn_label(n) .. ")" end,
    [Take] = function(n) return n.src:describe() .. " -> take(" .. tostring(n.n) .. ")" end,
    [Skip] = function(n) return n.src:describe() .. " -> skip(" .. tostring(n.n) .. ")" end,
    [TakeWhile] = function(n) return n.src:describe() .. " -> take_while(" .. fn_label(n) .. ")" end,
    [SkipWhile] = function(n) return n.src:describe() .. " -> skip_while(" .. fn_label(n) .. ")" end,
    [Enumerate] = function(n) return n.src:describe() .. " -> enumerate(" .. tostring(n.start) .. ")" end,
    [Scan] = function(n) return n.src:describe() .. " -> scan(" .. fn_label(n) .. ", " .. tostring(n.init) .. ")" end,
    [Dedup] = function(n) return n.src:describe() .. " -> dedup()" end,
    [Tap] = function(n) return n.src:describe() .. " -> tap(" .. fn_label(n) .. ")" end,
    [Chain] = function(n) return "chain(" .. n.left:describe() .. ", " .. n.right:describe() .. ")" end,
}, { cache = true })

local normalize = pvm.verb("normalize", {
    [Range] = function(n) return n end,
    [Array] = function(n) return n end,
    [Chars] = function(n) return n end,
    [Once]  = function(n) return n end,
    [Rep]   = function(n) return (n.n <= 0) and Empty or n end,
    [Empty] = function(n) return n end,
    [Map] = function(n)
        local src = n.src:normalize()
        if src == Empty then return Empty end
        return (src == n.src) and n or Map(n.fn, n.fn_name, src)
    end,
    [Filter] = function(n)
        local src = n.src:normalize()
        if src == Empty then return Empty end
        return (src == n.src) and n or Filter(n.fn, n.fn_name, src)
    end,
    [Take] = function(n)
        if n.n <= 0 then return Empty end
        local src = n.src:normalize()
        if src == Empty then return Empty end
        return (src == n.src) and n or Take(n.n, src)
    end,
    [Skip] = function(n)
        local src = n.src:normalize()
        if n.n <= 0 then return src end
        if src == Empty then return Empty end
        return (src == n.src) and n or Skip(n.n, src)
    end,
    [TakeWhile] = function(n)
        local src = n.src:normalize()
        if src == Empty then return Empty end
        return (src == n.src) and n or TakeWhile(n.fn, n.fn_name, src)
    end,
    [SkipWhile] = function(n)
        local src = n.src:normalize()
        if src == Empty then return Empty end
        return (src == n.src) and n or SkipWhile(n.fn, n.fn_name, src)
    end,
    [Enumerate] = function(n)
        local src = n.src:normalize()
        if src == Empty then return Empty end
        return (src == n.src) and n or Enumerate(n.start, src)
    end,
    [Scan] = function(n)
        local src = n.src:normalize()
        if src == Empty then return Empty end
        return (src == n.src) and n or Scan(n.fn, n.init, n.fn_name, src)
    end,
    [Dedup] = function(n)
        local src = n.src:normalize()
        if src == Empty then return Empty end
        return (src == n.src) and n or Dedup(src)
    end,
    [Tap] = function(n)
        local src = n.src:normalize()
        if src == Empty then return Empty end
        return (src == n.src) and n or Tap(n.fn, n.fn_name, src)
    end,
    [Chain] = function(n)
        local l, r = n.left:normalize(), n.right:normalize()
        if l == Empty then return r end
        if r == Empty then return l end
        if l == n.left and r == n.right then return n end
        return Chain(l, r)
    end,
}, { cache = true })

Pipe.__tostring = function(self) return self:describe() end

-- ═══════════════════════════════════════════════════════════
--  CODEGEN
-- ═══════════════════════════════════════════════════════════

-- Symbolic val — deferred expression for the current element.
-- Map wraps val in App() instead of emitting a local;
-- the expression is only rendered when a stage actually needs it.
local VAL_VAR, VAL_APP = {}, {}
local function Var(name) return { tag = VAL_VAR, name = name } end
local function App(fn_name, inner) return { tag = VAL_APP, fn_name = fn_name, x = inner } end

local function render_val(v)
    if v.tag == VAL_VAR then return v.name end
    if v.tag == VAL_APP then return string.format("%s(%s)", v.fn_name, render_val(v.x)) end
    error("render_val: unknown val tag")
end

local function materialize(q, fresh, v)
    if v.tag == VAL_VAR then return v.name, v end
    local expr = render_val(v)
    local name = fresh("v")
    q("local %s = %s", name, expr)
    return name, Var(name)
end

local emit = pvm.verb("emit", {
    [Range] = function(n, q, fresh, body_fn)
        local i = fresh("i")
        local lo = q:val(n.lo, "lo")
        local hi = q:val(n.hi, "hi")
        local st = q:val(n.step, "step")
        q("for %s = %s, %s, %s do", i, lo, hi, st)
        body_fn(q, Var(i))
        q("end")
    end,
    [Array] = function(n, q, fresh, body_fn)
        local data = q:val(n.data, "data")
        local i = fresh("i")
        local v = fresh("v")
        q("for %s = 1, #%s do", i, data)
        q("local %s = %s[%s]", v, data, i)
        body_fn(q, Var(v))
        q("end")
    end,
    [Chars] = function(n, q, fresh, body_fn)
        local str = q:val(n.str, "str")
        local sub = q:val(string.sub, "sub")
        local i = fresh("i")
        local ch = fresh("ch")
        q("for %s = 1, #%s do", i, str)
        q("local %s = %s(%s, %s, %s)", ch, sub, str, i, i)
        body_fn(q, Var(ch))
        q("end")
    end,
    [Once] = function(n, q, _fresh, body_fn)
        local val = q:val(n.val, "once_val")
        q("do")
        body_fn(q, Var(val))
        q("end")
    end,
    [Rep] = function(n, q, fresh, body_fn)
        local val = q:val(n.val, "rep_val")
        local cnt = q:val(n.n, "rep_n")
        local i = fresh("i")
        q("for %s = 1, %s do", i, cnt)
        body_fn(q, Var(val))
        q("end")
    end,
    [Empty] = function() end,
    [Map] = function(n, q, fresh, body_fn)
        local fn = q:val(n.fn, "mapf")
        n.src:emit(q, fresh, function(q2, val)
            body_fn(q2, App(fn, val))
        end)
    end,
    [Filter] = function(n, q, fresh, body_fn)
        local fn = q:val(n.fn, "filt")
        n.src:emit(q, fresh, function(q2, val)
            local name, var = materialize(q2, fresh, val)
            q2("if %s(%s) then", fn, name)
            body_fn(q2, var)
            q2("end")
        end)
    end,
    [Take] = function(n, q, fresh, body_fn)
        local c = fresh("taken")
        local lim = q:val(n.n, "take_n")
        q("local %s = 0", c)
        n.src:emit(q, fresh, function(q2, val)
            q2("%s = %s + 1", c, c)
            body_fn(q2, val)
            q2("if %s >= %s then goto _done end", c, lim)
        end)
    end,
    [Skip] = function(n, q, fresh, body_fn)
        local c = fresh("skipped")
        local lim = q:val(n.n, "skip_n")
        q("local %s = 0", c)
        n.src:emit(q, fresh, function(q2, val)
            q2("%s = %s + 1", c, c)
            q2("if %s > %s then", c, lim)
            body_fn(q2, val)
            q2("end")
        end)
    end,
    [TakeWhile] = function(n, q, fresh, body_fn)
        local fn = q:val(n.fn, "tw_fn")
        n.src:emit(q, fresh, function(q2, val)
            local name, var = materialize(q2, fresh, val)
            q2("if not %s(%s) then goto _done end", fn, name)
            body_fn(q2, var)
        end)
    end,
    [SkipWhile] = function(n, q, fresh, body_fn)
        local fn = q:val(n.fn, "sw_fn")
        local flag = fresh("sw_active")
        q("local %s = true", flag)
        n.src:emit(q, fresh, function(q2, val)
            local name, var = materialize(q2, fresh, val)
            q2("if %s then", flag)
            q2("  if not %s(%s) then %s = false end", fn, name, flag)
            q2("end")
            q2("if not %s then", flag)
            body_fn(q2, var)
            q2("end")
        end)
    end,
    [Chain] = function(n, q, fresh, body_fn)
        n.left:emit(q, fresh, body_fn)
        n.right:emit(q, fresh, body_fn)
    end,
    [Enumerate] = function(n, q, fresh, body_fn)
        local idx = fresh("idx")
        local start = q:val(n.start - 1, "enum_start")
        q("local %s = %s", idx, start)
        n.src:emit(q, fresh, function(q2, val)
            local pair = fresh("pair")
            q2("%s = %s + 1", idx, idx)
            q2("local %s = { %s, %s }", pair, idx, render_val(val))
            body_fn(q2, Var(pair))
        end)
    end,
    [Scan] = function(n, q, fresh, body_fn)
        local fn = q:val(n.fn, "scanf")
        local acc = fresh("acc")
        local init = q:val(n.init, "scan_init")
        q("local %s = %s", acc, init)
        n.src:emit(q, fresh, function(q2, val)
            q2("%s = %s(%s, %s)", acc, fn, acc, render_val(val))
            body_fn(q2, Var(acc))
        end)
    end,
    [Dedup] = function(n, q, fresh, body_fn)
        local sentinel = q:val({}, "dedup_sentinel")
        local prev = fresh("prev")
        q("local %s = %s", prev, sentinel)
        n.src:emit(q, fresh, function(q2, val)
            local name, var = materialize(q2, fresh, val)
            q2("if %s ~= %s then", name, prev)
            q2("  %s = %s", prev, name)
            body_fn(q2, var)
            q2("end")
        end)
    end,
    [Tap] = function(n, q, fresh, body_fn)
        local fn = q:val(n.fn, "tapf")
        n.src:emit(q, fresh, function(q2, val)
            local name, var = materialize(q2, fresh, val)
            q2("%s(%s)", fn, name)
            body_fn(q2, var)
        end)
    end,
})

local function make_lower(name, build_fn)
    return pvm.lower("iter2." .. name, function(node)
        local q = Quote()
        local slot = 0
        local function fresh(hint)
            slot = slot + 1
            return q:sym((hint or "s") .. "_" .. slot)
        end
        node = node:normalize()
        build_fn(q, fresh, node)
        local fn, src = q:compile("=(iter2." .. name .. ")")
        return { fn = fn, source = src, node = node }
    end, { input = "table" })
end

local build_collect = make_lower("collect", function(q, fresh, node)
    q("return function()")
    q("local _out, _n = {}, 0")
    node:emit(q, fresh, function(q2, val)
        q2("_n = _n + 1")
        q2("_out[_n] = %s", render_val(val))
    end)
    q("::_done::")
    q("return _out")
    q("end")
end)

local build_fold = make_lower("fold", function(q, fresh, node)
    q("return function(_fold_fn, _init)")
    q("local _acc = _init")
    node:emit(q, fresh, function(q2, val)
        q2("_acc = _fold_fn(_acc, %s)", render_val(val))
    end)
    q("::_done::")
    q("return _acc")
    q("end")
end)

local build_each = make_lower("each", function(q, fresh, node)
    q("return function(_each_fn)")
    node:emit(q, fresh, function(q2, val)
        q2("_each_fn(%s)", render_val(val))
    end)
    q("::_done::")
    q("end")
end)

local build_sum = make_lower("sum", function(q, fresh, node)
    q("return function()")
    q("local _acc = 0")
    node:emit(q, fresh, function(q2, val)
        q2("_acc = _acc + %s", render_val(val))
    end)
    q("::_done::")
    q("return _acc")
    q("end")
end)

local build_count = make_lower("count", function(q, fresh, node)
    q("return function()")
    q("local _n = 0")
    node:emit(q, fresh, function(q2)
        q2("_n = _n + 1")
    end)
    q("::_done::")
    q("return _n")
    q("end")
end)

local build_first = make_lower("first", function(q, fresh, node)
    q("return function()")
    q("local _first = nil")
    node:emit(q, fresh, function(q2, val)
        q2("_first = %s", render_val(val))
        q2("goto _done")
    end)
    q("::_done::")
    q("return _first")
    q("end")
end)

local lowerings = {
    collect = build_collect,
    fold = build_fold,
    each = build_each,
    sum = build_sum,
    count = build_count,
    first = build_first,
}

local C = {}
C.__index = C

function C:collect() return build_collect(self.node).fn() end
function C:fold(fn, init) return build_fold(self.node).fn(fn, init) end
function C:each(fn) return build_each(self.node).fn(fn) end
function C:sum() return build_sum(self.node).fn() end
function C:count() return build_count(self.node).fn() end
function C:first() return build_first(self.node).fn() end
function C:join(sep) return table.concat(self:collect(), sep or ", ") end

function C:source(name)
    name = name or "collect"
    local lower = lowerings[name]
    if not lower then error("iter2: unknown compiled reducer '" .. tostring(name) .. "'", 2) end
    return lower(self.node).source
end

function C:describe() return self.node:describe() end
C.__tostring = C.describe

function Pipe:collect() return build_collect(self:normalize()).fn() end
function Pipe:fold(fn, init) return build_fold(self:normalize()).fn(fn, init) end
function Pipe:each(fn) return build_each(self:normalize()).fn(fn) end
function Pipe:sum() return build_sum(self:normalize()).fn() end
function Pipe:count() return build_count(self:normalize()).fn() end
function Pipe:first() return build_first(self:normalize()).fn() end
function Pipe:join(sep) return table.concat(self:collect(), sep or ", ") end
function Pipe:source(name)
    name = name or "collect"
    local lower = lowerings[name]
    if not lower then error("iter2: unknown compiled reducer '" .. tostring(name) .. "'", 2) end
    return lower(self:normalize()).source
end
function Pipe:trace(name)
    name = name or "collect"
    local lower = lowerings[name]
    if not lower then error("iter2: unknown compiled reducer '" .. tostring(name) .. "'", 2) end
    local node = self:normalize()
    local before = lower:stats()
    local calls0, hits0 = before.calls, before.hits
    local entry = lower(node)
    local after = lower:stats()
    local hit = after.hits > hits0
    local lines = {
        string.format("iter2 trace [%s]", name),
        string.rep("=", 40),
        "normalized:",
        "  " .. node:describe(),
        string.format("lowering cache: calls %d -> %d, hits %d -> %d (%s)", calls0, after.calls, hits0, after.hits, hit and "hit" or "miss"),
        "",
        "lowering wrapper:",
        lower.source,
        "",
        "reducer source:",
        entry.source,
    }
    return table.concat(lines, "\n")
end
function Pipe:compile()
    return setmetatable({ node = self:normalize() }, C)
end

-- ═══════════════════════════════════════════════════════════
--  EXTRAS
-- ═══════════════════════════════════════════════════════════

it.types = function() return ctx end
it.Pipe = I
it.normalize = normalize
it.depth = depth
it.node_count = node_count
it.describe = describe
it.emit = emit
it.lowerings = lowerings
it.trace = function(node, name) return node:trace(name) end

return it
