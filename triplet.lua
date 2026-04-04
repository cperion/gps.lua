--[[
  triplet.lua — iterator algebra microframework

  One primitive: (gen, param, ctrl)
  gen(param, ctrl) -> ctrl', value... | nil

  Every combinator: triplet in, triplet out.
  Closed algebra. Zero allocation in hot paths.
  LuaJIT traces through everything.
]]

local T = {}

-- ═══════════════════════════════════════════
-- CONSTRUCTORS: enter the space
-- ═══════════════════════════════════════════

--- lift a single value
function T.unit(x)
  return function(_, ctrl)
    if ctrl then return nil end
    return true, x
  end, nil, false
end

--- empty iterator
function T.empty()
  return function() return nil end, nil, nil
end

--- sequence from array table
function T.seq(t)
  return function(t, i)
    i = i + 1
    if i > #t then return nil end
    return i, t[i]
  end, t, 0
end

--- inclusive integer range
function T.range(a, b, step)
  step = step or 1
  return function(s, i)
    i = i + step
    if (step > 0 and i > s) or (step < 0 and i < s) then return nil end
    return i, i
  end, b, a - step
end

--- string as byte iterator
function T.bytes(str)
  return function(s, i)
    i = i + 1
    if i > #s then return nil end
    return i, s:byte(i)
  end, str, 0
end

--- string as character iterator
function T.chars(str)
  return function(s, i)
    i = i + 1
    if i > #s then return nil end
    return i, s:sub(i, i)
  end, str, 0
end

--- generate from a function: f(i) -> value | nil
function T.generate(f)
  return function(f, i)
    i = i + 1
    local v = f(i)
    if v == nil then return nil end
    return i, v
  end, f, 0
end

--- infinite repeat of a value
function T.rep(x)
  return function(_, c)
    return c + 1, x
  end, nil, 0
end

--- wrap a raw triplet (identity, but makes intent clear)
function T.wrap(g, p, c)
  return g, p, c
end

-- ═══════════════════════════════════════════
-- TRANSFORMERS: triplet -> triplet
-- ═══════════════════════════════════════════

--- transform each value
function T.map(f, g, p, c)
  return function(s, _)
    local nc, v = s.g(s.p, s.c)
    if nc == nil then return nil end
    s.c = nc
    return true, f(v)
  end, {g=g, p=p, c=c}, true
end

--- transform with index
function T.mapi(f, g, p, c)
  return function(s, i)
    local nc, v = s.g(s.p, s.c)
    if nc == nil then return nil end
    s.c = nc
    i = i + 1
    return i, f(i, v)
  end, {g=g, p=p, c=c}, 0
end

--- keep values matching predicate
function T.filter(pred, g, p, c)
  return function(s, _)
    while true do
      local nc, v = s.g(s.p, s.c)
      if nc == nil then return nil end
      s.c = nc
      if pred(v) then return true, v end
    end
  end, {g=g, p=p, c=c}, true
end

--- take first n values
function T.take(n, g, p, c)
  return function(s, i)
    if i >= n then return nil end
    local nc, v = s.g(s.p, s.c)
    if nc == nil then return nil end
    s.c = nc
    return i + 1, v
  end, {g=g, p=p, c=c}, 0
end

--- take while predicate holds
function T.take_while(pred, g, p, c)
  return function(s, _)
    local nc, v = s.g(s.p, s.c)
    if nc == nil then return nil end
    s.c = nc
    if not pred(v) then return nil end
    return true, v
  end, {g=g, p=p, c=c}, true
end

--- drop first n values
function T.drop(n, g, p, c)
  return function(s, ctrl)
    if not ctrl then
      for _ = 1, n do
        local nc = s.g(s.p, s.c)
        if nc == nil then return nil end
        s.c = nc
      end
    end
    local nc, v = s.g(s.p, s.c)
    if nc == nil then return nil end
    s.c = nc
    return true, v
  end, {g=g, p=p, c=c}, false
end

--- drop while predicate holds
function T.drop_while(pred, g, p, c)
  return function(s, ctrl)
    while true do
      local nc, v = s.g(s.p, s.c)
      if nc == nil then return nil end
      s.c = nc
      if ctrl or not pred(v) then
        return true, v
      end
    end
  end, {g=g, p=p, c=c, dropping=true}, false
end

--- running accumulator: yields each intermediate state
function T.scan(f, acc, g, p, c)
  return function(s, _)
    local nc, v = s.g(s.p, s.c)
    if nc == nil then return nil end
    s.c = nc
    s.acc = f(s.acc, v)
    return true, s.acc
  end, {g=g, p=p, c=c, acc=acc}, true
