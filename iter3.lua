-- iter3.lua — typed AST, typed runtime state, pure gen/param/state iterators
--
-- No reducer codegen.
-- No implicit optimization.
--
-- The authored structure is immutable, interned ASDL.
-- The live iterator state is ALSO typed with ASDL, but NOT unique, so it can
-- be mutated in place by the generator. That is the core idea here.
--
-- Usage:
--   local iter = require("iter3")
--
--   local p = iter.range(1, 1000)
--       :filter(function(x) return x % 2 == 1 end, "odd")
--       :map(function(x) return x * x end, "square")
--       :take(10)
--
--   local gen, param, state = p:triplet()   -- raw, no optimize/codegen
--   local out = p:collect()
--   local fastish = p:plan()                -- explicit lowered plan reuse
--   local better = p:optimize():plan()      -- explicit rewrite + lowered plan
--
-- Notes:
--   * Pipe nodes are immutable/interned ASDL (unique)
--   * State nodes are mutable ASDL (non-unique)
--   * Stateful combinators mutate their typed state in place and return it
--   * Stateless combinators reuse the child state directly

local pvm = require("pvm")

local iter = {}

local ctx = pvm.context():Define([[
module Iter3 {
    Pipe = Range(number lo, number hi, number step) unique
         | Array(table data) unique
         | Chars(string str) unique
         | Once(any val) unique
         | Rep(any val, number n) unique
         | Empty
         | Map(function fn, string? fn_name, Iter3.Pipe src) unique
         | Filter(function fn, string? fn_name, Iter3.Pipe src) unique
         | Take(number n, Iter3.Pipe src) unique
         | Skip(number n, Iter3.Pipe src) unique
         | TakeWhile(function fn, string? fn_name, Iter3.Pipe src) unique
         | SkipWhile(function fn, string? fn_name, Iter3.Pipe src) unique
         | Chain(Iter3.Pipe left, Iter3.Pipe right) unique
         | Zip(Iter3.Pipe left, Iter3.Pipe right) unique
         | Enumerate(number start, Iter3.Pipe src) unique
         | Scan(function fn, any init, string? fn_name, Iter3.Pipe src) unique
         | FlatMap(function fn, string? fn_name, Iter3.Pipe src) unique
         | Dedup(Iter3.Pipe src) unique
         | Tap(function fn, string? fn_name, Iter3.Pipe src) unique
         | Window(number n, Iter3.Pipe src) unique
         | GroupBy(function fn, string? fn_name, Iter3.Pipe src) unique
         | Unique(Iter3.Pipe src) unique
         | Intersperse(any sep, Iter3.Pipe src) unique
         | Cycle(Iter3.Pipe src) unique

    State = RangeS(number i)
          | ArrayS(number i)
          | CharsS(number i)
          | OnceS(boolean done)
          | RepS(number i)
          | TakeS(number seen, Iter3.State? inner)
          | SkipWhileS(boolean active, Iter3.State? inner)
          | ChainS(number phase, Iter3.State? left, Iter3.State? right)
          | ZipS(Iter3.State? left, Iter3.State? right)
          | EnumerateS(number idx, Iter3.State? inner)
          | ScanS(any acc, Iter3.State? inner)
          | FlatMapS(Iter3.State? outer, function? igen, any iparam, Iter3.State? inner)
          | DedupS(any prev, boolean have_prev, Iter3.State? inner)
          | WindowS(table buf, Iter3.State? inner, boolean first)
          | GroupByS(Iter3.State? inner, any head, any key, boolean active, boolean done)
          | UniqueS(table seen, Iter3.State? inner)
          | IntersperseS(Iter3.State? inner, number phase, any buffered)
}
]])

local I = ctx.Iter3
local Pipe = I.Pipe
local State = I.State

local Range, Array, Chars, Once, Rep, Empty = I.Range, I.Array, I.Chars, I.Once, I.Rep, I.Empty
local Map, Filter, Take, Skip = I.Map, I.Filter, I.Take, I.Skip
local TakeWhile, SkipWhile, Chain, Zip = I.TakeWhile, I.SkipWhile, I.Chain, I.Zip
local Enumerate, Scan, FlatMap = I.Enumerate, I.Scan, I.FlatMap
local Dedup, Tap, Window = I.Dedup, I.Tap, I.Window
local GroupBy, Unique, Intersperse, Cycle = I.GroupBy, I.Unique, I.Intersperse, I.Cycle

local RangeS, ArrayS, CharsS = I.RangeS, I.ArrayS, I.CharsS
local OnceS, RepS = I.OnceS, I.RepS
local TakeS, SkipWhileS = I.TakeS, I.SkipWhileS
local ChainS, ZipS = I.ChainS, I.ZipS
local EnumerateS, ScanS, FlatMapS = I.EnumerateS, I.ScanS, I.FlatMapS
local DedupS, WindowS = I.DedupS, I.WindowS
local GroupByS, UniqueS, IntersperseS = I.GroupByS, I.UniqueS, I.IntersperseS

