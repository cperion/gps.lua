-- iterkit.lua — composable iterators, interpreted and compiled
--
-- Three primitives:
--   gen, param, state — the triplet
--   Quote             — turns param trees into flat loops
--
-- Usage:
--   local it = require("iterkit")
--
--   -- build a pipeline (just data)
--   local p = it.range(1, 1000)
--              :filter(function(x) return x % 2 == 1 end)
--              :map(function(x) return x * x end)
--              :take(100)
--
--   -- inspect it
--   print(p)                    -- human-readable pipeline
--   print(p:depth())            -- how deep
--
--   -- run interpreted (generic, always works)
--   p:collect()                 -- → table
--   p:fold(add, 0)              -- → value
--   p:sum()                     -- → number
--   p:each(print)               -- side effects
--
--   -- compile and run (fast, generated code)
--   local fast = p:compile()
--   fast:collect()              -- same results, flat loop
--   fast:fold(add, 0)           -- same results, flat loop
--   print(fast:source())        -- see the generated code
--
--   -- the triplet is always available
--   local gen, param, state = p:triplet()
--   -- use in a raw for-loop, or hand to another system

local Quote = require("quote")
local it = {}

-- ═══════════════════════════════════════════════════════════
--  PARAM NODE (the tree)
-- ═══════════════════════════════════════════════════════════

local P = {}; P.__index = P

local function node(fields)
   return setmetatable(fields, P)
end

-- ═══════════════════════════════════════════════════════════
--  ATOMS — produce a pipeline
-- ═══════════════════════════════════════════════════════════

function it.range(a, b, s)
   if b == nil then a, b = 1, a end
   return node { tag = "range", lo = a, hi = b, step = s or 1 }
end

function it.from(t)
   return node { tag = "array", data = t }
end

function it.chars(s)
   return node { tag = "chars", str = s }
end

function it.once(v)
   return node { tag = "once", val = v }
end

function it.rep(v, n)
   return node { tag = "rep", val = v, n = n }
end

function it.empty()
   return node { tag = "empty" }
end

-- ═══════════════════════════════════════════════════════════
--  COMBINATORS — transform a pipeline, return a new pipeline
--  All hang off P so you can chain: it.range(10):map(f):filter(g)
-- ═══════════════════════════════════════════════════════════

function P:map(fn, name)
   return node { tag = "map", fn = fn, fn_name = name, src = self }
end

function P:filter(fn, name)
   return node { tag = "filter", fn = fn, fn_name = name, src = self }
end

function P:take(n)
   return node { tag = "take", n = n, src = self }
end

function P:skip(n)
   return node { tag = "skip", n = n, src = self }
end

function P:take_while(fn, name)
   return node { tag = "take_while", fn = fn, fn_name = name, src = self }
end

function P:skip_while(fn, name)
   return node { tag = "skip_while", fn = fn, fn_name = name, src = self }
end

function P:chain(other)
   return node { tag = "chain", left = self, right = other }
end

function P:zip(other)
   return node { tag = "zip", left = self, right = other }
end

function P:enumerate(start)
   return node { tag = "enumerate", start = start or 1, src = self }
end

function P:scan(fn, init, name)
   return node { tag = "scan", fn = fn, init = init, fn_name = name, src = self }
end

function P:flatmap(fn, name)
   return node { tag = "flatmap", fn = fn, fn_name = name, src = self }
end

function P:dedup()
   return node { tag = "dedup", src = self }
end

function P:window(n)
   return node { tag = "window", n = n, src = self }
end

function P:tap(fn, name)
   return node { tag = "tap", fn = fn, fn_name = name, src = self }
end

-- ═══════════════════════════════════════════════════════════
--  INTERPRETER — one gen, dispatches on tag
-- ═══════════════════════════════════════════════════════════

local step, init_state