end

--- deduplicate consecutive equal values
function T.dedup(g, p, c)
  local sentinel = {}  -- unique ref
  return function(s, _)
    while true do
      local nc, v = s.g(s.p, s.c)
      if nc == nil then return nil end
      s.c = nc
      if v ~= s.prev then
        s.prev = v
        return true, v
      end
    end
  end, {g=g, p=p, c=c, prev=sentinel}, true
end

--- buffer values into chunks of size n
function T.chunk(n, g, p, c)
  return function(s, _)
    local buf = {}
    for i = 1, n do
      local nc, v = s.g(s.p, s.c)
      if nc == nil then
        if #buf > 0 then return true, buf end
        return nil
      end
      s.c = nc
      buf[i] = v
    end
    return true, buf
  end, {g=g, p=p, c=c}, true
end

--- sliding window of size n
function T.window(n, g, p, c)
  return function(s, ctrl)
    if not ctrl then
      -- fill initial window
      s.win = {}
      for i = 1, n do
        local nc, v = s.g(s.p, s.c)
        if nc == nil then return nil end
        s.c = nc
        s.win[i] = v
      end
      -- copy for output
      local out = {}
      for i = 1, n do out[i] = s.win[i] end
      return true, out
    end
    -- slide by one
    local nc, v = s.g(s.p, s.c)
    if nc == nil then return nil end
    s.c = nc
    -- shift window
    for i = 1, n - 1 do
      s.win[i] = s.win[i + 1]
    end
    s.win[n] = v
    local out = {}
    for i = 1, n do out[i] = s.win[i] end
    return true, out
  end, {g=g, p=p, c=c}, false
end

--- inject a side effect without changing the stream
function T.tap(f, g, p, c)
  return function(s, _)
    local nc, v = s.g(s.p, s.c)
    if nc == nil then return nil end
    s.c = nc
    f(v)
    return true, v
  end, {g=g, p=p, c=c}, true
end

--- enumerate: yields index, value as a pair table
function T.enumerate(g, p, c)
  return function(s, i)
    local nc, v = s.g(s.p, s.c)
    if nc == nil then return nil end
    s.c = nc
    i = i + 1
    return i, {i, v}
  end, {g=g, p=p, c=c}, 0
end

-- ═══════════════════════════════════════════
-- COMBINATORS: multiple triplets -> triplet
-- ═══════════════════════════════════════════

--- concatenate: drain first, then second
function T.concat(g1, p1, c1, g2, p2, c2)
  return function(s, _)
    if not s.second then
      local nc, v = s.g1(s.p1, s.c1)
      if nc ~= nil then
        s.c1 = nc
        return true, v
      end
      s.second = true
    end
    local nc, v = s.g2(s.p2, s.c2)
    if nc == nil then return nil end
    s.c2 = nc
    return true, v
  end, {g1=g1, p1=p1, c1=c1, g2=g2, p2=p2, c2=c2, second=false}, true
end

--- zip: two iterators in lockstep, yields pairs
function T.zip(g1, p1, c1, g2, p2, c2)
  return function(s, _)
    local nc1, v1 = s.g1(s.p1, s.c1)
    if nc1 == nil then return nil end
    local nc2, v2 = s.g2(s.p2, s.c2)
    if nc2 == nil then return nil end
    s.c1, s.c2 = nc1, nc2
    return true, v1, v2
  end, {g1=g1, p1=p1, c1=c1, g2=g2, p2=p2, c2=c2}, true
end

--- zip with combining function
function T.zip_with(f, g1, p1, c1, g2, p2, c2)
  return function(s, _)
    local nc1, v1 = s.g1(s.p1, s.c1)
    if nc1 == nil then return nil end
    local nc2, v2 = s.g2(s.p2, s.c2)
    if nc2 == nil then return nil end
    s.c1, s.c2 = nc1, nc2
    return true, f(v1, v2)
  end, {g1=g1, p1=p1, c1=c1, g2=g2, p2=p2, c2=c2}, true
end

--- interleave: alternate values from two iterators
function T.interleave(g1, p1, c1, g2, p2, c2)
  return function(s, _)
    local g, p
    if s.first then
      g, p = s.g1, "p1"
    else
      g, p = s.g2, "p2"
    end
    local nc, v = g(s[p], s[p == "p1" and "c1" or "c2"])
    if nc == nil then
      -- other side might still have data
      s.first = not s.first
      g = s.first and s.g1 or s.g2
      p = s.first and "p1" or "p2"
      nc, v = g(s[p], s[p == "p1" and "c1" or "c2"])
      if nc == nil then return nil end
    end
    s[p == "p1" and "c1" or "c2"] = nc
    s.first = not s.first
    return true, v
  end, {g1=g1, p1=p1, c1=c1, g2=g2, p2=p2, c2=c2, first=true}, true
