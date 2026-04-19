--[[
  triplet.lua — iterator algebra over (gen, param, ctrl)

  Design:
    1. generic hot kernel: hoisted module-scope generators + packed array state
    2. targeted representation-aware fast paths for common seq-backed cases
    3. convenience helpers that may allocate by construction

  The important lesson from benchmarking: one uniform generic path is not
  always fastest under LuaJIT. For shallow common cases like seq+seq zip, an
  explicit specialization can beat the generic packed-state machine while still
  keeping the overall library disciplined.

  Helpers such as `chars`, `chunk`, `window`, `enumerate`, and stream sugar are
  still useful, but they should not be confused with the minimal hot-kernel
  story.
]]

local T = {}

local setmetatable = setmetatable
local table_concat = table.concat

local ACTIVE = 1
local DEDUP_SENTINEL = {}

-- ═══════════════════════════════════════════
-- CONSTRUCTORS: enter the space
-- ═══════════════════════════════════════════

local function unit_gen(x, emitted)
  if emitted ~= 0 then
    return nil
  end
  return 1, x
end

function T.unit(x)
  return unit_gen, x, 0
end

local function empty_gen()
  return nil
end

function T.empty()
  return empty_gen, nil, nil
end

local function seq_gen(t, i)
  i = i + 1
  if i > #t then
    return nil
  end
  return i, t[i]
end

function T.seq(t)
  return seq_gen, t, 0
end

local function is_fresh_seq(g, c)
  return g == seq_gen and c == 0
end

local RANGE_STOP = 1
local RANGE_STEP = 2

local function range_gen(s, i)
  local step = s[RANGE_STEP]
  i = i + step
  local stop = s[RANGE_STOP]
  if (step > 0 and i > stop) or (step < 0 and i < stop) then
    return nil
  end
  return i, i
end

function T.range(a, b, step)
  step = step or 1
  return range_gen, { b, step }, a - step
end

local function bytes_gen(str, i)
  i = i + 1
  if i > #str then
    return nil
  end
  return i, str:byte(i)
end

function T.bytes(str)
  return bytes_gen, str, 0
end

local function chars_gen(str, i)
  i = i + 1
  if i > #str then
    return nil
  end
  return i, str:sub(i, i)
end

function T.chars(str)
  return chars_gen, str, 0
end

local function generate_gen(f, i)
  i = i + 1
  local v = f(i)
  if v == nil then
    return nil
  end
  return i, v
end

function T.generate(f)
  return generate_gen, f, 0
end

local function rep_gen(x, c)
  return c + 1, x
end

function T.rep(x)
  return rep_gen, x, 0
end

function T.wrap(g, p, c)
  return g, p, c
end

-- ═══════════════════════════════════════════
-- TRANSFORMERS: triplet -> triplet
-- ═══════════════════════════════════════════

local MAP_F = 1
local MAP_G = 2
local MAP_P = 3
local MAP_C = 4

local function map_gen(s, _)
  local nc, v = s[MAP_G](s[MAP_P], s[MAP_C])
  if nc == nil then
    return nil
  end
  s[MAP_C] = nc
  return ACTIVE, s[MAP_F](v)
end

function T.map(f, g, p, c)
  return map_gen, { f, g, p, c }, 0
end

local MAPI_F = 1
local MAPI_G = 2
local MAPI_P = 3
local MAPI_C = 4

local function mapi_gen(s, i)
  local nc, v = s[MAPI_G](s[MAPI_P], s[MAPI_C])
  if nc == nil then
    return nil
  end
  s[MAPI_C] = nc
  i = i + 1
  return i, s[MAPI_F](i, v)
end

function T.mapi(f, g, p, c)
  return mapi_gen, { f, g, p, c }, 0
end

local FILTER_PRED = 1
local FILTER_G = 2
local FILTER_P = 3
local FILTER_C = 4