local function mt(x)
	return getmetatable(x)
end

local function is_empty(x)
	return x == Empty
end

local function check_step(s)
	s = s or 1
	if s == 0 then
		error("iter3.range: step must not be 0", 3)
	end
	return s
end

local function fn_label(node)
	return node.fn_name or "fn"
end

-- ═══════════════════════════════════════════════════════════
--  DSL
-- ═══════════════════════════════════════════════════════════

function iter.range(a, b, s)
	if b == nil then
		a, b = 1, a
	end
	return Range(a, b, check_step(s))
end

function iter.from(t)
	return Array(t)
end
function iter.chars(s)
	return Chars(s)
end
function iter.once(v)
	return Once(v)
end
function iter.rep(v, n)
	return Rep(v, n)
end
function iter.empty()
	return Empty
end

function Pipe:map(fn, name)
	return Map(fn, name, self)
end
function Pipe:filter(fn, name)
	return Filter(fn, name, self)
end
function Pipe:take(n)
	return Take(n, self)
end
function Pipe:skip(n)
	return Skip(n, self)
end
function Pipe:take_while(fn, name)
	return TakeWhile(fn, name, self)
end
function Pipe:skip_while(fn, name)
	return SkipWhile(fn, name, self)
end
function Pipe:chain(other)
	return Chain(self, other)
end
function Pipe:zip(other)
	return Zip(self, other)
end
function Pipe:enumerate(start)
	return Enumerate(start or 1, self)
end
function Pipe:scan(fn, init, name)
	return Scan(fn, init, name, self)
end
function Pipe:flatmap(fn, name)
	return FlatMap(fn, name, self)
end
function Pipe:dedup()
	return Dedup(self)
end
function Pipe:tap(fn, name)
	return Tap(fn, name, self)
end
function Pipe:window(n)
	return Window(n, self)
end
function Pipe:group_by(fn, name)
	return GroupBy(fn, name, self)
end
function Pipe:unique()
	return Unique(self)
end
function Pipe:intersperse(sep)
	return Intersperse(sep, self)
end
function Pipe:cycle()
	return Cycle(self)
end

-- ═══════════════════════════════════════════════════════════
--  ANALYSIS / DESCRIPTION
-- ═══════════════════════════════════════════════════════════

local function depth(node)
	if is_empty(node) then
		return 1
	end
	local k = mt(node)
	if k == Range or k == Array or k == Chars or k == Once or k == Rep then
		return 1
	elseif k == Chain or k == Zip then
		local dl, dr = depth(node.left), depth(node.right)
		return 1 + (dl > dr and dl or dr)
	else
		return 1 + depth(node.src)
	end
end

local function node_count(node)
	if is_empty(node) then
		return 1
	end
	local k = mt(node)
	if k == Range or k == Array or k == Chars or k == Once or k == Rep then
		return 1
	elseif k == Chain or k == Zip then
		return 1 + node_count(node.left) + node_count(node.right)
	else
		return 1 + node_count(node.src)
	end
end

