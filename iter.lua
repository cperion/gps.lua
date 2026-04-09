-- iter.lua — gen, param, state
--
-- param is the program. state is the registers. step is the VM.
-- everything is data. nothing is hidden.
--
-- usage:
--   local iter = require("iter")
--   iter.range(10):filter(odd):map(sq):sum()
--   iter.from({3,1,4,1,5}):dedup():collect()
--   iter.range(4):flatmap(function(x) return iter.range(x) end):collect()
--
-- the triplet is always available:
--   local gen, param, state = iter.range(10):triplet()
--
-- introspection:
--   print(pipeline)              -- describe
--   pipeline:depth()             -- tree depth
--   pipeline:nodes()             -- node count
--   pipeline:rewrite(fn)         -- transform the tree
--
-- fork mid-iteration:
--   local gen, p, s = pipeline:triplet()
--   s = gen(p, s)  -- advance
--   local s2 = iter.clone(s)  -- fork
--
-- built-in rewrites:
--   pipeline:fuse()              -- fuse adjacent maps and filters

local iter = {}
local P = {}; P.__index = P

-- ─── step & init: the VM ─────────────────────────────────

local step, init

step = function(p, s)
   local t = p[1]  -- tag is p[1], always

   if t == 1 then -- range
      local i = s + p[4]
      if p[4] > 0 then
         if i > p[3] then return nil end
      else
         if i < p[3] then return nil end
      end
      return i, i

   elseif t == 2 then -- array
      local i = s + 1
      if i > p[3] then return nil end
      return i, p[2][i]

   elseif t == 3 then -- chars
      local i = s + 1
      if i > p[3] then return nil end
      return i, p[2]:sub(i, i)

   elseif t == 4 then -- once
      if s then return nil end
      return true, p[2]

   elseif t == 5 then -- rep
      if s >= p[3] then return nil end
      return s + 1, p[2]

   elseif t == 6 then -- empty
      return nil

   elseif t == 7 then -- map
      local ns, v = step(p[3], s)
      if ns == nil then return nil end
      return ns, p[2](v)

   elseif t == 8 then -- filter
      local ns, v = step(p[3], s)
      while ns ~= nil do
         if p[2](v) then return ns, v end
         ns, v = step(p[3], ns)
      end
      return nil

   elseif t == 9 then -- take
      if s[1] >= p[2] then return nil end
      local ns, v = step(p[3], s[2])
      if ns == nil then return nil end
      return { s[1] + 1, ns }, v

   elseif t == 10 then -- skip (state already advanced past n)
      return step(p[3], s)

   elseif t == 11 then -- take_while
      if s[1] then return nil end
      local ns, v = step(p[3], s[2])
      if ns == nil or not p[2](v) then return nil end
      return { false, ns }, v

   elseif t == 12 then -- skip_while
      local ns, v = step(p[3], s[2])
      while ns ~= nil do
         if not s[1] then return { false, ns }, v end
         if not p[2](v) then return { false, ns }, v end
         ns, v = step(p[3], ns)
      end
      return nil

   elseif t == 13 then -- chain
      if s[1] == 1 then
         local ns, v = step(p[2], s[2])
         if ns ~= nil then return { 1, ns, s[3] }, v end
      end
      local ns, v = step(p[3], s[3])
      if ns == nil then return nil end
      return { 2, s[2], ns }, v

   elseif t == 14 then -- zip
      local sa, va = step(p[2], s[1])
      if sa == nil then return nil end
      local sb, vb = step(p[3], s[2])
      if sb == nil then return nil end
      return { sa, sb }, { va, vb }

   elseif t == 15 then -- enumerate
      local ns, v = step(p[3], s[2])
      if ns == nil then return nil end
      return { s[1] + 1, ns }, s[1] + 1, v

   elseif t == 16 then -- scan
      local ns, v = step(p[4], s[2])
      if ns == nil then return nil end
      local acc = p[2](s[1], v)
      return { acc, ns }, acc

   elseif t == 17 then -- flatmap
      while true do
         if s[2] then
            local ns, v = step(s[2], s[3])
            if ns ~= nil then return { s[1], s[2], ns }, v end
         end
         local ns, v = step(p[3], s[1])
         if ns == nil then return nil end
         local ip = p[2](v)
         s = { ns, ip, init(ip) }
      end

   elseif t == 18 then -- dedup
      local ns, v = step(p[2], s[2])
      while ns ~= nil do
         if not s[3] or v ~= s[1] then return { v, ns, true }, v end
         ns, v = step(p[2], ns)
      end
      return nil

   elseif t == 19 then -- tap
      local ns, v = step(p[3], s)
      if ns == nil then return nil end
      p[2](v)
      return ns, v

   elseif t == 20 then -- window
      local buf, ss, first = s[1], s[2], s[3]
      if first then
         local out = {}
         for i = 1, #buf do out[i] = buf[i] end
         return { buf, ss, false }, out
      end
      local ns, v = step(p[3], ss)
      if ns == nil then return nil end
      local nb = {}
      for i = 2, #buf do nb[i-1] = buf[i] end
      nb[#buf] = v
      local out = {}
      for i = 1, #nb do out[i] = nb[i] end
      return { nb, ns, false }, out

   elseif t == 21 then -- group_by
      if s[5] or not s[4] then return nil end
      local group = { s[2] }
      local key = s[3]
      local ss = s[1]
      while true do
         local ns, nv = step(p[3], ss)
         if ns == nil then
            return { ss, nil, nil, false, true }, { key = key, items = group }
         end
         ss = ns
         local nk = p[2](nv)
         if nk ~= key then
            return { ss, nv, nk, true, false }, { key = key, items = group }
         end
         group[#group + 1] = nv
      end

   elseif t == 22 then -- unique
      local ns, v = step(p[2], s[2])
      while ns ~= nil do
         if not s[1][v] then
            s[1][v] = true
            return { s[1], ns }, v
         end
         ns, v = step(p[2], ns)
      end
      return nil

   elseif t == 23 then -- intersperse
      -- s = { inner_state, phase, buffered }
      -- phase 0: advance inner, yield element
      -- phase 1: advance inner, if nil→done, else buffer it, yield sep
      -- phase 2: yield buffered, go to phase 1
      local phase = s[2]
      if phase == 0 then
         local ns, v = step(p[3], s[1])
         if ns == nil then return nil end
         return { ns, 1, nil }, v
      elseif phase == 1 then
         local ns, v = step(p[3], s[1])
         if ns == nil then return nil end
         return { ns, 2, v }, p[2]
      else -- phase 2
         return { s[1], 1, nil }, s[3]
      end

   elseif t == 24 then -- cycle
      local ns, v = step(p[2], s)
      if ns ~= nil then return ns, v end
      local s0 = init(p[2])
      ns, v = step(p[2], s0)
      if ns == nil then return nil end
      return ns, v
   end
end

init = function(p)
   local t = p[1]
   if     t == 1  then return p[2] - p[4]           -- range: lo - step
   elseif t == 2  then return 0                      -- array
   elseif t == 3  then return 0                      -- chars
   elseif t == 4  then return false                   -- once
   elseif t == 5  then return 0                      -- rep
   elseif t == 6  then return nil                    -- empty
   elseif t == 7  then return init(p[3])             -- map
   elseif t == 8  then return init(p[3])             -- filter
   elseif t == 9  then return { 0, init(p[3]) }     -- take
   elseif t == 10 then                               -- skip
      local ss = init(p[3])
      for _ = 1, p[2] do
         ss = step(p[3], ss)
         if ss == nil then return nil end
      end
      return ss
   elseif t == 11 then return { false, init(p[3]) }  -- take_while
   elseif t == 12 then return { true,  init(p[3]) }  -- skip_while
   elseif t == 13 then return { 1, init(p[2]), init(p[3]) }  -- chain
   elseif t == 14 then return { init(p[2]), init(p[3]) }     -- zip
   elseif t == 15 then return { (p[2] or 1) - 1, init(p[3]) } -- enumerate
   elseif t == 16 then return { p[3], init(p[4]) }   -- scan
   elseif t == 17 then return { init(p[3]), false, nil }  -- flatmap
   elseif t == 18 then return { nil, init(p[2]), false }  -- dedup
   elseif t == 19 then return init(p[3])             -- tap
   elseif t == 20 then                               -- window
      local ss = init(p[3])
      local buf = {}
      for i = 1, p[2] do
         local ns, v = step(p[3], ss)
         if ns == nil then return nil end
         ss = ns; buf[i] = v
      end
      return { buf, ss, true }
   elseif t == 21 then                               -- group_by
      local ss = init(p[3])
      local ns, v = step(p[3], ss)
      if ns == nil then return { nil, nil, nil, false, true } end
      return { ns, v, p[2](v), true, false }
   elseif t == 22 then return { {}, init(p[2]) }     -- unique
   elseif t == 23 then return { init(p[3]), 0, nil }   -- intersperse
   elseif t == 24 then return init(p[2])              -- cycle
   end
end

-- ─── tag constants ───────────────────────────────────────

local T = {
   RANGE=1, ARRAY=2, CHARS=3, ONCE=4, REP=5, EMPTY=6,
   MAP=7, FILTER=8, TAKE=9, SKIP=10, TAKE_WHILE=11, SKIP_WHILE=12,
   CHAIN=13, ZIP=14, ENUMERATE=15, SCAN=16, FLATMAP=17, DEDUP=18,
   TAP=19, WINDOW=20, GROUP_BY=21, UNIQUE=22, INTERSPERSE=23, CYCLE=24,
}
iter.T = T

local TNAME = {}
for k, v in pairs(T) do TNAME[v] = k:lower() end

-- ─── param builders ──────────────────────────────────────

local function node(arr)
   return setmetatable(arr, P)
end

function iter.range(a, b, s)
   if b == nil then a, b = 1, a end
   return node { T.RANGE, a, b, s or 1 }
end

function iter.from(t)
   return node { T.ARRAY, t, #t }
end

function iter.chars(s)
   return node { T.CHARS, s, #s }
end

function iter.once(v)
   return node { T.ONCE, v }
end

function iter.rep(v, n)
   return node { T.REP, v, n }
end

function iter.empty()
   return node { T.EMPTY }
end

-- ─── combinators ─────────────────────────────────────────

function P:map(fn)          return node { T.MAP, fn, self } end
function P:filter(fn)       return node { T.FILTER, fn, self } end
function P:take(n)          return node { T.TAKE, n, self } end
function P:skip(n)          return node { T.SKIP, n, self } end
function P:take_while(fn)   return node { T.TAKE_WHILE, fn, self } end
function P:skip_while(fn)   return node { T.SKIP_WHILE, fn, self } end
function P:chain(other)     return node { T.CHAIN, self, other } end
function P:zip(other)       return node { T.ZIP, self, other } end
function P:enumerate(start) return node { T.ENUMERATE, start or 1, self } end
function P:scan(fn, seed)   return node { T.SCAN, fn, seed, self } end
function P:flatmap(fn)      return node { T.FLATMAP, fn, self } end
function P:dedup()          return node { T.DEDUP, self } end
function P:tap(fn)          return node { T.TAP, fn, self } end
function P:window(n)        return node { T.WINDOW, n, self } end
function P:group_by(fn)     return node { T.GROUP_BY, fn, self } end
function P:unique()         return node { T.UNIQUE, self } end
function P:intersperse(sep) return node { T.INTERSPERSE, sep, self } end
function P:cycle()          return node { T.CYCLE, self } end

-- ─── triplet ─────────────────────────────────────────────

function P:triplet() return step, self, init(self) end

-- ─── reducers ────────────────────────────────────────────

function P:collect()
   local out, n, s, v = {}, 0, init(self), nil
   s, v = step(self, s)
   while s ~= nil do n = n+1; out[n] = v; s, v = step(self, s) end
   return out
end

function P:fold(fn, acc)
   local s, v = init(self), nil
   s, v = step(self, s)
   while s ~= nil do acc = fn(acc, v); s, v = step(self, s) end
   return acc
end

function P:each(fn)
   local s, v = init(self), nil
   s, v = step(self, s)
   while s ~= nil do fn(v); s, v = step(self, s) end
end

function P:sum()   return self:fold(function(a, b) return a + b end, 0) end
function P:count() return self:fold(function(a, _) return a + 1 end, 0) end
function P:join(sep) return table.concat(self:collect(), sep or ", ") end

function P:min()
   return self:fold(function(a, b) return a == nil and b or (b < a and b or a) end, nil)
end
function P:max()
   return self:fold(function(a, b) return a == nil and b or (b > a and b or a) end, nil)
end

function P:first()
   local _, v = step(self, init(self))
   return v
end

function P:last()
   local r, s, v = nil, init(self), nil
   s, v = step(self, s)
   while s ~= nil do r = v; s, v = step(self, s) end
   return r
end

function P:any(fn)
   local s, v = init(self), nil
   s, v = step(self, s)
   while s ~= nil do if fn(v) then return true end; s, v = step(self, s) end
   return false
end

function P:all(fn)
   local s, v = init(self), nil
   s, v = step(self, s)
   while s ~= nil do if not fn(v) then return false end; s, v = step(self, s) end
   return true
end

function P:nth(n) return self:skip(n-1):first() end
function P:contains(val) return self:any(function(v) return v == val end) end

function P:partition(fn)
   local y, n = {}, {}
   self:each(function(v) if fn(v) then y[#y+1]=v else n[#n+1]=v end end)
   return y, n
end

function P:to_map(kf)
   local out = {}
   self:each(function(v) out[kf(v)] = v end)
   return out
end

-- ─── introspection ───────────────────────────────────────

-- child access by structure
local function get_children(p)
   local t = p[1]
   if t == T.CHAIN or t == T.ZIP            then return { p[2], p[3] }     end
   if t == T.DEDUP or t == T.UNIQUE or t == T.CYCLE then return { p[2] } end
   if t == T.SCAN                           then return { p[4] }           end
   if t >= 7 and t <= 12 then return { p[3] } end  -- map..skip_while
   if t == T.ENUMERATE or t == T.FLATMAP or t == T.TAP
      or t == T.WINDOW or t == T.GROUP_BY or t == T.INTERSPERSE then
      return { p[3] }
   end
   return {}
end

function P:depth()
   local kids = get_children(self)
   if #kids == 0 then return 1 end
   local d = 0
   for i = 1, #kids do
      local kd = kids[i]:depth()
      if kd > d then d = kd end
   end
   return 1 + d
end

function P:nodes()
   local n = 1
   for _, k in ipairs(get_children(self)) do n = n + k:nodes() end
   return n
end

local function desc(p, indent)
   indent = indent or 0
   local pad = string.rep("  ", indent)
   local t = p[1]

   if t == T.RANGE then
      local s = p[4] ~= 1 and (", " .. p[4]) or ""
      return pad .. "range(" .. p[2] .. ", " .. p[3] .. s .. ")"
   elseif t == T.ARRAY   then return pad .. "from[" .. p[3] .. "]"
   elseif t == T.CHARS   then return pad .. 'chars("' .. p[2] .. '")'
   elseif t == T.ONCE    then return pad .. "once(" .. tostring(p[2]) .. ")"
   elseif t == T.REP     then return pad .. "rep(" .. tostring(p[2]) .. ", " .. p[3] .. ")"
   elseif t == T.EMPTY   then return pad .. "empty()"

   elseif t == T.MAP        then return desc(p[3], indent) .. "\n" .. pad .. "  → map"
   elseif t == T.FILTER     then return desc(p[3], indent) .. "\n" .. pad .. "  → filter"
   elseif t == T.TAKE       then return desc(p[3], indent) .. "\n" .. pad .. "  → take(" .. p[2] .. ")"
   elseif t == T.SKIP       then return desc(p[3], indent) .. "\n" .. pad .. "  → skip(" .. p[2] .. ")"
   elseif t == T.TAKE_WHILE then return desc(p[3], indent) .. "\n" .. pad .. "  → take_while"
   elseif t == T.SKIP_WHILE then return desc(p[3], indent) .. "\n" .. pad .. "  → skip_while"
   elseif t == T.SCAN       then return desc(p[4], indent) .. "\n" .. pad .. "  → scan(_, " .. tostring(p[3]) .. ")"
   elseif t == T.ENUMERATE  then return desc(p[3], indent) .. "\n" .. pad .. "  → enumerate(" .. p[2] .. ")"
   elseif t == T.FLATMAP    then return desc(p[3], indent) .. "\n" .. pad .. "  → flatmap"
   elseif t == T.DEDUP      then return desc(p[2], indent) .. "\n" .. pad .. "  → dedup"
   elseif t == T.TAP        then return desc(p[3], indent) .. "\n" .. pad .. "  → tap"
   elseif t == T.WINDOW     then return desc(p[3], indent) .. "\n" .. pad .. "  → window(" .. p[2] .. ")"
   elseif t == T.GROUP_BY   then return desc(p[3], indent) .. "\n" .. pad .. "  → group_by"
   elseif t == T.UNIQUE     then return desc(p[2], indent) .. "\n" .. pad .. "  → unique"
   elseif t == T.INTERSPERSE then return desc(p[3], indent) .. "\n" .. pad .. "  → intersperse(" .. tostring(p[2]) .. ")"
   elseif t == T.CYCLE      then return desc(p[2], indent) .. "\n" .. pad .. "  → cycle"

   elseif t == T.CHAIN then
      return pad .. "chain(\n" .. desc(p[2], indent+1) .. ",\n" .. desc(p[3], indent+1) .. "\n" .. pad .. ")"
   elseif t == T.ZIP then
      return pad .. "zip(\n" .. desc(p[2], indent+1) .. ",\n" .. desc(p[3], indent+1) .. "\n" .. pad .. ")"
   end
   return pad .. (TNAME[t] or "?") .. "(?)"
end

function P:describe() return desc(self) end
P.__tostring = P.describe

-- ─── tree rewriting ──────────────────────────────────────

function P:rewrite(fn)
   local kids = get_children(self)
   if #kids == 0 then return fn(self) or self end

   local new_kids, changed = {}, false
   for i, k in ipairs(kids) do
      new_kids[i] = k:rewrite(fn)
      if new_kids[i] ~= k then changed = true end
   end

   local current = self
   if changed then
      local t = self[1]
      if t == T.CHAIN or t == T.ZIP then
         current = node { t, new_kids[1], new_kids[2] }
      elseif t == T.DEDUP or t == T.UNIQUE or t == T.CYCLE then
         current = node { t, new_kids[1] }
      elseif t == T.SCAN then
         current = node { t, self[2], self[3], new_kids[1] }
      else
         current = node { t, self[2], new_kids[1] }
      end
   end

   return fn(current) or current
end

-- ─── built-in rewrites ──────────────────────────────────

function P:fuse()
   return self:rewrite(function(n)
      if n[1] == T.MAP and n[3][1] == T.MAP then
         local f, g = n[3][2], n[2]
         return node { T.MAP, function(x) return g(f(x)) end, n[3][3] }
      end
      if n[1] == T.FILTER and n[3][1] == T.FILTER then
         local p, q = n[3][2], n[2]
         return node { T.FILTER, function(x) return p(x) and q(x) end, n[3][3] }
      end
      if n[1] == T.TAKE and n[3][1] == T.TAKE then
         return node { T.TAKE, math.min(n[2], n[3][2]), n[3][3] }
      end
      if n[1] == T.SKIP and n[3][1] == T.SKIP then
         return node { T.SKIP, n[2] + n[3][2], n[3][3] }
      end
   end)
end

-- ─── fork ────────────────────────────────────────────────

function iter.clone(state)
   if type(state) ~= "table" then return state end
   local c = {}
   for k, v in pairs(state) do c[k] = iter.clone(v) end
   return c
end

-- ─── module ──────────────────────────────────────────────

iter.step = step
iter.init = init
iter.node = node
iter.P = P

return iter