local function filter_gen(s, _)
  while true do
    local nc, v = s[FILTER_G](s[FILTER_P], s[FILTER_C])
    if nc == nil then
      return nil
    end
    s[FILTER_C] = nc
    if s[FILTER_PRED](v) then
      return ACTIVE, v
    end
  end
end

function T.filter(pred, g, p, c)
  return filter_gen, { pred, g, p, c }, 0
end

local FILTER_NOT_PRED = 1
local FILTER_NOT_G = 2
local FILTER_NOT_P = 3
local FILTER_NOT_C = 4

local function filter_not_gen(s, _)
  while true do
    local nc, v = s[FILTER_NOT_G](s[FILTER_NOT_P], s[FILTER_NOT_C])
    if nc == nil then
      return nil
    end
    s[FILTER_NOT_C] = nc
    if not s[FILTER_NOT_PRED](v) then
      return ACTIVE, v
    end
  end
end

local function filter_not(pred, g, p, c)
  return filter_not_gen, { pred, g, p, c }, 0
end

local TAKE_N = 1
local TAKE_G = 2
local TAKE_P = 3
local TAKE_C = 4

local function take_gen(s, i)
  if i >= s[TAKE_N] then
    return nil
  end
  local nc, v = s[TAKE_G](s[TAKE_P], s[TAKE_C])
  if nc == nil then
    return nil
  end
  s[TAKE_C] = nc
  return i + 1, v
end

function T.take(n, g, p, c)
  return take_gen, { n, g, p, c }, 0
end

local TW_PRED = 1
local TW_G = 2
local TW_P = 3
local TW_C = 4

local function take_while_gen(s, _)
  local nc, v = s[TW_G](s[TW_P], s[TW_C])
  if nc == nil then
    return nil
  end
  s[TW_C] = nc
  if not s[TW_PRED](v) then
    return nil
  end
  return ACTIVE, v
end

function T.take_while(pred, g, p, c)
  return take_while_gen, { pred, g, p, c }, 0
end

local DROP_N = 1
local DROP_G = 2
local DROP_P = 3
local DROP_C = 4

local function drop_gen(s, _)
  local n = s[DROP_N]
  while n > 0 do
    local nc = s[DROP_G](s[DROP_P], s[DROP_C])
    if nc == nil then
      return nil
    end
    s[DROP_C] = nc
    n = n - 1
  end
  s[DROP_N] = 0

  local nc, v = s[DROP_G](s[DROP_P], s[DROP_C])
  if nc == nil then
    return nil
  end
  s[DROP_C] = nc
  return ACTIVE, v
end

function T.drop(n, g, p, c)
  return drop_gen, { n, g, p, c }, 0
end

local DW_PRED = 1
local DW_G = 2
local DW_P = 3
local DW_C = 4
local DW_DONE = 5

local function drop_while_gen(s, _)
  while true do
    local nc, v = s[DW_G](s[DW_P], s[DW_C])
    if nc == nil then
      return nil
    end
    s[DW_C] = nc
    if s[DW_DONE] or not s[DW_PRED](v) then
      s[DW_DONE] = true
      return ACTIVE, v
    end
  end
end

function T.drop_while(pred, g, p, c)
  return drop_while_gen, { pred, g, p, c, false }, 0
end

local SCAN_F = 1
local SCAN_ACC = 2
local SCAN_G = 3
local SCAN_P = 4
local SCAN_C = 5

local function scan_gen(s, _)
  local nc, v = s[SCAN_G](s[SCAN_P], s[SCAN_C])
  if nc == nil then
    return nil
  end
  s[SCAN_C] = nc
  local acc = s[SCAN_F](s[SCAN_ACC], v)
  s[SCAN_ACC] = acc
  return ACTIVE, acc
end

function T.scan(f, acc, g, p, c)
  return scan_gen, { f, acc, g, p, c }, 0
end

local DEDUP_PREV = 1
local DEDUP_G = 2
local DEDUP_P = 3
local DEDUP_C = 4