local function describe(node)
	if is_empty(node) then
		return "empty()"
	end
	local k = mt(node)
	if k == Range then
		return node.step == 1 and string.format("range(%s, %s)", tostring(node.lo), tostring(node.hi))
			or string.format("range(%s, %s, %s)", tostring(node.lo), tostring(node.hi), tostring(node.step))
	elseif k == Array then
		return string.format("array[%d]", #node.data)
	elseif k == Chars then
		return string.format("chars(%q)", node.str)
	elseif k == Once then
		return "once(" .. tostring(node.val) .. ")"
	elseif k == Rep then
		return string.format("rep(%s, %s)", tostring(node.val), tostring(node.n))
	elseif k == Map then
		return node.src:describe() .. " -> map(" .. fn_label(node) .. ")"
	elseif k == Filter then
		return node.src:describe() .. " -> filter(" .. fn_label(node) .. ")"
	elseif k == Take then
		return node.src:describe() .. " -> take(" .. tostring(node.n) .. ")"
	elseif k == Skip then
		return node.src:describe() .. " -> skip(" .. tostring(node.n) .. ")"
	elseif k == TakeWhile then
		return node.src:describe() .. " -> take_while(" .. fn_label(node) .. ")"
	elseif k == SkipWhile then
		return node.src:describe() .. " -> skip_while(" .. fn_label(node) .. ")"
	elseif k == Chain then
		return "chain(" .. node.left:describe() .. ", " .. node.right:describe() .. ")"
	elseif k == Zip then
		return "zip(" .. node.left:describe() .. ", " .. node.right:describe() .. ")"
	elseif k == Enumerate then
		return node.src:describe() .. " -> enumerate(" .. tostring(node.start) .. ")"
	elseif k == Scan then
		return node.src:describe() .. " -> scan(" .. fn_label(node) .. ", " .. tostring(node.init) .. ")"
	elseif k == FlatMap then
		return node.src:describe() .. " -> flatmap(" .. fn_label(node) .. ")"
	elseif k == Dedup then
		return node.src:describe() .. " -> dedup()"
	elseif k == Tap then
		return node.src:describe() .. " -> tap(" .. fn_label(node) .. ")"
	elseif k == Window then
		return node.src:describe() .. " -> window(" .. tostring(node.n) .. ")"
	elseif k == GroupBy then
		return node.src:describe() .. " -> group_by(" .. fn_label(node) .. ")"
	elseif k == Unique then
		return node.src:describe() .. " -> unique()"
	elseif k == Intersperse then
		return node.src:describe() .. " -> intersperse(" .. tostring(node.sep) .. ")"
	elseif k == Cycle then
		return node.src:describe() .. " -> cycle()"
	end
	return "<?>"
end

function Pipe:depth()
	return depth(self)
end
function Pipe:node_count()
	return node_count(self)
end
function Pipe:nodes()
	return node_count(self)
end
function Pipe:describe()
	return describe(self)
end
Pipe.__tostring = Pipe.describe

-- ═══════════════════════════════════════════════════════════
--  OPTIMIZATION (EXPLICIT)
-- ═══════════════════════════════════════════════════════════

local opt_cache = setmetatable({}, { __mode = "k" })

local function compose_names(a, b, sep)
	if a and b then
		return a .. sep .. b
	end
	return a or b
end

local function compose_map(outer, inner)
	return function(x)
		return outer(inner(x))
	end
end

local function compose_pred(outer, inner)
	return function(x)
		return inner(x) and outer(x)
	end
end

local function compose_tap(outer, inner)
	return function(x)
		inner(x)
		outer(x)
	end
end

local function mk_range(lo, hi, step)
	if step == 0 then
		error("iter3: range step must not be 0", 2)
	end
	if (step > 0 and lo > hi) or (step < 0 and lo < hi) then
		return Empty
	end
	return Range(lo, hi, step)
end

local function mk_rep(val, n)
	if n <= 0 then
		return Empty
	end
	return Rep(val, n)
end

local function range_take(n, src)
	local last = src.lo + (n - 1) * src.step
	if src.step > 0 then
		if last > src.hi then
			last = src.hi
		end
	else
		if last < src.hi then
			last = src.hi
		end
	end
	return mk_range(src.lo, last, src.step)
end

local function range_skip(n, src)
	return mk_range(src.lo + n * src.step, src.hi, src.step)
end

local optimize
optimize = function(node)
	local hit = opt_cache[node]
	if hit ~= nil then
		return hit
	end

	local out
	if is_empty(node) then
		out = node
	else
		local k = mt(node)

		if k == Range then
			out = mk_range(node.lo, node.hi, node.step)
		elseif k == Array or k == Chars or k == Once then
			out = node
		elseif k == Rep then
			out = mk_rep(node.val, node.n)
		elseif k == Map then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif mt(src) == Map then
				out = Map(compose_map(node.fn, src.fn), compose_names(node.fn_name, src.fn_name, "∘"), src.src)
			elseif src == node.src then
				out = node
			else
				out = Map(node.fn, node.fn_name, src)
			end
		elseif k == Filter then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif mt(src) == Filter then
				out = Filter(compose_pred(node.fn, src.fn), compose_names(src.fn_name, node.fn_name, "&"), src.src)
			elseif src == node.src then
				out = node
			else
				out = Filter(node.fn, node.fn_name, src)
			end
		elseif k == Take then
			if node.n <= 0 then
				out = Empty
			else
				local src = optimize(node.src)
				if is_empty(src) then
					out = Empty
				else
					local sk = mt(src)
					if sk == Take then
						out = optimize(Take(math.min(node.n, src.n), src.src))
					elseif sk == Range then
						out = range_take(node.n, src)
					elseif sk == Rep then
						out = mk_rep(src.val, math.min(node.n, src.n))
					elseif sk == Once then
						out = src
					elseif src == node.src then
						out = node
					else
						out = Take(node.n, src)
					end
				end
			end
		elseif k == Skip then
			local src = optimize(node.src)
			if node.n <= 0 then
				out = src
			elseif is_empty(src) then
				out = Empty
			else
				local sk = mt(src)
				if sk == Skip then
					out = optimize(Skip(node.n + src.n, src.src))
				elseif sk == Range then
					out = range_skip(node.n, src)
				elseif sk == Rep then
					out = mk_rep(src.val, src.n - node.n)
				elseif sk == Once then
					out = Empty
				elseif src == node.src then
					out = node
				else
					out = Skip(node.n, src)
				end
			end
		elseif k == TakeWhile then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif src == node.src then
				out = node
			else
				out = TakeWhile(node.fn, node.fn_name, src)
			end
		elseif k == SkipWhile then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif src == node.src then
				out = node
			else
				out = SkipWhile(node.fn, node.fn_name, src)
			end
		elseif k == Chain then
			local l, r = optimize(node.left), optimize(node.right)
			if is_empty(l) then
				out = r
			elseif is_empty(r) then
				out = l
			elseif l == node.left and r == node.right then
				out = node
			else
				out = Chain(l, r)
			end
		elseif k == Zip then
			local l, r = optimize(node.left), optimize(node.right)
			if is_empty(l) or is_empty(r) then
				out = Empty
			elseif l == node.left and r == node.right then
				out = node
			else
				out = Zip(l, r)
			end
		elseif k == Enumerate then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif src == node.src then
				out = node
			else
				out = Enumerate(node.start, src)
			end
		elseif k == Scan then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif src == node.src then
				out = node
			else
				out = Scan(node.fn, node.init, node.fn_name, src)
			end
		elseif k == FlatMap then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif src == node.src then
				out = node
			else
				out = FlatMap(node.fn, node.fn_name, src)
			end
		elseif k == Dedup then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif mt(src) == Dedup then
				out = src
			elseif src == node.src then
				out = node
			else
				out = Dedup(src)
			end
		elseif k == Tap then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif mt(src) == Tap then
				out = Tap(compose_tap(node.fn, src.fn), compose_names(node.fn_name, src.fn_name, "+"), src.src)
			elseif src == node.src then
				out = node
			else
				out = Tap(node.fn, node.fn_name, src)
			end
		elseif k == Window then
			if node.n <= 0 then
				out = Empty
			else
				local src = optimize(node.src)
				if is_empty(src) then
					out = Empty
				elseif src == node.src then
					out = node
				else
					out = Window(node.n, src)
				end
			end
		elseif k == GroupBy then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif src == node.src then
				out = node
			else
				out = GroupBy(node.fn, node.fn_name, src)
			end
		elseif k == Unique then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif mt(src) == Unique then
				out = src
			elseif src == node.src then
				out = node
			else
				out = Unique(src)
			end
		elseif k == Intersperse then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif src == node.src then
				out = node
			else
				out = Intersperse(node.sep, src)
			end
		elseif k == Cycle then
			local src = optimize(node.src)
			if is_empty(src) then
				out = Empty
			elseif src == node.src then
				out = node
			else
				out = Cycle(src)
			end
		else
			out = node
		end
	end

	opt_cache[node] = out
	return out
end

function Pipe:optimize()
	return optimize(self)
end
function Pipe:normalize()
	return optimize(self)
end

-- ═══════════════════════════════════════════════════════════
--  RUNTIME: gen/param/state
-- ═══════════════════════════════════════════════════════════

local function init_nil()
	return nil
end

local function init_passthrough(p)
	return p[3](p[2])
end

local function gen_empty(_p, _s)
	return nil
end

local function init_range(p)
	return RangeS(p[1] - p[3])
end

local function gen_range(p, s)
	if s == nil then
		return nil
	end
	local i = s.i + p[3]
	if p[3] > 0 then
		if i > p[2] then
			return nil
		end
	else
		if i < p[2] then
			return nil
		end
	end
	s.i = i
	return s, i
end

local function init_array(_p)
	return ArrayS(0)
end

local function gen_array(p, s)
	if s == nil then
		return nil
	end
	local i = s.i + 1
	if i > p[2] then
		return nil
	end
	s.i = i
	return s, p[1][i]
end

local function init_chars(_p)
	return CharsS(0)
end

local function gen_chars(p, s)
	if s == nil then
		return nil
	end
	local i = s.i + 1
	if i > p[2] then
		return nil
	end
	s.i = i
	return s, p[1]:sub(i, i)
end

local function init_once(_p)
	return OnceS(false)
end

local function gen_once(p, s)
	if s == nil or s.done then
		return nil
	end
	s.done = true
	return s, p[1]
end

local function init_rep(_p)
	return RepS(0)
end

local function gen_rep(p, s)
	if s == nil then
		return nil
	end
	local i = s.i + 1
	if i > p[2] then
		return nil
	end
	s.i = i
	return s, p[1]
end

local function gen_map(p, s)
	if s == nil then
		return nil
	end
	local ns, v = p[1](p[2], s)
	if ns == nil then
		return nil
	end
	return ns, p[4](v)
end

local function gen_filter(p, s)
	if s == nil then
		return nil
	end
	local ns, v = p[1](p[2], s)
	while ns ~= nil do
		if p[4](v) then
			return ns, v
		end
		ns, v = p[1](p[2], ns)
	end
	return nil
end

local function init_take(p)
	return TakeS(0, p[3](p[2]))
end

local function gen_take(p, s)
	if s == nil then
		return nil
	end
	if s.seen >= p[4] then
		return nil
	end
	local ns, v = p[1](p[2], s.inner)
	if ns == nil then
		return nil
	end
	s.seen = s.seen + 1
	s.inner = ns
	return s, v
end

local function init_skip(p)
	local s = p[3](p[2])
	for _ = 1, p[4] do
		s = p[1](p[2], s)
		if s == nil then
			return nil
		end
	end
	return s
end

local function gen_skip(p, s)
	if s == nil then
		return nil
	end
	return p[1](p[2], s)
end

local function gen_take_while(p, s)
	if s == nil then
		return nil
	end
	local ns, v = p[1](p[2], s)
	if ns == nil then
		return nil
	end
	if not p[4](v) then
		return nil
	end
	return ns, v
end

local function init_skip_while(p)
	return SkipWhileS(true, p[3](p[2]))
end

local function gen_skip_while(p, s)
	if s == nil then
		return nil
	end
	local ns, v = p[1](p[2], s.inner)
	while ns ~= nil do
		if not s.active then
			s.inner = ns
			return s, v
		end
		if not p[4](v) then
			s.active = false
			s.inner = ns
			return s, v
		end
		ns, v = p[1](p[2], ns)
	end
	return nil
end

local function init_chain(p)
	return ChainS(1, p[3](p[2]), p[6](p[5]))
end

local function gen_chain(p, s)
	if s == nil then
		return nil
	end
	if s.phase == 1 then
		local ns, v = p[1](p[2], s.left)
		if ns ~= nil then
			s.left = ns
			return s, v
		end
		s.phase = 2
	end
	local ns, v = p[4](p[5], s.right)
	if ns == nil then
		return nil
	end
	s.right = ns
	return s, v
end

local function init_zip(p)
	return ZipS(p[3](p[2]), p[6](p[5]))
end

local function gen_zip(p, s)
	if s == nil then
		return nil
	end
	local sa, va = p[1](p[2], s.left)
	if sa == nil then
		return nil
	end
	local sb, vb = p[4](p[5], s.right)
	if sb == nil then
		return nil
	end
	s.left, s.right = sa, sb
	return s, { va, vb }
end

local function init_enumerate(p)
	return EnumerateS(p[4] - 1, p[3](p[2]))
end

local function gen_enumerate(p, s)
	if s == nil then
		return nil
	end
	local ns, v = p[1](p[2], s.inner)
	if ns == nil then
		return nil
	end
	s.idx = s.idx + 1
	s.inner = ns
	return s, { s.idx, v }
end

local function init_scan(p)
	return ScanS(p[5], p[3](p[2]))
end

local function gen_scan(p, s)
	if s == nil then
		return nil
	end
	local ns, v = p[1](p[2], s.inner)
	if ns == nil then
		return nil
	end
	s.acc = p[4](s.acc, v)
	s.inner = ns
	return s, s.acc
end

local function to_triplet(a, b, c)
	if type(a) == "function" then
		return a, b, c
	end
	if type(a) == "table" then
		local triplet = a.triplet
		if triplet == nil then
			local m = mt(a)
			triplet = m and m.triplet or nil
		end
		if type(triplet) == "function" then
			return triplet(a)
		end
	end
	error("iter3.flatmap: expected pipeline, plan, or gen/param/state triplet", 3)
end

local function init_flatmap(p)
	return FlatMapS(p[3](p[2]), nil, nil, nil)
end

local function gen_flatmap(p, s)
	if s == nil then
		return nil
	end
	while true do
		if s.igen ~= nil then
			local ns, v = s.igen(s.iparam, s.inner)
			if ns ~= nil then
				s.inner = ns
				return s, v
			end
			s.igen, s.iparam, s.inner = nil, nil, nil
		end

		local ns, v = p[1](p[2], s.outer)
		if ns == nil then
			return nil
		end
		s.outer = ns
		s.igen, s.iparam, s.inner = to_triplet(p[4](v))
	end
end

local function init_dedup(p)
	return DedupS(nil, false, p[3](p[2]))
end

local function gen_dedup(p, s)
	if s == nil then
		return nil
	end
	local ns, v = p[1](p[2], s.inner)
	while ns ~= nil do
		if not s.have_prev or v ~= s.prev then
			s.prev = v
			s.have_prev = true
			s.inner = ns
			return s, v
		end
		ns, v = p[1](p[2], ns)
	end
	return nil
end

local function gen_tap(p, s)
	if s == nil then
		return nil
	end
	local ns, v = p[1](p[2], s)
	if ns == nil then
		return nil
	end
	p[4](v)
	return ns, v
end

local function init_window(p)
	local ss = p[3](p[2])
	local buf = {}
	for i = 1, p[4] do
		local ns, v = p[1](p[2], ss)
		if ns == nil then
			return nil
		end
		ss = ns
		buf[i] = v
	end
	return WindowS(buf, ss, true)
end

local function gen_window(p, s)
	if s == nil then
		return nil
	end
	local buf, ss, first = s.buf, s.inner, s.first
	if first then
		local out = {}
		for i = 1, #buf do
			out[i] = buf[i]
		end
		s.first = false
		return s, out
	end
	local ns, v = p[1](p[2], ss)
	if ns == nil then
		return nil
	end
	local nb = {}
	for i = 2, #buf do
		nb[i - 1] = buf[i]
	end
	nb[#buf] = v
	s.buf = nb
	s.inner = ns
	local out = {}
	for i = 1, #nb do
		out[i] = nb[i]
	end
	return s, out
end

local function init_group_by(p)
	local ss = p[3](p[2])
	local ns, v = p[1](p[2], ss)
	if ns == nil then
		return GroupByS(nil, nil, nil, false, true)
	end
	return GroupByS(ns, v, p[4](v), true, false)
end

local function gen_group_by(p, s)
	if s == nil or s.done or not s.active then
		return nil
	end
	local group = { s.head }
	local key = s.key
	local ss = s.inner
	while true do
		local ns, nv = p[1](p[2], ss)
		if ns == nil then
			s.inner, s.head, s.key, s.active, s.done = nil, nil, nil, false, true
			return s, { key = key, items = group }
		end
		ss = ns
		local nk = p[4](nv)
		if nk ~= key then
			s.inner, s.head, s.key, s.active, s.done = ss, nv, nk, true, false
			return s, { key = key, items = group }
		end
		group[#group + 1] = nv
	end
end

local function init_unique(p)
	return UniqueS({}, p[3](p[2]))
end

local function gen_unique(p, s)
	if s == nil then
		return nil
	end
	local ns, v = p[1](p[2], s.inner)
	while ns ~= nil do
		if not s.seen[v] then
			s.seen[v] = true
			s.inner = ns
			return s, v
		end
		ns, v = p[1](p[2], ns)
	end
	return nil
end

local function init_intersperse(p)
	return IntersperseS(p[3](p[2]), 0, nil)
end

local function gen_intersperse(p, s)
	if s == nil then
		return nil
	end
	local phase = s.phase
	if phase == 0 then
		local ns, v = p[1](p[2], s.inner)
		if ns == nil then
			return nil
		end
		s.inner, s.phase, s.buffered = ns, 1, nil
		return s, v
	elseif phase == 1 then
		local ns, v = p[1](p[2], s.inner)
		if ns == nil then
			return nil
		end
		s.inner, s.phase, s.buffered = ns, 2, v
		return s, p[4]
	else
		s.phase = 1
		local v = s.buffered
		s.buffered = nil
		return s, v
	end
end

local function gen_cycle(p, s)
	local ns, v = p[1](p[2], s)
	if ns ~= nil then
		return ns, v
	end
	local s0 = p[3](p[2])
	if s0 == nil then
		return nil
	end
	return p[1](p[2], s0)
end

-- ═══════════════════════════════════════════════════════════
--  LOWERING (DIRECT, NO CODEGEN)
-- ═══════════════════════════════════════════════════════════

local LEAF_GEN = {
	Range = gen_range,
	Array = gen_array,
	Chars = gen_chars,
	Once = gen_once,
	Rep = gen_rep,
}

local LEAF_INIT = {
	Range = init_range,
	Array = init_array,
	Chars = init_chars,
	Once = init_once,
	Rep = init_rep,
}

local LEAF_PARAM = {
	Range = function(node)
		return { node.lo, node.hi, node.step }
	end,
	Array = function(node)
		return { node.data, #node.data }
	end,
	Chars = function(node)
		return { node.str, #node.str }
	end,
	Once = function(node)
		return { node.val }
	end,
	Rep = function(node)
		return { node.val, node.n }
	end,
}

local UNARY_GEN = {
	Map = gen_map,
	Filter = gen_filter,
	Take = gen_take,
	Skip = gen_skip,
	TakeWhile = gen_take_while,
	SkipWhile = gen_skip_while,
	Enumerate = gen_enumerate,
	Scan = gen_scan,
	FlatMap = gen_flatmap,
	Dedup = gen_dedup,
	Tap = gen_tap,
	Window = gen_window,
	GroupBy = gen_group_by,
	Unique = gen_unique,
	Intersperse = gen_intersperse,
	Cycle = gen_cycle,
}

local UNARY_INIT = {
	Map = init_passthrough,
	Filter = init_passthrough,
	Take = init_take,
	Skip = init_skip,
	TakeWhile = init_passthrough,
	SkipWhile = init_skip_while,
	Enumerate = init_enumerate,
	Scan = init_scan,
	FlatMap = init_flatmap,
	Dedup = init_dedup,
	Tap = init_passthrough,
	Window = init_window,
	GroupBy = init_group_by,
	Unique = init_unique,
	Intersperse = init_intersperse,
	Cycle = init_passthrough,
}

local lower
lower = function(node)
	if node == Empty then
		return gen_empty, false, init_nil
	end

	local kind = node.kind
	local g0 = LEAF_GEN[kind]
	if g0 ~= nil then
		return g0, LEAF_PARAM[kind](node), LEAF_INIT[kind]
	end

	if kind == "Chain" then
		local lg, lp, li = lower(node.left)
		local rg, rp, ri = lower(node.right)
		return gen_chain, { lg, lp, li, rg, rp, ri }, init_chain
	elseif kind == "Zip" then
		local lg, lp, li = lower(node.left)
		local rg, rp, ri = lower(node.right)
		return gen_zip, { lg, lp, li, rg, rp, ri }, init_zip
	end

	local g, p, i = lower(node.src)
	if
		kind == "Map"
		or kind == "Filter"
		or kind == "TakeWhile"
		or kind == "SkipWhile"
		or kind == "FlatMap"
		or kind == "Tap"
		or kind == "GroupBy"
	then
		return UNARY_GEN[kind], { g, p, i, node.fn }, UNARY_INIT[kind]
	elseif kind == "Take" or kind == "Skip" or kind == "Window" then
		return UNARY_GEN[kind], { g, p, i, node.n }, UNARY_INIT[kind]
	elseif kind == "Enumerate" then
		return UNARY_GEN[kind], { g, p, i, node.start }, UNARY_INIT[kind]
	elseif kind == "Scan" then
		return UNARY_GEN[kind], { g, p, i, node.fn, node.init }, UNARY_INIT[kind]
	elseif kind == "Dedup" or kind == "Unique" or kind == "Cycle" then
		return UNARY_GEN[kind], { g, p, i }, UNARY_INIT[kind]
	elseif kind == "Intersperse" then
		return UNARY_GEN[kind], { g, p, i, node.sep }, UNARY_INIT[kind]
	end

	error("iter3.lower: unknown node kind " .. tostring(kind), 2)
end

-- ═══════════════════════════════════════════════════════════
--  PLAN OBJECT
-- ═══════════════════════════════════════════════════════════

local Plan = {}
Plan.__index = Plan

function Plan:triplet()
	return self.gen, self.param, self.init(self.param)
end

function Plan:describe()
	return self.node:describe()
end

Plan.__tostring = Plan.describe

-- ═══════════════════════════════════════════════════════════
--  REDUCERS
-- ═══════════════════════════════════════════════════════════

local function do_collect(gen, param, state)
	local out, n = {}, 0
	local v
	state, v = gen(param, state)
	while state ~= nil do
		n = n + 1
		out[n] = v
		state, v = gen(param, state)
	end
	return out
end

local function do_fold(gen, param, state, fn, acc)
	local v
	state, v = gen(param, state)
	while state ~= nil do
		acc = fn(acc, v)
		state, v = gen(param, state)
	end
	return acc
end

local function do_each(gen, param, state, fn)
	local v
	state, v = gen(param, state)
	while state ~= nil do
		fn(v)
		state, v = gen(param, state)
	end
end

local function do_sum(gen, param, state)
	local acc, v = 0, nil
	state, v = gen(param, state)
	while state ~= nil do
		acc = acc + v
		state, v = gen(param, state)
	end
	return acc
end

local function do_count(gen, param, state)
	local n = 0
	state = gen(param, state)
	while state ~= nil do
		n = n + 1
		state = gen(param, state)
	end
	return n
end

local function do_first(gen, param, state)
	local _, v = gen(param, state)
	return v
end

local function do_last(gen, param, state)
	local r, v = nil, nil
	state, v = gen(param, state)
	while state ~= nil do
		r = v
		state, v = gen(param, state)
	end
	return r
end

local function do_min(gen, param, state)
	local r, v = nil, nil
	state, v = gen(param, state)
	while state ~= nil do
		if r == nil or v < r then
			r = v
		end
		state, v = gen(param, state)
	end
	return r
end

local function do_max(gen, param, state)
	local r, v = nil, nil
	state, v = gen(param, state)
	while state ~= nil do
		if r == nil or v > r then
			r = v
		end
		state, v = gen(param, state)
	end
	return r
end

local function do_any(gen, param, state, fn)
	local v
	state, v = gen(param, state)
	while state ~= nil do
		if fn(v) then
			return true
		end
		state, v = gen(param, state)
	end
	return false
end

local function do_all(gen, param, state, fn)
	local v
	state, v = gen(param, state)
	while state ~= nil do
		if not fn(v) then
			return false
		end
		state, v = gen(param, state)
	end
	return true
end

function Pipe:triplet()
	local gen, param, init = lower(self)
	return gen, param, init(param)
end

function Pipe:plan()
	local gen, param, init = lower(self)
	return setmetatable({ node = self, gen = gen, param = param, init = init }, Plan)
end

function Pipe:collect()
	local gen, param, state = self:triplet()
	return do_collect(gen, param, state)
end

function Plan:collect()
	local gen, param, state = self:triplet()
	return do_collect(gen, param, state)
end

function Pipe:fold(fn, acc)
	local gen, param, state = self:triplet()
	return do_fold(gen, param, state, fn, acc)
end

function Plan:fold(fn, acc)
	local gen, param, state = self:triplet()
	return do_fold(gen, param, state, fn, acc)
end

function Pipe:each(fn)
	local gen, param, state = self:triplet()
	return do_each(gen, param, state, fn)
end

function Plan:each(fn)
	local gen, param, state = self:triplet()
	return do_each(gen, param, state, fn)
end

function Pipe:sum()
	local gen, param, state = self:triplet()
	return do_sum(gen, param, state)
end

function Plan:sum()
	local gen, param, state = self:triplet()
	return do_sum(gen, param, state)
end

function Pipe:count()
	local gen, param, state = self:triplet()
	return do_count(gen, param, state)
end

function Plan:count()
	local gen, param, state = self:triplet()
	return do_count(gen, param, state)
end

function Pipe:first()
	local gen, param, state = self:triplet()
	return do_first(gen, param, state)
end

function Plan:first()
	local gen, param, state = self:triplet()
	return do_first(gen, param, state)
end

function Pipe:last()
	local gen, param, state = self:triplet()
	return do_last(gen, param, state)
end

function Plan:last()
	local gen, param, state = self:triplet()
	return do_last(gen, param, state)
end

function Pipe:min()
	local gen, param, state = self:triplet()
	return do_min(gen, param, state)
end

function Plan:min()
	local gen, param, state = self:triplet()
	return do_min(gen, param, state)
end

function Pipe:max()
	local gen, param, state = self:triplet()
	return do_max(gen, param, state)
end

function Plan:max()
	local gen, param, state = self:triplet()
	return do_max(gen, param, state)
end

function Pipe:any(fn)
	local gen, param, state = self:triplet()
	return do_any(gen, param, state, fn)
end

function Plan:any(fn)
	local gen, param, state = self:triplet()
	return do_any(gen, param, state, fn)
end

function Pipe:all(fn)
	local gen, param, state = self:triplet()
	return do_all(gen, param, state, fn)
end

function Plan:all(fn)
	local gen, param, state = self:triplet()
	return do_all(gen, param, state, fn)
end

function Pipe:join(sep)
	return table.concat(self:collect(), sep or ", ")
end
function Plan:join(sep)
	return table.concat(self:collect(), sep or ", ")
end

function Pipe:nth(n)
	return self:skip(n - 1):first()
end
function Plan:nth(n)
	return self.node:skip(n - 1):plan():first()
end

function Pipe:contains(val)
	return self:any(function(v)
		return v == val
	end)
end
function Plan:contains(val)
	return self:any(function(v)
		return v == val
	end)
end

function Pipe:partition(fn)
	local yes, no = {}, {}
	self:each(function(v)
		if fn(v) then
			yes[#yes + 1] = v
		else
			no[#no + 1] = v
		end
	end)
	return yes, no
end

function Plan:partition(fn)
	local yes, no = {}, {}
	self:each(function(v)
		if fn(v) then
			yes[#yes + 1] = v
		else
			no[#no + 1] = v
		end
	end)
	return yes, no
end

function Pipe:to_map(kf)
	local out = {}
	self:each(function(v)
		out[kf(v)] = v
	end)
	return out
end

function Plan:to_map(kf)
	local out = {}
	self:each(function(v)
		out[kf(v)] = v
	end)
	return out
end

-- ═══════════════════════════════════════════════════════════
--  STATE CLONING
-- ═══════════════════════════════════════════════════════════

local function clone(x)
	if type(x) ~= "table" then
		return x
	end
	local out = {}
	for k, v in pairs(x) do
		out[k] = clone(v)
	end
	return setmetatable(out, mt(x))
end

iter.clone = clone

-- ═══════════════════════════════════════════════════════════
--  MODULE EXTRAS
-- ═══════════════════════════════════════════════════════════

iter.types = function()
	return ctx
end
iter.Pipe = I.Pipe
iter.State = State
iter.depth = depth
iter.node_count = node_count
iter.describe = describe
iter.optimize = optimize
iter.normalize = optimize
iter.lower = lower
iter.plan = function(node)
	return node:plan()
end
iter.Plan = Plan

return iter