end

-- ═══════════════════════════════════════════
-- FLATMAP / CHAIN: the monadic bind
-- value -> triplet, then flatten
-- ═══════════════════════════════════════════

--- flatmap: f(value) returns (g, p, c), results are flattened
function T.flatmap(f, g, p, c)
  return function(s, _)
    while true do
      -- drain current inner iterator
      if s.ig then
        local nc, v = s.ig(s.ip, s.ic)
        if nc ~= nil then
          s.ic = nc
          return true, v
        end
        s.ig = nil  -- inner exhausted
      end
      -- pull next from outer
      local nc, val = s.g(s.p, s.c)
      if nc == nil then return nil end
      s.c = nc
      -- expand into new inner
      s.ig, s.ip, s.ic = f(val)
    end
  end, {g=g, p=p, c=c, ig=nil, ip=nil, ic=nil}, true
end

-- ═══════════════════════════════════════════
-- PIPELINE: stack of triplets
-- ═══════════════════════════════════════════

--- pipe output of first as values transformed by second
--- second is a function: value -> value
function T.pipe(f, g, p, c)
  return T.map(f, g, p, c)
end

--- compose a sequence of transform functions over a base triplet
--- T.pipeline(g, p, c, f1, f2, f3, ...)
function T.pipeline(g, p, c, ...)
  local transforms = {...}
  for i = 1, #transforms do
    g, p, c = T.map(transforms[i], g, p, c)
  end
  return g, p, c
end

--- compose from a list of (value -> value) functions
function T.compose(...)
  local fns = {...}
  return function(x)
    for i = 1, #fns do
      x = fns[i](x)
    end
    return x
  end
end

--- stack: takes iterator-of-iterators, chains them sequentially
--- each yielded (g, p, c) is drained in order
function T.flatten(gg, gp, gc)
  return function(s, _)
    while true do
      -- drain current inner
      if s.ig then
        local nc, v = s.ig(s.ip, s.ic)
        if nc ~= nil then
          s.ic = nc
          return true, v
        end
        s.ig = nil
      end
      -- pull next iterator from the meta-iterator
      local nc, g, p, c = s.gg(s.gp, s.gc)
      if nc == nil then return nil end
      s.gc = nc
      s.ig, s.ip, s.ic = g, p, c
    end
  end, {gg=gg, gp=gp, gc=gc, ig=nil, ip=nil, ic=nil}, true
end

-- ═══════════════════════════════════════════
-- CONSUMERS: leave the space
-- ═══════════════════════════════════════════

--- fold to a single value
function T.fold(f, acc, g, p, c)
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then return acc end
    ctrl = nc
    acc = f(acc, v)
  end
end

--- fold but returns result as (g, p, c) — stays in the space
function T.foldT(f, acc, g, p, c)
  return T.unit(T.fold(f, acc, g, p, c))
end