local function dedup_gen(s, _)
  while true do
    local nc, v = s[DEDUP_G](s[DEDUP_P], s[DEDUP_C])
    if nc == nil then
      return nil
    end
    s[DEDUP_C] = nc
    if v ~= s[DEDUP_PREV] then
      s[DEDUP_PREV] = v
      return ACTIVE, v
    end
  end
end

function T.dedup(g, p, c)
  return dedup_gen, { DEDUP_SENTINEL, g, p, c }, 0
end

local CHUNK_N = 1
local CHUNK_G = 2
local CHUNK_P = 3
local CHUNK_C = 4

local function chunk_gen(s, _)
  local n = s[CHUNK_N]
  local buf = {}
  for i = 1, n do
    local nc, v = s[CHUNK_G](s[CHUNK_P], s[CHUNK_C])
    if nc == nil then
      if i > 1 then
        return ACTIVE, buf
      end
      return nil
    end
    s[CHUNK_C] = nc
    buf[i] = v
  end
  return ACTIVE, buf
end

function T.chunk(n, g, p, c)
  if n <= 0 then
    error("T.chunk: n must be >= 1", 2)
  end
  return chunk_gen, { n, g, p, c }, 0
end

local WINDOW_N = 1
local WINDOW_G = 2
local WINDOW_P = 3
local WINDOW_C = 4
local WINDOW_BUF = 5
local WINDOW_HEAD = 6
local WINDOW_READY = 7

local function copy_window(buf, head, n)
  local out = {}
  local k = 1
  for i = head, n do
    out[k] = buf[i]
    k = k + 1
  end
  for i = 1, head - 1 do
    out[k] = buf[i]
    k = k + 1
  end
  return out
end

local function window_gen(s, _)
  local n = s[WINDOW_N]
  local buf = s[WINDOW_BUF]

  if not s[WINDOW_READY] then
    for i = 1, n do
      local nc, v = s[WINDOW_G](s[WINDOW_P], s[WINDOW_C])
      if nc == nil then
        return nil
      end
      s[WINDOW_C] = nc
      buf[i] = v
    end
    s[WINDOW_HEAD] = 1
    s[WINDOW_READY] = true
    return ACTIVE, copy_window(buf, 1, n)
  end

  local nc, v = s[WINDOW_G](s[WINDOW_P], s[WINDOW_C])
  if nc == nil then
    return nil
  end
  s[WINDOW_C] = nc

  local head = s[WINDOW_HEAD]
  buf[head] = v
  head = head + 1
  if head > n then
    head = 1
  end
  s[WINDOW_HEAD] = head

  return ACTIVE, copy_window(buf, head, n)
end

function T.window(n, g, p, c)
  if n <= 0 then
    error("T.window: n must be >= 1", 2)
  end
  return window_gen, { n, g, p, c, {}, 1, false }, 0
end

local TAP_F = 1
local TAP_G = 2
local TAP_P = 3
local TAP_C = 4

local function tap_gen(s, _)
  local nc, v = s[TAP_G](s[TAP_P], s[TAP_C])
  if nc == nil then
    return nil
  end
  s[TAP_C] = nc
  s[TAP_F](v)
  return ACTIVE, v
end

function T.tap(f, g, p, c)
  return tap_gen, { f, g, p, c }, 0
end

-- enumerate is allocating by contract because it returns a fresh pair table.
-- Still, seq-backed enumeration is common enough that it gets a direct fast path
-- instead of paying the generic wrapped-triplet overhead.
local ENUM_G = 1
local ENUM_P = 2
local ENUM_C = 3

local function enumerate_gen(s, i)
  local nc, v = s[ENUM_G](s[ENUM_P], s[ENUM_C])
  if nc == nil then
    return nil
  end
  s[ENUM_C] = nc
  i = i + 1
  return i, { i, v }
end