step = function(p, s)
   local tag = p.tag

   if tag == "range" then
      local i = s + p.step
      if (p.step > 0 and i > p.hi) or (p.step < 0 and i < p.hi) then return nil end
      return i, i

   elseif tag == "array" then
      local i = s + 1
      if i > #p.data then return nil end
      return i, p.data[i]

   elseif tag == "chars" then
      local i = s + 1
      if i > #p.str then return nil end
      return i, p.str:sub(i, i)

   elseif tag == "once" then
      if s then return nil end
      return true, p.val

   elseif tag == "rep" then
      local i = s + 1
      if i > p.n then return nil end
      return i, p.val

   elseif tag == "empty" then
      return nil

   elseif tag == "map" then
      local ns, v = step(p.src, s)
      if ns == nil then return nil end
      return ns, p.fn(v)

   elseif tag == "filter" then
      local ns, v = step(p.src, s)
      while ns ~= nil do
         if p.fn(v) then return ns, v end
         ns, v = step(p.src, ns)
      end
      return nil

   elseif tag == "take" then
      if s[1] >= p.n then return nil end
      local ns, v = step(p.src, s[2])
      if ns == nil then return nil end
      return { s[1] + 1, ns }, v

   elseif tag == "skip" then
      local ns, v = step(p.src, s)
      if ns == nil then return nil end
      return ns, v

   elseif tag == "take_while" then
      if s[1] then return nil end
      local ns, v = step(p.src, s[2])
      if ns == nil then return nil end
      if not p.fn(v) then return nil end
      return { false, ns }, v

   elseif tag == "skip_while" then
      if s[1] then
         local ns, v = step(p.src, s[2])
         while ns ~= nil do
            if not p.fn(v) then return { false, ns }, v end
            ns, v = step(p.src, ns)
         end
         return nil
      else
         local ns, v = step(p.src, s[2])
         if ns == nil then return nil end
         return { false, ns }, v
      end

   elseif tag == "chain" then
      if s[1] == 1 then
         local ns, v = step(p.left, s[2])
         if ns ~= nil then return { 1, ns, s[3] }, v end
         s = { 2, s[2], s[3] }
      end
      local ns, v = step(p.right, s[3])
      if ns == nil then return nil end
      return { 2, s[2], ns }, v

   elseif tag == "zip" then
      local sa, va = step(p.left, s[1])
      if sa == nil then return nil end
      local sb, vb = step(p.right, s[2])
      if sb == nil then return nil end
      return { sa, sb }, { va, vb }

   elseif tag == "enumerate" then
      local ns, v = step(p.src, s[2])
      if ns == nil then return nil end
      local idx = s[1] + 1
      return { idx, ns }, { idx, v }

   elseif tag == "scan" then
      local ns, v = step(p.src, s[2])
      if ns == nil then return nil end
      local acc = p.fn(s[1], v)
      return { acc, ns }, acc

   elseif tag == "flatmap" then
      while true do
         if s[2] then
            local ns, v = step(s[2], s[3])
            if ns ~= nil then return { s[1], s[2], ns }, v end
         end
         local ns, v = step(p.src, s[1])
         if ns == nil then return nil end
         local ip = p.fn(v)
         s = { ns, ip, init_state(ip) }
      end

   elseif tag == "dedup" then
      local ns, v = step(p.src, s[2])
      while ns ~= nil do
         if not s[3] or v ~= s[1] then
            return { v, ns, true }, v
         end
         ns, v = step(p.src, ns)
      end
      return nil

   elseif tag == "tap" then
      local ns, v = step(p.src, s)
      if ns == nil then return nil end
      p.fn(v)
      return ns, v

   elseif tag == "window" then
      local buf, ss, first = s[1], s[2], s[3]
      if first then
         local out = {}
         for i = 1, #buf do out[i] = buf[i] end
         return { buf, ss, false }, out
      end
      local ns, v = step(p.src, ss)
      if ns == nil then return nil end
      local nb = {}
      for i = 2, #buf do nb[i-1] = buf[i] end
      nb[#buf] = v
      local out = {}
      for i = 1, #nb do out[i] = nb[i] end
      return { nb, ns, false }, out
   end

   error("iterkit: unknown tag '" .. tostring(tag) .. "'")
end

init_state = function(p)
   local tag = p.tag
   if tag == "range"      then return p.lo - p.step
   elseif tag == "array"      then return 0
   elseif tag == "chars"      then return 0
   elseif tag == "once"       then return false
   elseif tag == "rep"        then return 0
   elseif tag == "empty"      then return nil
   elseif tag == "map"        then return init_state(p.src)
   elseif tag == "filter"     then return init_state(p.src)
   elseif tag == "tap"        then return init_state(p.src)
   elseif tag == "take"       then return { 0, init_state(p.src) }
   elseif tag == "take_while" then return { false, init_state(p.src) }
   elseif tag == "skip_while" then return { true, init_state(p.src) }
   elseif tag == "chain"      then return { 1, init_state(p.left), init_state(p.right) }
   elseif tag == "zip"        then return { init_state(p.left), init_state(p.right) }
   elseif tag == "enumerate"  then return { (p.start or 1) - 1, init_state(p.src) }
   elseif tag == "scan"       then return { p.init, init_state(p.src) }
   elseif tag == "flatmap"    then return { init_state(p.src), false, nil }
   elseif tag == "dedup"      then return { nil, init_state(p.src), false }
   elseif tag == "skip" then
      local ss = init_state(p.src)
      for _ = 1, p.n do
         ss = step(p.src, ss)
         if ss == nil then return nil end
      end
      return ss
   elseif tag == "window" then
      local ss = init_state(p.src)
      local buf = {}
      for i = 1, p.n do
         local ns, v = step(p.src, ss)
         if ns == nil then return nil end
         ss = ns; buf[i] = v
      end
      return { buf, ss, true }
   end
   error("iterkit: unknown tag '" .. tostring(tag) .. "'")
end

-- ═══════════════════════════════════════════════════════════
--  TRIPLET — raw gen, param, state for external use
-- ═══════════════════════════════════════════════════════════

function P:triplet()
   return step, self, init_state(self)
end

-- ═══════════════════════════════════════════════════════════
--  INTERPRETED REDUCERS
-- ═══════════════════════════════════════════════════════════

function P:collect()
   local out, n = {}, 0
   local s = init_state(self)
   local v
   s, v = step(self, s)
   while s ~= nil do
      n = n + 1; out[n] = v
      s, v = step(self, s)
   end
   return out
end

function P:fold(fn, init)
   local acc = init
   local s = init_state(self)
   local v
   s, v = step(self, s)
   while s ~= nil do
      acc = fn(acc, v)
      s, v = step(self, s)
   end
   return acc
end

function P:sum()
   return self:fold(function(a, b) return a + b end, 0)
end

function P:count()
   return self:fold(function(a, _) return a + 1 end, 0)
end

function P:min()
   return self:fold(function(a, b) return a == nil and b or (b < a and b or a) end, nil)
end

function P:max()
   return self:fold(function(a, b) return a == nil and b or (b > a and b or a) end, nil)
end

function P:first()
   local s, v = step(self, init_state(self))
   return v
end

function P:last()
   local r = nil
   local s = init_state(self)
   local v
   s, v = step(self, s)
   while s ~= nil do r = v; s, v = step(self, s) end
   return r
end

function P:each(fn)
   local s = init_state(self)
   local v
   s, v = step(self, s)
   while s ~= nil do fn(v); s, v = step(self, s) end
end

function P:any(fn)
   local s = init_state(self)
   local v
   s, v = step(self, s)
   while s ~= nil do
      if fn(v) then return true end
      s, v = step(self, s)
   end
   return false
end

function P:all(fn)
   local s = init_state(self)
   local v
   s, v = step(self, s)
   while s ~= nil do
      if not fn(v) then return false end
      s, v = step(self, s)
   end
   return true
end

function P:join(sep)
   return table.concat(self:collect(), sep or ", ")
end

-- ═══════════════════════════════════════════════════════════
--  INTROSPECTION — because param is data
-- ═══════════════════════════════════════════════════════════

function P:describe(indent)
   indent = indent or 0
   local pad = string.rep("  ", indent)
   local tag = self.tag
   local name = self.fn_name or "fn"

   if     tag == "range"     then
      local s = self.step ~= 1 and (", " .. self.step) or ""
      return pad .. "range(" .. self.lo .. ", " .. self.hi .. s .. ")"
   elseif tag == "array"     then return pad .. "array[" .. #self.data .. "]"
   elseif tag == "chars"     then return pad .. 'chars("' .. self.str .. '")'
   elseif tag == "once"      then return pad .. "once(" .. tostring(self.val) .. ")"
   elseif tag == "rep"       then return pad .. "rep(" .. tostring(self.val) .. ", " .. self.n .. ")"
   elseif tag == "empty"     then return pad .. "empty()"

   elseif tag == "map"       then return self.src:describe(indent) .. "\n" .. pad .. "  → map(" .. name .. ")"
   elseif tag == "filter"    then return self.src:describe(indent) .. "\n" .. pad .. "  → filter(" .. name .. ")"
   elseif tag == "take"      then return self.src:describe(indent) .. "\n" .. pad .. "  → take(" .. self.n .. ")"
   elseif tag == "skip"      then return self.src:describe(indent) .. "\n" .. pad .. "  → skip(" .. self.n .. ")"
   elseif tag == "take_while" then return self.src:describe(indent) .. "\n" .. pad .. "  → take_while(" .. name .. ")"
   elseif tag == "skip_while" then return self.src:describe(indent) .. "\n" .. pad .. "  → skip_while(" .. name .. ")"
   elseif tag == "scan"      then return self.src:describe(indent) .. "\n" .. pad .. "  → scan(" .. name .. ", " .. tostring(self.init) .. ")"
   elseif tag == "flatmap"   then return self.src:describe(indent) .. "\n" .. pad .. "  → flatmap(" .. name .. ")"
   elseif tag == "enumerate" then return self.src:describe(indent) .. "\n" .. pad .. "  → enumerate(" .. (self.start or 1) .. ")"
   elseif tag == "dedup"     then return self.src:describe(indent) .. "\n" .. pad .. "  → dedup()"
   elseif tag == "window"    then return self.src:describe(indent) .. "\n" .. pad .. "  → window(" .. self.n .. ")"
   elseif tag == "tap"       then return self.src:describe(indent) .. "\n" .. pad .. "  → tap(" .. name .. ")"

   elseif tag == "chain" then
      return pad .. "chain(\n" .. self.left:describe(indent+1) .. ",\n"
             .. self.right:describe(indent+1) .. "\n" .. pad .. ")"
   elseif tag == "zip" then
      return pad .. "zip(\n" .. self.left:describe(indent+1) .. ",\n"
             .. self.right:describe(indent+1) .. "\n" .. pad .. ")"
   end
   return pad .. tag .. "(?)"
end

P.__tostring = P.describe

function P:depth()
   if self.src   then return 1 + self.src:depth() end
   if self.left  then return 1 + math.max(self.left:depth(), self.right:depth()) end
   return 1
end

function P:node_count()
   local n = 1
   if self.src   then n = n + self.src:node_count() end
   if self.left  then n = n + self.left:node_count() + self.right:node_count() end
   return n
end

-- ═══════════════════════════════════════════════════════════
--  COMPILER — Quote walks the tree, emits a flat loop
-- ═══════════════════════════════════════════════════════════
--
-- emit_loop(q, fresh, p, body_fn)
--   q        : Quote builder
--   fresh    : generates unique variable names
--   p        : param node
--   body_fn  : function(q, val_var) — emits code for each value
--
-- At compile time, we recurse down the param tree.
-- Each node wraps its logic around the body.
-- Range emits a for-loop. Filter wraps body in if.
-- Map wraps body in a local. Chain emits two loops.
--
-- The generated code has no recursion, no dispatch, no state tables.

local emit_loop

emit_loop = function(q, fresh, p, body_fn)
   local tag = p.tag

   if tag == "range" then
      local i = fresh("i")
      local lo = q:val(p.lo, "lo")
      local hi = q:val(p.hi, "hi")
      if p.step == 1 then
         q("for %s = %s, %s do", i, lo, hi)
      else
         local st = q:val(p.step, "step")
         q("for %s = %s, %s, %s do", i, lo, hi, st)
      end
      body_fn(q, i)
      q("end")

   elseif tag == "array" then
      local _data = q:val(p.data, "data")
      local i = fresh("i")
      q("for %s = 1, #%s do", i, _data)
      local v = fresh("v")
      q("local %s = %s[%s]", v, _data, i)
      body_fn(q, v)
      q("end")

   elseif tag == "chars" then
      local _str = q:val(p.str, "str")
      local _sub = q:val(string.sub, "sub")
      local i = fresh("i")
      q("for %s = 1, #%s do", i, _str)
      local ch = fresh("ch")
      q("local %s = %s(%s, %s, %s)", ch, _sub, _str, i, i)
      body_fn(q, ch)
      q("end")

   elseif tag == "once" then
      local _val = q:val(p.val, "once_val")
      q("do")
      body_fn(q, _val)
      q("end")

   elseif tag == "rep" then
      local _val = q:val(p.val, "rep_val")
      local _n = q:val(p.n, "rep_n")
      local i = fresh("i")
      q("for %s = 1, %s do", i, _n)
      body_fn(q, _val)
      q("end")

   elseif tag == "empty" then
      -- emit nothing

   elseif tag == "map" then
      local _fn = q:val(p.fn, "mapf")
      local mv = fresh("mapped")
      emit_loop(q, fresh, p.src, function(q, val)
         q("local %s = %s(%s)", mv, _fn, val)
         body_fn(q, mv)
      end)

   elseif tag == "filter" then
      local _fn = q:val(p.fn, "filt")
      emit_loop(q, fresh, p.src, function(q, val)
         q("if %s(%s) then", _fn, val)
         body_fn(q, val)
         q("end")
      end)

   elseif tag == "take" then
      local c = fresh("taken")
      local _n = q:val(p.n, "take_n")
      q("local %s = 0", c)
      emit_loop(q, fresh, p.src, function(q, val)
         q("%s = %s + 1", c, c)
         body_fn(q, val)
         q("if %s >= %s then goto _done end", c, _n)
      end)

   elseif tag == "skip" then
      local c = fresh("skipped")
      local _n = q:val(p.n, "skip_n")
      q("local %s = 0", c)
      emit_loop(q, fresh, p.src, function(q, val)
         q("%s = %s + 1", c, c)
         q("if %s > %s then", c, _n)
         body_fn(q, val)
         q("end")
      end)

   elseif tag == "take_while" then
      local _fn = q:val(p.fn, "tw_fn")
      emit_loop(q, fresh, p.src, function(q, val)
         q("if not %s(%s) then goto _done end", _fn, val)
         body_fn(q, val)
      end)

   elseif tag == "skip_while" then
      local _fn = q:val(p.fn, "sw_fn")
      local flag = fresh("sw_active")
      q("local %s = true", flag)
      emit_loop(q, fresh, p.src, function(q, val)
         q("if %s then", flag)
         q("  if not %s(%s) then %s = false end", _fn, val, flag)
         q("end")
         q("if not %s then", flag)
         body_fn(q, val)
         q("end")
      end)

   elseif tag == "chain" then
      emit_loop(q, fresh, p.left, body_fn)
      emit_loop(q, fresh, p.right, body_fn)

   elseif tag == "zip" then
      -- zip needs coroutine-style interleaving; fall back to interpreter
      local _step = q:val(step, "step")
      local _init = q:val(init_state, "init_state")
      local _p = q:val(p, "zip_p")
      local s = fresh("zip_s")
      local v = fresh("zip_v")
      q("local %s = %s(%s)", s, _init, _p)
      q("local %s", v)
      q("%s, %s = %s(%s, %s)", s, v, _step, _p, s)
      q("while %s ~= nil do", s)
      body_fn(q, v)
      q("%s, %s = %s(%s, %s)", s, v, _step, _p, s)
      q("end")

   elseif tag == "enumerate" then
      local idx = fresh("idx")
      local _start = q:val((p.start or 1) - 1, "enum_start")
      q("local %s = %s", idx, _start)
      emit_loop(q, fresh, p.src, function(q, val)
         q("%s = %s + 1", idx, idx)
         local pair = fresh("enum_pair")
         q("local %s = { %s, %s }", pair, idx, val)
         body_fn(q, pair)
      end)

   elseif tag == "scan" then
      local _fn = q:val(p.fn, "scanf")
      local acc = fresh("acc")
      local _init = q:val(p.init, "scan_init")
      q("local %s = %s", acc, _init)
      emit_loop(q, fresh, p.src, function(q, val)
         q("%s = %s(%s, %s)", acc, _fn, acc, val)
         body_fn(q, acc)
      end)

   elseif tag == "flatmap" then
      local _fn = q:val(p.fn, "fmapf")
      local _step = q:val(step, "step")
      local _init = q:val(init_state, "init_state")
      emit_loop(q, fresh, p.src, function(q, val)
         local ip = fresh("inner_p")
         local is = fresh("inner_s")
         local iv = fresh("inner_v")
         q("local %s = %s(%s)", ip, _fn, val)
         q("local %s = %s(%s)", is, _init, ip)
         q("local %s", iv)
         q("%s, %s = %s(%s, %s)", is, iv, _step, ip, is)
         q("while %s ~= nil do", is)
         body_fn(q, iv)
         q("%s, %s = %s(%s, %s)", is, iv, _step, ip, is)
         q("end")
      end)

   elseif tag == "dedup" then
      local sentinel = q:val({}, "dedup_sentinel")
      local prev = fresh("prev")
      q("local %s = %s", prev, sentinel)
      emit_loop(q, fresh, p.src, function(q, val)
         q("if %s ~= %s then", val, prev)
         q("  %s = %s", prev, val)
         body_fn(q, val)
         q("end")
      end)

   elseif tag == "tap" then
      local _fn = q:val(p.fn, "tapf")
      emit_loop(q, fresh, p.src, function(q, val)
         q("%s(%s)", _fn, val)
         body_fn(q, val)
      end)

   elseif tag == "window" then
      -- window needs buffering; fall back to interpreter for inner
      local _step = q:val(step, "step")
      local _init = q:val(init_state, "init_state")
      local _p = q:val(p, "win_p")
      local s = fresh("win_s")
      local v = fresh("win_v")
      q("local %s = %s(%s)", s, _init, _p)
      q("local %s", v)
      q("%s, %s = %s(%s, %s)", s, v, _step, _p, s)
      q("while %s ~= nil do", s)
      body_fn(q, v)
      q("%s, %s = %s(%s, %s)", s, v, _step, _p, s)
      q("end")

   else
      error("iterkit compile: unknown tag '" .. tostring(tag) .. "'")
   end
end

-- ═══════════════════════════════════════════════════════════
--  COMPILED PIPELINE — wraps a generated function
-- ═══════════════════════════════════════════════════════════

local C = {}; C.__index = C
local reducer_builders = {}

-- Build the scaffolding around emit_loop for a specific reducer shape
local function make_compiler(param, reducer_name, build_fn)
   local q = Quote()
   local slot = 0
   local function fresh(hint)
      slot = slot + 1
      return q:sym(hint .. "_" .. slot)
   end

   build_fn(q, fresh, param)
   local fn, src = q:compile("=(iterkit." .. reducer_name .. ")")
   return fn, src
end

function P:compile()
   local compiled = setmetatable({ param = self, _cache = {} }, C)
   return compiled
end

C.__tostring = function(self)
   return "<compiled " .. self.param:describe() .. ">"
end

function C:_get(name, build_fn)
   if not self._cache[name] then
      local fn, src = make_compiler(self.param, name, build_fn)
      self._cache[name] = { fn = fn, src = src }
   end
   return self._cache[name]
end

reducer_builders.collect = function(q, fresh, p)
   q("return function()")
   q("local _out, _n = {}, 0")
   emit_loop(q, fresh, p, function(q, val)
      q("_n = _n + 1")
      q("_out[_n] = %s", val)
   end)
   q("::_done::")
   q("return _out")
   q("end")
end

function C:collect()
   local entry = self:_get("collect", reducer_builders.collect)
   return entry.fn()
end

reducer_builders.fold = function(q, fresh, p)
   q("return function(_fold_fn, _init)")
   q("local _acc = _init")
   emit_loop(q, fresh, p, function(q, val)
      q("_acc = _fold_fn(_acc, %s)", val)
   end)
   q("::_done::")
   q("return _acc")
   q("end")
end

function C:fold(fn, init)
   local entry = self:_get("fold", reducer_builders.fold)
   return entry.fn(fn, init)
end

reducer_builders.each = function(q, fresh, p)
   q("return function(_each_fn)")
   emit_loop(q, fresh, p, function(q, val)
      q("_each_fn(%s)", val)
   end)
   q("::_done::")
   q("end")
end

function C:each(fn)
   local entry = self:_get("each", reducer_builders.each)
   entry.fn(fn)
end

reducer_builders.sum = function(q, fresh, p)
   q("return function()")
   q("local _acc = 0")
   emit_loop(q, fresh, p, function(q, val)
      q("_acc = _acc + %s", val)
   end)
   q("::_done::")
   q("return _acc")
   q("end")
end

function C:sum()
   local entry = self:_get("sum", reducer_builders.sum)
   return entry.fn()
end

reducer_builders.count = function(q, fresh, p)
   q("return function()")
   q("local _n = 0")
   emit_loop(q, fresh, p, function(q, val)
      q("_n = _n + 1")
   end)
   q("::_done::")
   q("return _n")
   q("end")
end

function C:count()
   local entry = self:_get("count", reducer_builders.count)
   return entry.fn()
end

reducer_builders.min = function(q, fresh, p)
   q("return function()")
   q("local _min = nil")
   emit_loop(q, fresh, p, function(q, val)
      q("if _min == nil or %s < _min then _min = %s end", val, val)
   end)
   q("::_done::")
   q("return _min")
   q("end")
end

function C:min()
   local entry = self:_get("min", reducer_builders.min)
   return entry.fn()
end

reducer_builders.max = function(q, fresh, p)
   q("return function()")
   q("local _max = nil")
   emit_loop(q, fresh, p, function(q, val)
      q("if _max == nil or %s > _max then _max = %s end", val, val)
   end)
   q("::_done::")
   q("return _max")
   q("end")
end

function C:max()
   local entry = self:_get("max", reducer_builders.max)
   return entry.fn()
end

reducer_builders.first = function(q, fresh, p)
   q("return function()")
   q("local _first = nil")
   emit_loop(q, fresh, p, function(q, val)
      q("_first = %s", val)
      q("goto _done")
   end)
   q("::_done::")
   q("return _first")
   q("end")
end

function C:first()
   local entry = self:_get("first", reducer_builders.first)
   return entry.fn()
end

function C:join(sep)
   return table.concat(self:collect(), sep or ", ")
end

-- Access generated source for any reducer
function C:source(name)
   name = name or "collect"
   local build_fn = reducer_builders[name]
   if not build_fn then
      error("iterkit: unknown compiled reducer '" .. tostring(name) .. "'", 2)
   end
   local entry = self:_get(name, build_fn)
   return entry.src
end

-- ═══════════════════════════════════════════════════════════
--  BENCH HELPER
-- ═══════════════════════════════════════════════════════════

function it.bench(label, fn, n)
   n = n or 10000
   for _ = 1, math.min(n, 100) do fn() end
   collectgarbage("collect"); collectgarbage("stop")
   local t0 = os.clock()
   local r
   for _ = 1, n do r = fn() end
   local t1 = os.clock()
   collectgarbage("restart")
   local us = (t1 - t0) / n * 1e6
   io.write(string.format("  %-40s %8.1f μs/iter  (%d iters)\n", label, us, n))
   return r, us
end

-- ═══════════════════════════════════════════════════════════
--  MODULE
-- ═══════════════════════════════════════════════════════════

-- Export the interpreter primitives for advanced use
it.step = step
it.init_state = init_state

return it
