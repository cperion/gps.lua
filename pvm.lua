-- pvm.lua — the recording phase boundary
--
-- One primitive. Everything else is composition.
--
-- The insight: the memoize boundary, the fusion boundary, and
-- the machine boundary are the same thing — a recording triplet
-- keyed by ASDL unique identity.
--
-- On hit:  seq over cached array. Zero work.
-- On miss: recording triplet that lazily evaluates, records,
--          and commits to cache on full drain.
-- On repeated miss for the same node during that drain:
--          share the in-flight recording instead of re-running it.
--
-- Adjacent misses fuse automatically: the outermost drain is
-- the only loop. LuaJIT traces straight through the entire
-- miss chain as one path.
--
-- Partial drain (execution only needs some elements) is safe:
-- the not-yet-exhausted phase does not commit, and next access
-- re-evaluates lazily. Inner phases may still commit if they
-- were individually fully drained before the outer stop.
-- Full drain commits all exhausted intermediate caches as side effects.
--
-- ── API ─────────────────────────────────────────────────────
--
--   pvm.context()              ASDL type system (interned, immutable)
--   pvm.with(node, overrides)  structural update preserving sharing
--   pvm.T                      triplet algebra module
--
--   pvm.phase(name, handlers)  streaming boundary (dispatch table)
--   pvm.phase(name, fn)        scalar boundary as lazy single-element stream
--   pvm.one(g, p, c)           terminal: consume exactly one element
--   pvm.lower(name, fn)        compatibility wrapper over phase + one
--   pvm.drain(g, p, c)         canonical terminal: materialize → array
--   pvm.drain_into(g, p, c, out)  terminal optimization for append-only sinks
--   pvm.report(phases)         cache behavior diagnostics
--
-- ── What pvm2 primitives this replaces ──────────────────────
--
--   pvm2.verb_memo   → pvm.phase (recording triplet on miss)
--   pvm2.verb_iter   → pvm.phase (just don't cache: use T directly)
--   pvm2.verb_flat   → pvm.phase + pvm.drain_into
--   pvm2.pipe        → chain of phases (fusion is automatic)
--   pvm2.fuse_maps   → T.map/T.filter over phase output (fusion is automatic)
--   pvm2.fuse_pipeline → just call phases in sequence (fusion is automatic)
--
-- ── Why this works ──────────────────────────────────────────
--
--   The triplet (g, p, c) IS (gen, param, state).
--   The phase boundary IS a machine boundary.
--   The cache check IS the fusion gate.
--
--   Hit  → skip the machine entirely.
--   Miss → run the machine lazily, record as side effect.
--   Adjacent misses → one fused pass, one trace.
--
--   The compiler does not produce machines.
--   The compiler IS machines. All the way down.

local unpack = table.unpack or unpack
local Triplet = require("triplet")

local pvm = {}

local function get_asdl()
    if not package.preload["gps.asdl_lexer"] then
        package.preload["gps.asdl_lexer"] = function() return require("asdl_lexer") end
    end
    if not package.preload["gps.asdl_parser"] then
        package.preload["gps.asdl_parser"] = function() return require("asdl_parser") end
    end
    if not package.preload["gps.asdl_context"] then
        package.preload["gps.asdl_context"] = function() return require("asdl_context") end
    end
    return require("gps.asdl_context")
end

function pvm.context()
    local ctx = get_asdl().NewContext()
    local orig = ctx.Define
    function ctx:Define(text)
        orig(self, text)
        return self
    end
    return ctx
end

function pvm.with(node, overrides)
    local mt = getmetatable(node)
    if not mt or not mt.__fields then
        error("pvm.with: not an ASDL node", 2)
    end
    local fields = mt.__fields
    local args = {}
    for i = 1, #fields do
        local name = fields[i].name
        args[i] = overrides[name] ~= nil and overrides[name] or node[name]
    end
    return mt(unpack(args, 1, #fields))
end
local getmetatable = getmetatable
local type = type
local rawset = rawset
local select = select

local function normalize_handlers(handlers)
	local normalized = {}
	for key, fn in pairs(handlers) do
		local class = key
		if type(key) == "table"
			and rawget(key, "__fields") == nil
			and rawget(key, "members") == nil then
			local mt = getmetatable(key)
			if type(mt) == "table" then
				class = mt
			end
		end
		normalized[class] = fn
	end
	return normalized
end

-- ══════════════════════════════════════════════════════════════
--  FOUNDATION — from pvm, unchanged
-- ══════════════════════════════════════════════════════════════

pvm.T = Triplet

-- ══════════════════════════════════════════════════════════════
--  SEQ — the hit-path gen
--
--  Iterates a flat cached array. The fast path.
--  On cache hit, this is all that runs.
-- ══════════════════════════════════════════════════════════════

local function seq_gen(t, i)
	i = i + 1
	if i > #t then
		return nil
	end
	return i, t[i]
end

local function seq_n_gen(s, i)
	i = i + 1
	if i > s.n then
		return nil
	end
	return i, s.array[i]
end

-- ══════════════════════════════════════════════════════════════
--  RECORDING GEN — the miss-path gen
--
--  The core primitive of pvm.
--
--  A recording is shared by every consumer that asks for the same
--  node while the miss is still in flight.
--
--  Each consumer tracks only its read index. The shared recording
--  owns the source triplet state and the growing output buffer.
--  If a consumer asks for an element that is already buffered, it
--  reads it directly. Otherwise it advances the shared source by
--  one step, records that value, and returns it.
--
--  When the shared source exhausts, the buffer commits to cache and
--  all later lookups become plain seq hits.
--
--  Internally the recording entry is packed in array slots so the
--  hot triplet path stays field-light and trace-friendly.
--
--  Properties:
--   • invisible to consumer (valid triplet)
--   • composable with T.map, T.filter, T.concat, etc.
--   • fuses with adjacent recording gens (one trace)
--   • deduplicates repeated in-flight misses for the same node
--   • populates cache as side effect of full consumption
--   • safe under partial consumption (the unexhausted recording does not commit)
-- ══════════════════════════════════════════════════════════════

local REC_NAME    = 1
local REC_NODE    = 2
local REC_CACHE   = 3
local REC_PENDING = 4
local REC_BUF     = 5
local REC_N       = 6
local REC_DONE    = 7
local REC_G       = 8
local REC_P       = 9
local REC_C       = 10
local REC_PACKED  = 11

local function finish_recording(entry)
	if entry[REC_DONE] then
		return
	end
	entry[REC_DONE] = true
	if entry[REC_PACKED] then
		entry[REC_CACHE][entry[REC_NODE]] = { array = entry[REC_BUF], n = entry[REC_N] }
	else
		entry[REC_CACHE][entry[REC_NODE]] = entry[REC_BUF]
	end
	entry[REC_PENDING][entry[REC_NODE]] = nil
end

local function advance_recording(entry)
	if entry[REC_DONE] then
		return false
	end
	local c, val = entry[REC_G](entry[REC_P], entry[REC_C])
	if c == nil then
		finish_recording(entry)
		return false
	end
	entry[REC_C] = c
	local n = entry[REC_N] + 1
	entry[REC_N] = n
	entry[REC_BUF][n] = val
	return true
end

local function recording_gen(entry, i)
	i = i + 1
	if i <= entry[REC_N] then
		return i, entry[REC_BUF][i]
	end
	if not advance_recording(entry) then
		return nil
	end
	return i, entry[REC_BUF][i]
end

-- ══════════════════════════════════════════════════════════════
--  PHASE — the one boundary primitive
--
--  Replaces: verb_memo, verb_iter, verb_flat, pipe, fuse_maps.
--
--  Canonical pvm usage is phase -> triplet -> terminal consumer.
--  drain/fold/each are the primary exits. drain_into is just a
--  sink optimization; it is not a second execution model.
--
--  A phase is a recording triplet boundary keyed by ASDL unique
--  identity.
--
--  Handlers receive a node and return a triplet (g, p, c).
--  The handler's triplet is the raw production of that phase
--  for that node.
--
--  On hit:  return seq over cached array. Zero work.
--  On repeated lookup while a miss is already being recorded:
--           return another reader over that in-flight recording.
--  On miss: return recording triplet wrapping the handler's
--           output. Evaluation is lazy. Cache fills on drain.
--
--  Handlers call child phases inside their body. If a child
--  hits, the parent gets seq (instant). If a child misses,
--  the parent gets a recording triplet. The recording triplets
--  nest. The outermost drain pulls through all of them in one
--  pass.
--
--  Usage:
--
--    local lower = pvm.phase("lower", {
--        [Widget.Row] = function(node)
--            -- return triplet: concatenation of lowered children
--            return T.concat(
--                lower(node.children[1]),   -- recursive, may hit or miss
--                lower(node.children[2])
--            )
--        end,
--        [Widget.Text] = function(node)
--            -- leaf: return a single-element triplet
--            return pvm.once(DrawText(node.value, node.style))
--        end,
--    })
--
--    -- pull-driven: nothing evaluates until you drain
--    local commands = pvm.drain(lower(root))
--
-- ══════════════════════════════════════════════════════════════

local VALUE_FN = 1
local VALUE_NODE = 2
local VALUE_READY = 3
local VALUE_DATA = 4

local function value_once_gen(s, emitted)
	if emitted ~= 0 then
		return nil
	end
	if not s[VALUE_READY] then
		s[VALUE_DATA] = s[VALUE_FN](s[VALUE_NODE])
		s[VALUE_READY] = true
	end
	return 1, s[VALUE_DATA]
end

function pvm.phase(name, handlers_or_fn)
	local dispatch = nil
	local value_fn = nil

	local handlers_t = type(handlers_or_fn)
	if handlers_t == "table" then
		dispatch = normalize_handlers(handlers_or_fn)
	elseif handlers_t == "function" then
		value_fn = handlers_or_fn
	else
		error("pvm.phase: second argument must be handlers table or value function", 2)
	end

	local cache = setmetatable({}, { __mode = "k" })
	local pending = setmetatable({}, { __mode = "k" })
	local stats = { name = name, calls = 0, hits = 0, shared = 0 }

	local function call(self_or_node, maybe_node)
		local node = maybe_node or self_or_node
		stats.calls = stats.calls + 1

		-- cache hit: instant
		local hit = cache[node]
		if hit ~= nil then
			stats.hits = stats.hits + 1
			if hit.array ~= nil and hit.n ~= nil then
				return seq_n_gen, hit, 0
			end
			return seq_gen, hit, 0
		end

		-- in-flight hit: share the recording already underway
		local inflight = pending[node]
		if inflight ~= nil then
			stats.shared = stats.shared + 1
			return recording_gen, inflight, 0
		end

		local g, p, c
		if value_fn ~= nil then
			g, p, c = value_once_gen, { value_fn, node, false, nil }, 0
		else
			-- miss: dispatch
			local mt = getmetatable(node)
			local handler = dispatch[mt]
			if not handler then
				error("pvm.phase '" .. name .. "': no handler for " .. tostring(mt and mt.kind or type(node)), 2)
			end
			g, p, c = handler(node)
		end

		-- if handler returned nil, treat as empty production
		if g == nil then
			local empty = {}
			cache[node] = empty
			return seq_gen, empty, 0
		end

		local entry = {
			name,
			node,
			cache,
			pending,
			{},
			0,
			false,
			g,
			p,
			c,
			value_fn ~= nil,
		}
		pending[node] = entry
		return recording_gen, entry, 0
	end

	-- inject method on handler classes so nodes can call node:phase_name()
	if dispatch ~= nil then
		for cls, _ in pairs(dispatch) do
			rawset(cls, name, call)
		end
	end

	-- the boundary object
	local boundary = {}
	boundary.name = name

	boundary.__call = call

	function boundary:stats()
		return stats
	end

	function boundary:hit_ratio()
		if stats.calls == 0 then
			return 1.0
		end
		return stats.hits / stats.calls
	end

	function boundary:reuse_ratio()
		if stats.calls == 0 then
			return 1.0
		end
		return (stats.hits + stats.shared) / stats.calls
	end

	function boundary:reset()
		cache = setmetatable({}, { __mode = "k" })
		pending = setmetatable({}, { __mode = "k" })
		stats.calls = 0
		stats.hits = 0
		stats.shared = 0
		-- re-inject methods since cache ref changed
		if dispatch ~= nil then
			for cls, _ in pairs(dispatch) do
				rawset(cls, name, call)
			end
		end
	end

	-- allow inspecting what's cached for a node (testing/debugging)
	function boundary:cached(node)
		return cache[node]
	end

	function boundary:inflight(node)
		return pending[node]
	end

	-- force a node's cache to be populated (eager pre-compilation)
	function boundary:warm(node)
		local g, p, c = call(node)
		-- drain to force commit
		while true do
			c, _ = g(p, c)
			if c == nil then
				break
			end
		end
		return cache[node]
	end

	return setmetatable(boundary, boundary)
end

-- ══════════════════════════════════════════════════════════════
--  LOWER — compatibility wrapper over phase + one
--
--  Keep existing call sites working while converging on
--  a single public boundary concept (`pvm.phase`).
--
--    local solve_phase = pvm.phase("solve", fn)
--    local solved = pvm.one(solve_phase(node))
--
--  `pvm.lower` now preserves old ergonomics (`solve(node)`)
--  by wrapping that pattern.
-- ══════════════════════════════════════════════════════════════

local function cached_scalar_value(cached)
	if cached == nil then
		return nil
	end
	if cached.array ~= nil and cached.n ~= nil then
		if cached.n == 0 then
			return nil
		end
		return cached.array[1]
	end
	return cached[1]
end

function pvm.lower(name, fn)
	local scalar_phase = pvm.phase(name, fn)

	local boundary = {}
	boundary.name = name
	boundary.__phase = scalar_phase

	boundary.__call = function(_, node, ...)
		if select("#", ...) ~= 0 then
			error("pvm.lower '" .. tostring(name) .. "': extra args are not supported", 2)
		end
		return pvm.one(scalar_phase(node))
	end

	function boundary:stats()
		return scalar_phase:stats()
	end

	function boundary:hit_ratio()
		return scalar_phase:hit_ratio()
	end

	function boundary:reuse_ratio()
		return scalar_phase:reuse_ratio()
	end

	function boundary:reset()
		scalar_phase:reset()
	end

	function boundary:cached(node)
		return cached_scalar_value(scalar_phase:cached(node))
	end

	function boundary:warm(node, ...)
		if select("#", ...) ~= 0 then
			error("pvm.lower '" .. tostring(name) .. "': extra args are not supported", 2)
		end
		return cached_scalar_value(scalar_phase:warm(node))
	end

	return setmetatable(boundary, boundary)
end

local function copy_seq_array(array, start_i, end_i)
	if start_i > end_i then
		return {}
	end
	local out, n = {}, 0
	for i = start_i, end_i do
		n = n + 1
		out[n] = array[i]
	end
	return out
end

local function append_seq_array(out, array, start_i, end_i)
	if start_i > end_i then
		return out
	end
	local n = #out
	for i = start_i, end_i do
		n = n + 1
		out[n] = array[i]
	end
	return out
end

local function drain_recording(entry, start_i)
	if entry[REC_DONE] then
		return copy_seq_array(entry[REC_BUF], start_i, entry[REC_N])
	end
	local result, n = {}, 0
	for i = start_i, entry[REC_N] do
		n = n + 1
		result[n] = entry[REC_BUF][i]
	end
	while advance_recording(entry) do
		n = n + 1
		result[n] = entry[REC_BUF][entry[REC_N]]
	end
	return result
end

local function drain_recording_into(entry, start_i, out)
	out = append_seq_array(out, entry[REC_BUF], start_i, entry[REC_N])
	if entry[REC_DONE] then
		return out
	end
	local n = #out
	while advance_recording(entry) do
		n = n + 1
		out[n] = entry[REC_BUF][entry[REC_N]]
	end
	return out
end

-- ══════════════════════════════════════════════════════════════
--  DRAIN — force full materialization
--
--  Pulls all elements from a triplet into a flat array.
--  This is the outermost boundary — the thing that causes
--  all recording triplets in the chain to commit their caches.
--
--  Use this when you need a concrete array:
--   • installing an artifact
--   • passing to a backend
--   • testing
--
--  In normal operation, execution pulls lazily and drain is
--  only called at the outermost install boundary.
-- ══════════════════════════════════════════════════════════════

function pvm.drain(g, p, c)
	if g == nil then
		return {}
	end
	if g == seq_gen then
		return copy_seq_array(p, c + 1, #p)
	end
	if g == seq_n_gen then
		return copy_seq_array(p.array, c + 1, p.n)
	end
	if g == recording_gen then
		return drain_recording(p, c + 1)
	end
	local result, n = {}, 0
	while true do
		local val
		c, val = g(p, c)
		if c == nil then
			break
		end
		n = n + 1
		result[n] = val
	end
	return result
end

-- Drain appending to an existing output array.
-- This is a sink optimization over the canonical triplet path,
-- not a separate flat execution architecture.

function pvm.drain_into(g, p, c, out)
	if g == nil then
		return out
	end
	if g == seq_gen then
		return append_seq_array(out, p, c + 1, #p)
	end
	if g == seq_n_gen then
		return append_seq_array(out, p.array, c + 1, p.n)
	end
	if g == recording_gen then
		return drain_recording_into(p, c + 1, out)
	end
	local n = #out
	while true do
		local val
		c, val = g(p, c)
		if c == nil then
			break
		end
		n = n + 1
		out[n] = val
	end
	return out
end

-- ══════════════════════════════════════════════════════════════
--  EACH — drain with per-element callback
--
--  For side-effectful consumption (rendering, audio output)
--  without materializing an array.
--
--    pvm.each(render(root), function(cmd)
--        execute_draw(cmd)
--    end)
--
-- ══════════════════════════════════════════════════════════════

function pvm.each(g, p, c, fn)
	if g == nil then
		return
	end
	if g == seq_gen then
		for i = c + 1, #p do fn(p[i]) end
		return
	end
	if g == seq_n_gen then
		for i = c + 1, p.n do fn(p.array[i]) end
		return
	end
	if g == recording_gen then
		for i = c + 1, p[REC_N] do fn(p[REC_BUF][i]) end
		while advance_recording(p) do
			fn(p[REC_BUF][p[REC_N]])
		end
		return
	end
	while true do
		local val
		c, val = g(p, c)
		if c == nil then
			break
		end
		fn(val)
	end
end

-- ══════════════════════════════════════════════════════════════
--  FOLD — drain with accumulator
--
--  For reductions that don't need an intermediate array.
--
--    local total = pvm.fold(phase(root), 0, function(acc, val)
--        return acc + val.size
--    end)
--
-- ══════════════════════════════════════════════════════════════

function pvm.fold(g, p, c, init, fn)
	if g == nil then
		return init
	end
	local acc = init
	if g == seq_gen then
		for i = c + 1, #p do acc = fn(acc, p[i]) end
		return acc
	end
	if g == seq_n_gen then
		for i = c + 1, p.n do acc = fn(acc, p.array[i]) end
		return acc
	end
	if g == recording_gen then
		for i = c + 1, p[REC_N] do acc = fn(acc, p[REC_BUF][i]) end
		while advance_recording(p) do
			acc = fn(acc, p[REC_BUF][p[REC_N]])
		end
		return acc
	end
	while true do
		local val
		c, val = g(p, c)
		if c == nil then
			break
		end
		acc = fn(acc, val)
	end
	return acc
end

-- ══════════════════════════════════════════════════════════════
--  ONE — consume exactly one element from a triplet
--
--  Useful for scalar boundaries expressed as phases.
--  Errors if the stream is empty or has more than one element.
-- ══════════════════════════════════════════════════════════════

function pvm.one(g, p, c)
	if g == nil then
		error("pvm.one: expected exactly 1 element, got 0", 2)
	end
	if g == seq_gen then
		local i = c + 1
		local n = #p
		if i > n then
			error("pvm.one: expected exactly 1 element, got 0", 2)
		end
		if i < n then
			error("pvm.one: expected exactly 1 element, got more", 2)
		end
		return p[i]
	end
	if g == seq_n_gen then
		local i = c + 1
		local n = p.n
		if i > n then
			error("pvm.one: expected exactly 1 element, got 0", 2)
		end
		if i < n then
			error("pvm.one: expected exactly 1 element, got more", 2)
		end
		return p.array[i]
	end
	if g == recording_gen then
		local i = c + 1
		if i > p[REC_N] then
			if not advance_recording(p) then
				error("pvm.one: expected exactly 1 element, got 0", 2)
			end
		end
		local value = p[REC_BUF][i]
		if i < p[REC_N] then
			error("pvm.one: expected exactly 1 element, got more", 2)
		end
		if advance_recording(p) then
			error("pvm.one: expected exactly 1 element, got more", 2)
		end
		return value
	end

	local c1, v1 = g(p, c)
	if c1 == nil then
		error("pvm.one: expected exactly 1 element, got 0", 2)
	end
	local c2 = g(p, c1)
	if c2 ~= nil then
		error("pvm.one: expected exactly 1 element, got more", 2)
	end
	return v1
end

-- ══════════════════════════════════════════════════════════════
--  REPORT — cache behavior diagnostics
--
--  The hit ratio is the design-quality metric.
--  90%+ means the decomposition is healthy.
--  <50% means the ASDL or phase boundaries are wrong.
-- ══════════════════════════════════════════════════════════════

function pvm.report(phases)
	local out = {}
	for i = 1, #phases do
		local s = phases[i]:stats()
		local calls = s.calls or 0
		local hits = s.hits or 0
		local shared = s.shared or 0
		out[i] = {
			name = s.name,
			calls = calls,
			hits = hits,
			shared = shared,
			ratio = calls > 0 and (hits / calls) or 1.0,
			reuse_ratio = calls > 0 and ((hits + shared) / calls) or 1.0,
		}
	end
	return out
end

-- Formatted report string
function pvm.report_string(phases)
	local lines = {}
	local report = pvm.report(phases)
	for i = 1, #report do
		local r = report[i]
		lines[i] = string.format("  %-24s calls=%-6d hits=%-6d shared=%-6d reuse=%.1f%%", r.name, r.calls, r.hits, r.shared, r.reuse_ratio * 100)
	end
	return table.concat(lines, "\n")
end

-- ══════════════════════════════════════════════════════════════
--  ARRAY AS TRIPLET — unchanged from pvm2
-- ══════════════════════════════════════════════════════════════

function pvm.seq(array, n)
	n = n or #array
	if n >= #array then
		return seq_gen, array, 0
	end
	return seq_n_gen, { array = array, n = n }, 0
end

function pvm.seq_rev(array, n)
	n = n or #array
	if n > #array then
		n = #array
	end
	local function rev_gen(a, i)
		i = i - 1
		if i < 1 then
			return nil
		end
		return i, a[i]
	end
	return rev_gen, array, n + 1
end

-- ══════════════════════════════════════════════════════════════
--  ONCE — single-element triplet
--
--  The leaf case. When a handler produces one output element.
--
--    [Widget.Text] = function(node)
--        return pvm.once(DrawText(node.value))
--    end
--
-- ══════════════════════════════════════════════════════════════

local function once_gen(val, emitted)
	if emitted ~= 0 then
		return nil
	end
	return 1, val
end

function pvm.once(value)
	return once_gen, value, 0
end

-- ══════════════════════════════════════════════════════════════
--  EMPTY — zero-element triplet
-- ══════════════════════════════════════════════════════════════

local function empty_gen()
	return nil
end

function pvm.empty()
	return empty_gen, nil, nil
end

-- ══════════════════════════════════════════════════════════════
--  CONCAT — specialized small-arity concatenation
--
--  concat2/concat3 avoid the meta-iterator and packed-table
--  overhead of concat_all for the most common cases.
-- ══════════════════════════════════════════════════════════════

local function concat2_gen(s, phase)
	if phase == 1 then
		local nc, v = s[1](s[2], s[3])
		if nc ~= nil then
			s[3] = nc
			return 1, v
		end
		phase = 2
	end
	local nc, v = s[4](s[5], s[6])
	if nc == nil then
		return nil
	end
	s[6] = nc
	return 2, v
end

local function concat3_gen(s, phase)
	if phase == 1 then
		local nc, v = s[1](s[2], s[3])
		if nc ~= nil then
			s[3] = nc
			return 1, v
		end
		phase = 2
	end
	if phase == 2 then
		local nc, v = s[4](s[5], s[6])
		if nc ~= nil then
			s[6] = nc
			return 2, v
		end
		phase = 3
	end
	local nc, v = s[7](s[8], s[9])
	if nc == nil then
		return nil
	end
	s[9] = nc
	return 3, v
end

function pvm.concat2(g1, p1, c1, g2, p2, c2)
	return concat2_gen, { g1, p1, c1, g2, p2, c2 }, 1
end

function pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
	return concat3_gen, { g1, p1, c1, g2, p2, c2, g3, p3, c3 }, 1
end

-- ══════════════════════════════════════════════════════════════
--  CONCAT_ALL — N-way triplet concatenation
--
--  Takes an array of packed triplets: { {g,p,c}, {g,p,c}, ... }
--  Returns a single concatenated triplet.
--
--  For large arity this stays inside pvm with one small state machine
--  instead of building a meta-iterator for Triplet.flatten().
-- ══════════════════════════════════════════════════════════════

local CONCAT_TRIPS = 1
local CONCAT_N     = 2
local CONCAT_I     = 3
local CONCAT_G     = 4
local CONCAT_P     = 5
local CONCAT_C     = 6

local function concatn_gen(s, active)
	while true do
		local g = s[CONCAT_G]
		if g ~= nil then
			local c, v = g(s[CONCAT_P], s[CONCAT_C])
			if c ~= nil then
				s[CONCAT_C] = c
				return active, v
			end
			s[CONCAT_G] = nil
		end
		local i = s[CONCAT_I] + 1
		if i > s[CONCAT_N] then
			return nil
		end
		s[CONCAT_I] = i
		local trip = s[CONCAT_TRIPS][i]
		s[CONCAT_G] = trip[1]
		s[CONCAT_P] = trip[2]
		s[CONCAT_C] = trip[3]
	end
end

function pvm.concat_all(trips)
	local n = #trips
	if n == 0 then
		return pvm.empty()
	end
	if n == 1 then
		return trips[1][1], trips[1][2], trips[1][3]
	end
	if n == 2 then
		local t1, t2 = trips[1], trips[2]
		return pvm.concat2(t1[1], t1[2], t1[3], t2[1], t2[2], t2[3])
	end
	if n == 3 then
		local t1, t2, t3 = trips[1], trips[2], trips[3]
		return pvm.concat3(t1[1], t1[2], t1[3], t2[1], t2[2], t2[3], t3[1], t3[2], t3[3])
	end
	return concatn_gen, { trips, n, 0, nil, nil, nil }, true
end

-- ══════════════════════════════════════════════════════════════
--  CHILDREN — map a phase over an array of child nodes
--
--  The most common handler pattern: lower each child,
--  concatenate results.
--
--    [Widget.Row] = function(node)
--        return pvm.children(lower, node.items)
--    end
--
--  This is pull-driven: if any child hits, its seq is instant.
--  If a child misses, its recording triplet fuses with the
--  parent's recording.
--
--  For large arrays, children stay lazy: pvm does not prebuild an
--  intermediate triplet array for every child before draining.
-- ══════════════════════════════════════════════════════════════

local CHILDREN_PHASE = 1
local CHILDREN_ARRAY = 2
local CHILDREN_N     = 3
local CHILDREN_I     = 4
local CHILDREN_G     = 5
local CHILDREN_P     = 6
local CHILDREN_C     = 7

local function children_gen(s, active)
	while true do
		local g = s[CHILDREN_G]
		if g ~= nil then
			local c, v = g(s[CHILDREN_P], s[CHILDREN_C])
			if c ~= nil then
				s[CHILDREN_C] = c
				return active, v
			end
			s[CHILDREN_G] = nil
		end
		local i = s[CHILDREN_I] + 1
		if i > s[CHILDREN_N] then
			return nil
		end
		s[CHILDREN_I] = i
		local next_g, next_p, next_c = s[CHILDREN_PHASE](s[CHILDREN_ARRAY][i])
		if next_g ~= nil then
			s[CHILDREN_G] = next_g
			s[CHILDREN_P] = next_p
			s[CHILDREN_C] = next_c
		end
	end
end

function pvm.children(phase_fn, array, n)
	n = n or #array
	if n > #array then
		n = #array
	end
	if n == 0 then
		return pvm.empty()
	end
	if n == 1 then
		return phase_fn(array[1])
	end
	if n == 2 then
		local g1, p1, c1 = phase_fn(array[1])
		local g2, p2, c2 = phase_fn(array[2])
		return pvm.concat2(g1, p1, c1, g2, p2, c2)
	end
	if n == 3 then
		local g1, p1, c1 = phase_fn(array[1])
		local g2, p2, c2 = phase_fn(array[2])
		local g3, p3, c3 = phase_fn(array[3])
		return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
	end
	return children_gen, { phase_fn, array, n, 0, nil, nil, nil }, true
end

return pvm