local function enumerate_seq_gen(t, i)
  i = i + 1
  if i > #t then
    return nil
  end
  return i, { i, t[i] }
end

function T.enumerate(g, p, c)
  if is_fresh_seq(g, c) then
    return enumerate_seq_gen, p, 0
  end
  return enumerate_gen, { g, p, c }, 0
end

-- ═══════════════════════════════════════════
-- COMBINATORS: multiple triplets -> triplet
-- ═══════════════════════════════════════════

local CONCAT_G1 = 1
local CONCAT_P1 = 2
local CONCAT_C1 = 3
local CONCAT_G2 = 4
local CONCAT_P2 = 5
local CONCAT_C2 = 6

local function concat_gen(s, phase)
  if phase == 1 then
    local nc, v = s[CONCAT_G1](s[CONCAT_P1], s[CONCAT_C1])
    if nc ~= nil then
      s[CONCAT_C1] = nc
      return 1, v
    end
    phase = 2
  end

  local nc, v = s[CONCAT_G2](s[CONCAT_P2], s[CONCAT_C2])
  if nc == nil then
    return nil
  end
  s[CONCAT_C2] = nc
  return 2, v
end

function T.concat(g1, p1, c1, g2, p2, c2)
  return concat_gen, { g1, p1, c1, g2, p2, c2 }, 1
end

-- zip / zip_with are the clearest examples of the "generic kernel + explicit
-- specialization" rule. The generic packed-state machine is the default, but
-- seq+seq is common enough that a direct array-index path wins decisively.
local ZIP_G1 = 1
local ZIP_P1 = 2
local ZIP_C1 = 3
local ZIP_G2 = 4
local ZIP_P2 = 5
local ZIP_C2 = 6

local function zip_gen(s, _)
  local nc1, v1 = s[ZIP_G1](s[ZIP_P1], s[ZIP_C1])
  if nc1 == nil then
    return nil
  end
  local nc2, v2 = s[ZIP_G2](s[ZIP_P2], s[ZIP_C2])
  if nc2 == nil then
    return nil
  end
  s[ZIP_C1] = nc1
  s[ZIP_C2] = nc2
  return ACTIVE, v1, v2
end

local ZIPSEQ_A = 1
local ZIPSEQ_B = 2

local function zip_seq_gen(s, i)
  i = i + 1
  if i > #s[ZIPSEQ_A] or i > #s[ZIPSEQ_B] then
    return nil
  end
  return i, s[ZIPSEQ_A][i], s[ZIPSEQ_B][i]
end

function T.zip(g1, p1, c1, g2, p2, c2)
  if is_fresh_seq(g1, c1) and is_fresh_seq(g2, c2) then
    return zip_seq_gen, { p1, p2 }, 0
  end
  return zip_gen, { g1, p1, c1, g2, p2, c2 }, 0
end

local ZIPW_F = 1
local ZIPW_G1 = 2
local ZIPW_P1 = 3
local ZIPW_C1 = 4
local ZIPW_G2 = 5
local ZIPW_P2 = 6
local ZIPW_C2 = 7

local function zip_with_gen(s, _)
  local nc1, v1 = s[ZIPW_G1](s[ZIPW_P1], s[ZIPW_C1])
  if nc1 == nil then
    return nil
  end
  local nc2, v2 = s[ZIPW_G2](s[ZIPW_P2], s[ZIPW_C2])
  if nc2 == nil then
    return nil
  end
  s[ZIPW_C1] = nc1
  s[ZIPW_C2] = nc2
  return ACTIVE, s[ZIPW_F](v1, v2)
end

local ZIPWSEQ_F = 1
local ZIPWSEQ_A = 2
local ZIPWSEQ_B = 3

local function zip_with_seq_gen(s, i)
  i = i + 1
  if i > #s[ZIPWSEQ_A] or i > #s[ZIPWSEQ_B] then
    return nil
  end
  return i, s[ZIPWSEQ_F](s[ZIPWSEQ_A][i], s[ZIPWSEQ_B][i])