--- collect into array table
function T.collect(g, p, c)
  local t = {}
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then return t end
    ctrl = nc
    t[#t + 1] = v
  end
end

--- run for side effects only
function T.each(f, g, p, c)
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then return end
    ctrl = nc
    f(v)
  end
end

--- first value or default
function T.first(g, p, c, default)
  local _, v = g(p, c)
  return v ~= nil and v or default
end

--- last value or default
function T.last(g, p, c, default)
  local result = default
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then return result end
    ctrl = nc
    result = v
  end
end

--- count elements
function T.count(g, p, c)
  local n = 0
  local ctrl = c
  while true do
    local nc = g(p, ctrl)
    if nc == nil then return n end
    ctrl = nc
    n = n + 1
  end
end

--- any value matches predicate?
function T.any(pred, g, p, c)
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then return false end
    ctrl = nc
    if pred(v) then return true end
  end
end

--- all values match predicate?
function T.all(pred, g, p, c)
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then return true end
    ctrl = nc
    if not pred(v) then return false end
  end
end

--- find first matching value
function T.find(pred, g, p, c)
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then return nil end
    ctrl = nc
    if pred(v) then return v end
  end
end

--- join string values
function T.join(sep, g, p, c)
  return table.concat(T.collect(g, p, c), sep)
end

-- ═══════════════════════════════════════════
-- RE-ENTRY: back into the space from tables
-- ═══════════════════════════════════════════

--- pairs iterator as triplet
function T.pairs(t)
  return next, t, nil
end

--- ipairs as triplet
function T.ipairs(t)
  return function(t, i)
    i = i + 1
    local v = t[i]
    if v == nil then return nil end
    return i, v
  end, t, 0
end

-- ═══════════════════════════════════════════
-- META: iterators of iterators
-- ═══════════════════════════════════════════

--- tee: split one iterator into n independent copies
--- returns array of triplets (each must be consumed at same rate)
function T.tee(n, g, p, c)
  local buffers = {}
  local state = {g=g, p=p, c=c}
  for i = 1, n do buffers[i] = {} end

  local function fetch(s, _)
    if #s.buf > 0 then
      return true, table.remove(s.buf, 1)
    end
    local nc, v = state.g(state.p, state.c)
    if nc == nil then return nil end
    state.c = nc
    -- push to all OTHER buffers
    for i = 1, n do
      if buffers[i] ~= s.buf then
        buffers[i][#buffers[i] + 1] = v
      end
    end
    return true, v
  end

  local iters = {}
  for i = 1, n do
    iters[i] = {fetch, {buf=buffers[i]}, true}
  end
  return iters
end

--- partition: split by predicate into two triplets
function T.partition(pred, g, p, c)
  local copies = T.tee(2, g, p, c)
  local g1, p1, c1 = copies[1][1], copies[1][2], copies[1][3]
  local g2, p2, c2 = copies[2][1], copies[2][2], copies[2][3]
  return
    T.filter(pred, g1, p1, c1),
    T.filter(function(v) return not pred(v) end, g2, p2, c2)
end

-- ═══════════════════════════════════════════
-- FLUENT WRAPPER: optional method chaining
-- (the raw functions are the real interface,
--  this is sugar for readability)
-- ═══════════════════════════════════════════

local Stream = {}
Stream.__index = Stream

function Stream:map(f)       return setmetatable({T.map(f, self[1], self[2], self[3])}, Stream) end
function Stream:filter(f)    return setmetatable({T.filter(f, self[1], self[2], self[3])}, Stream) end
function Stream:take(n)      return setmetatable({T.take(n, self[1], self[2], self[3])}, Stream) end
function Stream:drop(n)      return setmetatable({T.drop(n, self[1], self[2], self[3])}, Stream) end
function Stream:scan(f, acc) return setmetatable({T.scan(f, acc, self[1], self[2], self[3])}, Stream) end
function Stream:dedup()      return setmetatable({T.dedup(self[1], self[2], self[3])}, Stream) end
function Stream:chunk(n)     return setmetatable({T.chunk(n, self[1], self[2], self[3])}, Stream) end
function Stream:tap(f)       return setmetatable({T.tap(f, self[1], self[2], self[3])}, Stream) end
function Stream:enumerate()  return setmetatable({T.enumerate(self[1], self[2], self[3])}, Stream) end
function Stream:flatmap(f)   return setmetatable({T.flatmap(f, self[1], self[2], self[3])}, Stream) end
function Stream:take_while(f) return setmetatable({T.take_while(f, self[1], self[2], self[3])}, Stream) end

function Stream:fold(f, acc) return T.fold(f, acc, self[1], self[2], self[3]) end
function Stream:collect()    return T.collect(self[1], self[2], self[3]) end
function Stream:each(f)      return T.each(f, self[1], self[2], self[3]) end
function Stream:first(d)     return T.first(self[1], self[2], self[3], d) end
function Stream:last(d)      return T.last(self[1], self[2], self[3], d) end
function Stream:count()      return T.count(self[1], self[2], self[3]) end
function Stream:any(f)       return T.any(f, self[1], self[2], self[3]) end
function Stream:all(f)       return T.all(f, self[1], self[2], self[3]) end
function Stream:find(f)      return T.find(f, self[1], self[2], self[3]) end
function Stream:join(s)      return T.join(s, self[1], self[2], self[3]) end

--- unpack back to raw triplet
function Stream:unpack()     return self[1], self[2], self[3] end

--- make it work with for..in directly
function Stream:iter()       return self[1], self[2], self[3] end

function T.stream(g, p, c)
  return setmetatable({g, p, c}, Stream)
end

-- convenience constructors on stream
function T.S(t)              return T.stream(T.seq(t)) end
function T.R(a, b, step)     return T.stream(T.range(a, b, step)) end

return T