end

function T.zip_with(f, g1, p1, c1, g2, p2, c2)
  if is_fresh_seq(g1, c1) and is_fresh_seq(g2, c2) then
    return zip_with_seq_gen, { f, p1, p2 }, 0
  end
  return zip_with_gen, { f, g1, p1, c1, g2, p2, c2 }, 0
end

local IL_G1 = 1
local IL_P1 = 2
local IL_C1 = 3
local IL_G2 = 4
local IL_P2 = 5
local IL_C2 = 6
local IL_NEXT = 7
local IL_DONE1 = 8
local IL_DONE2 = 9

local function interleave_pull_1(s)
  local nc, v = s[IL_G1](s[IL_P1], s[IL_C1])
  if nc == nil then
    s[IL_DONE1] = true
    return nil
  end
  s[IL_C1] = nc
  s[IL_NEXT] = 2
  return ACTIVE, v
end

local function interleave_pull_2(s)
  local nc, v = s[IL_G2](s[IL_P2], s[IL_C2])
  if nc == nil then
    s[IL_DONE2] = true
    return nil
  end
  s[IL_C2] = nc
  s[IL_NEXT] = 1
  return ACTIVE, v
end

local function interleave_gen(s, _)
  if s[IL_DONE1] then
    if s[IL_DONE2] then
      return nil
    end
    return interleave_pull_2(s)
  end
  if s[IL_DONE2] then
    return interleave_pull_1(s)
  end

  if s[IL_NEXT] == 1 then
    local ctrl, v = interleave_pull_1(s)
    if ctrl ~= nil then
      return ctrl, v
    end
    if s[IL_DONE2] then
      return nil
    end
    return interleave_pull_2(s)
  end

  local ctrl, v = interleave_pull_2(s)
  if ctrl ~= nil then
    return ctrl, v
  end
  if s[IL_DONE1] then
    return nil
  end
  return interleave_pull_1(s)
end

function T.interleave(g1, p1, c1, g2, p2, c2)
  return interleave_gen, { g1, p1, c1, g2, p2, c2, 1, false, false }, 0
end

-- ═══════════════════════════════════════════
-- FLATMAP / CHAIN: the monadic bind
-- ═══════════════════════════════════════════

local FM_F = 1
local FM_G = 2
local FM_P = 3
local FM_C = 4
local FM_IG = 5
local FM_IP = 6
local FM_IC = 7

local function flatmap_gen(s, _)
  while true do
    local ig = s[FM_IG]
    if ig ~= nil then
      local nc, v = ig(s[FM_IP], s[FM_IC])
      if nc ~= nil then
        s[FM_IC] = nc
        return ACTIVE, v
      end
      s[FM_IG] = nil
    end

    local nc, outer_v = s[FM_G](s[FM_P], s[FM_C])
    if nc == nil then
      return nil
    end
    s[FM_C] = nc
    s[FM_IG], s[FM_IP], s[FM_IC] = s[FM_F](outer_v)
  end
end

function T.flatmap(f, g, p, c)
  return flatmap_gen, { f, g, p, c, nil, nil, nil }, 0
end

-- ═══════════════════════════════════════════
-- PIPELINE: stack of triplets
-- ═══════════════════════════════════════════

function T.pipe(f, g, p, c)
  return T.map(f, g, p, c)
end

function T.pipeline(g, p, c, ...)
  local transforms = { ... }
  for i = 1, #transforms do
    g, p, c = T.map(transforms[i], g, p, c)
  end
  return g, p, c
end

function T.compose(...)
  local fns = { ... }
  return function(x)
    for i = 1, #fns do
      x = fns[i](x)
    end
    return x
  end
end

local FL_GG = 1
local FL_GP = 2
local FL_GC = 3
local FL_IG = 4
local FL_IP = 5
local FL_IC = 6

local function flatten_gen(s, _)
  while true do
    local ig = s[FL_IG]
    if ig ~= nil then
      local nc, v = ig(s[FL_IP], s[FL_IC])
      if nc ~= nil then
        s[FL_IC] = nc
        return ACTIVE, v
      end
      s[FL_IG] = nil
    end

    local nc, g, p, c = s[FL_GG](s[FL_GP], s[FL_GC])
    if nc == nil then
      return nil
    end
    s[FL_GC] = nc
    s[FL_IG], s[FL_IP], s[FL_IC] = g, p, c
  end
end

function T.flatten(gg, gp, gc)
  return flatten_gen, { gg, gp, gc, nil, nil, nil }, 0
end

-- ═══════════════════════════════════════════
-- CONSUMERS: leave the space
-- ═══════════════════════════════════════════

function T.fold(f, acc, g, p, c)
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then
      return acc
    end
    ctrl = nc
    acc = f(acc, v)
  end
end

function T.foldT(f, acc, g, p, c)
  return T.unit(T.fold(f, acc, g, p, c))
end

function T.collect(g, p, c)
  local t, n = {}, 0
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then
      return t
    end
    ctrl = nc
    n = n + 1
    t[n] = v
  end
end

function T.each(f, g, p, c)
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then
      return
    end
    ctrl = nc
    f(v)
  end
end

function T.first(g, p, c, default)
  local nc, v = g(p, c)
  if nc == nil then
    return default
  end
  return v
end

function T.last(g, p, c, default)
  local result = default
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then
      return result
    end
    ctrl = nc
    result = v
  end
end

function T.count(g, p, c)
  local n = 0
  local ctrl = c
  while true do
    local nc = g(p, ctrl)
    if nc == nil then
      return n
    end
    ctrl = nc
    n = n + 1
  end
end

function T.any(pred, g, p, c)
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then
      return false
    end
    ctrl = nc
    if pred(v) then
      return true
    end
  end
end

function T.all(pred, g, p, c)
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then
      return true
    end
    ctrl = nc
    if not pred(v) then
      return false
    end
  end
end

function T.find(pred, g, p, c)
  local ctrl = c
  while true do
    local nc, v = g(p, ctrl)
    if nc == nil then
      return nil
    end
    ctrl = nc
    if pred(v) then
      return v
    end
  end
end

function T.join(sep, g, p, c)
  return table_concat(T.collect(g, p, c), sep)
end

-- ═══════════════════════════════════════════
-- RE-ENTRY: back into the space from tables
-- ═══════════════════════════════════════════

function T.pairs(t)
  return next, t, nil
end

local function ipairs_gen(t, i)
  i = i + 1
  local v = t[i]
  if v == nil then
    return nil
  end
  return i, v
end

function T.ipairs(t)
  return ipairs_gen, t, 0
end

-- ═══════════════════════════════════════════
-- META: iterators of iterators
-- ═══════════════════════════════════════════

-- tee has two implementations:
--   • tee(2): specialized hot path with direct handoff slots plus queue fallback
--   • tee(n): general queue-based implementation
--
-- The specialization matters because balanced tee(2) is common, while skewed
-- tee(2) must still avoid the old O(n) table.remove(1) disaster.
local TEE_SHARED_G = 1
local TEE_SHARED_P = 2
local TEE_SHARED_C = 3
local TEE_SHARED_DONE = 4
local TEE_SHARED_BUFS = 5
local TEE_SHARED_HEADS = 6
local TEE_SHARED_TAILS = 7
local TEE_SHARED_N = 8

local TEE_BRANCH_SHARED = 1
local TEE_BRANCH_ID = 2

local function tee_branch_gen(branch, _)
  local shared = branch[TEE_BRANCH_SHARED]
  local id = branch[TEE_BRANCH_ID]

  local bufs = shared[TEE_SHARED_BUFS]
  local heads = shared[TEE_SHARED_HEADS]
  local tails = shared[TEE_SHARED_TAILS]

  local head = heads[id]
  local tail = tails[id]
  if head <= tail then
    local buf = bufs[id]
    local v = buf[head]
    buf[head] = nil
    head = head + 1
    if head > tail then
      head = 1
      tail = 0
    end
    heads[id] = head
    tails[id] = tail
    return ACTIVE, v
  end

  if shared[TEE_SHARED_DONE] then
    return nil
  end

  local nc, v = shared[TEE_SHARED_G](shared[TEE_SHARED_P], shared[TEE_SHARED_C])
  if nc == nil then
    shared[TEE_SHARED_DONE] = true
    return nil
  end
  shared[TEE_SHARED_C] = nc

  local n = shared[TEE_SHARED_N]
  for i = 1, n do
    if i ~= id then
      local t = tails[i] + 1
      tails[i] = t
      bufs[i][t] = v
    end
  end

  return ACTIVE, v
end

local TEE2_G = 1
local TEE2_P = 2
local TEE2_C = 3
local TEE2_DONE = 4
local TEE2_Q1 = 5
local TEE2_H1 = 6
local TEE2_T1 = 7
local TEE2_Q2 = 8
local TEE2_H2 = 9
local TEE2_T2 = 10
local TEE2_HAS1 = 11
local TEE2_VAL1 = 12
local TEE2_HAS2 = 13
local TEE2_VAL2 = 14

local function tee2_push_other(shared, other_has_slot, other_val_slot, other_q_slot, other_t_slot, v)
  if shared[other_has_slot] then
    local t = shared[other_t_slot] + 1
    shared[other_t_slot] = t
    shared[other_q_slot][t] = v
  else
    shared[other_has_slot] = true
    shared[other_val_slot] = v
  end
end

local function tee2_pop_queue(shared, q_slot, h_slot, t_slot)
  local head = shared[h_slot]
  local tail = shared[t_slot]
  if head <= tail then
    local q = shared[q_slot]
    local v = q[head]
    q[head] = nil
    head = head + 1
    if head > tail then
      head = 1
      tail = 0
    end
    shared[h_slot] = head
    shared[t_slot] = tail
    return v
  end
  return nil
end

local function tee2_branch1_gen(shared, _)
  if shared[TEE2_HAS1] then
    local v = shared[TEE2_VAL1]
    shared[TEE2_HAS1] = false
    shared[TEE2_VAL1] = nil
    return ACTIVE, v
  end

  local qv = tee2_pop_queue(shared, TEE2_Q1, TEE2_H1, TEE2_T1)
  if qv ~= nil then
    return ACTIVE, qv
  end

  if shared[TEE2_DONE] then
    return nil
  end

  local nc, v = shared[TEE2_G](shared[TEE2_P], shared[TEE2_C])
  if nc == nil then
    shared[TEE2_DONE] = true
    return nil
  end
  shared[TEE2_C] = nc
  tee2_push_other(shared, TEE2_HAS2, TEE2_VAL2, TEE2_Q2, TEE2_T2, v)
  return ACTIVE, v
end

local function tee2_branch2_gen(shared, _)
  if shared[TEE2_HAS2] then
    local v = shared[TEE2_VAL2]
    shared[TEE2_HAS2] = false
    shared[TEE2_VAL2] = nil
    return ACTIVE, v
  end

  local qv = tee2_pop_queue(shared, TEE2_Q2, TEE2_H2, TEE2_T2)
  if qv ~= nil then
    return ACTIVE, qv
  end

  if shared[TEE2_DONE] then
    return nil
  end

  local nc, v = shared[TEE2_G](shared[TEE2_P], shared[TEE2_C])
  if nc == nil then
    shared[TEE2_DONE] = true
    return nil
  end
  shared[TEE2_C] = nc
  tee2_push_other(shared, TEE2_HAS1, TEE2_VAL1, TEE2_Q1, TEE2_T1, v)
  return ACTIVE, v
end

function T.tee(n, g, p, c)
  if n == 2 then
    local shared = { g, p, c, false, {}, 1, 0, {}, 1, 0, false, nil, false, nil }
    return {
      { tee2_branch1_gen, shared, 0 },
      { tee2_branch2_gen, shared, 0 },
    }
  end

  if n <= 0 then
    return {}
  end

  local buffers = {}
  local heads = {}
  local tails = {}
  for i = 1, n do
    buffers[i] = {}
    heads[i] = 1
    tails[i] = 0
  end

  local shared = { g, p, c, false, buffers, heads, tails, n }
  local iters = {}
  for i = 1, n do
    iters[i] = { tee_branch_gen, { shared, i }, 0 }
  end
  return iters
end

function T.partition(pred, g, p, c)
  local copies = T.tee(2, g, p, c)
  local bg1, bp1, bc1 = copies[1][1], copies[1][2], copies[1][3]
  local bg2, bp2, bc2 = copies[2][1], copies[2][2], copies[2][3]
  local g1, p1, c1 = T.filter(pred, bg1, bp1, bc1)
  local g2, p2, c2 = filter_not(pred, bg2, bp2, bc2)
  return g1, p1, c1, g2, p2, c2
end

-- ═══════════════════════════════════════════
-- FLUENT WRAPPER: optional method chaining
-- ═══════════════════════════════════════════

local Stream = {}
Stream.__index = Stream

function Stream:map(f)         return setmetatable({ T.map(f, self[1], self[2], self[3]) }, Stream) end
function Stream:filter(f)      return setmetatable({ T.filter(f, self[1], self[2], self[3]) }, Stream) end
function Stream:take(n)        return setmetatable({ T.take(n, self[1], self[2], self[3]) }, Stream) end
function Stream:drop(n)        return setmetatable({ T.drop(n, self[1], self[2], self[3]) }, Stream) end
function Stream:scan(f, acc)   return setmetatable({ T.scan(f, acc, self[1], self[2], self[3]) }, Stream) end
function Stream:dedup()        return setmetatable({ T.dedup(self[1], self[2], self[3]) }, Stream) end
function Stream:chunk(n)       return setmetatable({ T.chunk(n, self[1], self[2], self[3]) }, Stream) end
function Stream:tap(f)         return setmetatable({ T.tap(f, self[1], self[2], self[3]) }, Stream) end
function Stream:enumerate()    return setmetatable({ T.enumerate(self[1], self[2], self[3]) }, Stream) end
function Stream:flatmap(f)     return setmetatable({ T.flatmap(f, self[1], self[2], self[3]) }, Stream) end
function Stream:take_while(f)  return setmetatable({ T.take_while(f, self[1], self[2], self[3]) }, Stream) end

function Stream:fold(f, acc)   return T.fold(f, acc, self[1], self[2], self[3]) end
function Stream:collect()      return T.collect(self[1], self[2], self[3]) end
function Stream:each(f)        return T.each(f, self[1], self[2], self[3]) end
function Stream:first(d)       return T.first(self[1], self[2], self[3], d) end
function Stream:last(d)        return T.last(self[1], self[2], self[3], d) end
function Stream:count()        return T.count(self[1], self[2], self[3]) end
function Stream:any(f)         return T.any(f, self[1], self[2], self[3]) end
function Stream:all(f)         return T.all(f, self[1], self[2], self[3]) end
function Stream:find(f)        return T.find(f, self[1], self[2], self[3]) end
function Stream:join(s)        return T.join(s, self[1], self[2], self[3]) end

function Stream:unpack()       return self[1], self[2], self[3] end
function Stream:iter()         return self[1], self[2], self[3] end

function T.stream(g, p, c)
  return setmetatable({ g, p, c }, Stream)
end

function T.S(t)
  return T.stream(T.seq(t))
end

function T.R(a, b, step)
  return T.stream(T.range(a, b, step))
end

return T
