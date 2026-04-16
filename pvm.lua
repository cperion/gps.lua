-- pvm.lua — the recording phase boundary
--
-- One primitive. Everything else is composition.
--
-- The insight: the memoize boundary, the fusion boundary, and
-- the machine boundary are the same thing — a recording triplet
-- keyed by canonical ASDL identity.
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
--   pvm.context()              GC-backed ASDL type system
--   pvm.with(node, overrides)  structural update preserving sharing
--   pvm.T                      triplet algebra module
--
--   pvm.phase(name, handlers)  streaming boundary (dispatch table, optional extra cache args)
--   pvm.phase(name, fn)        scalar boundary as lazy single-element stream (optional extra cache args)
--   pvm.one(g, p, c)           terminal: consume exactly one element
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

local Triplet = require("triplet")

local type = type
local rawset = rawset
local select = select
local getmetatable = getmetatable
local unpack = unpack or table.unpack

local pvm = {}
pvm.NIL = {}
local ASDL = nil

local function get_asdl()
	if ASDL ~= nil then
		return ASDL
	end
	if not package.preload["gps.asdl_lexer"] then
		package.preload["gps.asdl_lexer"] = function()
			return require("asdl_lexer")
		end
	end
	if not package.preload["gps.asdl_parser"] then
		package.preload["gps.asdl_parser"] = function()
			return require("asdl_parser")
		end
	end
	if not package.preload["gps.asdl_context"] then
		package.preload["gps.asdl_context"] = function()
			return require("asdl_context")
		end
	end
	ASDL = require("gps.asdl_context")
	return ASDL
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

function pvm.classof(node)
	if type(node) ~= "table" then
		return false
	end
	local mt = getmetatable(node)
	return (mt and mt.__class) or false
end

function pvm.with(node, overrides)
	local cls = pvm.classof(node)
	if not cls or not cls.__fields then
		error("pvm.with: not an ASDL node", 2)
	end
	return cls.__with(node, overrides, pvm.NIL)
end

local function normalize_handlers(handlers)
	local normalized = {}
	for key, fn in pairs(handlers) do
		local class = pvm.classof(key) or key
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

local REC_CACHE_PARENT = 1
local REC_PENDING_PARENT = 2
local REC_SLOT = 3
local REC_BUF = 4
local REC_N = 5
local REC_DONE = 6
local REC_G = 7
local REC_P = 8
local REC_C = 9
local REC_PACKED = 10

local function finish_recording(entry)
	if entry[REC_DONE] then
		return
	end
	entry[REC_DONE] = true
	if entry[REC_PACKED] then
		entry[REC_CACHE_PARENT][entry[REC_SLOT]] = { array = entry[REC_BUF], n = entry[REC_N] }
	else
		entry[REC_CACHE_PARENT][entry[REC_SLOT]] = entry[REC_BUF]
	end
	entry[REC_PENDING_PARENT][entry[REC_SLOT]] = nil
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
--  identity. Extra explicit arguments become additional cache-key
--  dimensions: `phase(node, max_w)` caches on `(node identity, max_w)`.
--
--  Handlers receive a node and must return a triplet (g, p, c).
--  Returning nil from a handler is an error.
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
local VALUE_ARGC = 3
local VALUE_ARGS = 4
local VALUE_READY = 5
local VALUE_DATA = 6

local PHASE_ARG_NIL = {}

local function pack_phase_args(argc, ...)
	local args = { n = argc }
	for i = 1, argc do
		args[i] = select(i, ...)
	end
	return args
end

local function phase_arg_key(args, i)
	local v = args[i]
	if v == nil then
		return PHASE_ARG_NIL
	end
	return v
end

local function lookup_phase_args(root, args, argc)
	local t = root
	for i = 1, argc do
		t = t[phase_arg_key(args, i)]
		if t == nil then
			return nil
		end
	end
	return t
end

local function ensure_phase_args_parent(root, args, argc)
	local t = root
	for i = 1, argc - 1 do
		local key = phase_arg_key(args, i)
		local child = t[key]
		if child == nil then
			child = {}
			t[key] = child
		end
		t = child
	end
	return t, phase_arg_key(args, argc)
end

local function value_once_gen(s, emitted)
	if emitted ~= 0 then
		return nil
	end
	if not s[VALUE_READY] then
		local argc = s[VALUE_ARGC]
		if argc == 0 then
			s[VALUE_DATA] = s[VALUE_FN](s[VALUE_NODE])
		elseif argc == 1 then
			s[VALUE_DATA] = s[VALUE_FN](s[VALUE_NODE], s[VALUE_ARGS][1])
		else
			s[VALUE_DATA] = s[VALUE_FN](s[VALUE_NODE], unpack(s[VALUE_ARGS], 1, argc))
		end
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

	local keyed_cache = setmetatable({}, { __mode = "k" })
	local keyed_pending = setmetatable({}, { __mode = "k" })
	local keyed_cache_args = setmetatable({}, { __mode = "k" })
	local keyed_pending_args = setmetatable({}, { __mode = "k" })
	local stats = { name = name, calls = 0, hits = 0, shared = 0 }
	local boundary = {}
	boundary.name = name

	local function resolve_node(node)
		local cls = pvm.classof(node)
		if not cls then
			error("pvm.phase '" .. name .. "': expected ASDL node", 3)
		end
		return cls, node.__cachekey or node
	end

	local function peek_cache_table(cls)
		return keyed_cache[cls]
	end

	local function peek_cache_args_table(cls)
		return keyed_cache_args[cls]
	end

	local function resolve_cache_table(cls)
		local by_key = keyed_cache[cls]
		if by_key == nil then
			by_key = setmetatable({}, { __mode = "k" })
			keyed_cache[cls] = by_key
		end
		return by_key
	end

	local function resolve_pending_table(cls)
		local by_key = keyed_pending[cls]
		if by_key == nil then
			by_key = setmetatable({}, { __mode = "k" })
			keyed_pending[cls] = by_key
		end
		return by_key
	end

	local function resolve_cache_args_table(cls)
		local by_key = keyed_cache_args[cls]
		if by_key == nil then
			by_key = setmetatable({}, { __mode = "k" })
			keyed_cache_args[cls] = by_key
		end
		return by_key
	end

	local function resolve_pending_args_table(cls)
		local by_key = keyed_pending_args[cls]
		if by_key == nil then
			by_key = setmetatable({}, { __mode = "k" })
			keyed_pending_args[cls] = by_key
		end
		return by_key
	end

	local function miss_triplet(node, cls, argc, args)
		local g, p, c
		if value_fn ~= nil then
			g, p, c = value_once_gen, { value_fn, node, argc, args, false, nil }, 0
		else
			local handler = dispatch[cls]
			if not handler then
				error("pvm.phase '" .. name .. "': no handler for " .. tostring(cls and cls.kind or type(node)), 2)
			end
			if argc == 0 then
				g, p, c = handler(node)
			elseif argc == 1 then
				g, p, c = handler(node, args[1])
			else
				g, p, c = handler(node, unpack(args, 1, argc))
			end
			if g == nil then
				error("pvm.phase '" .. name .. "': handler must return a triplet (gen, param, ctrl), got nil", 2)
			end
		end
		if type(g) ~= "function" then
			error("pvm.phase '" .. name .. "': handler must return a triplet (gen, param, ctrl), got " .. type(g), 2)
		end
		return g, p, c
	end

	local function call(_, node, ...)
		stats.calls = stats.calls + 1
		local cls, key = resolve_node(node)
		local argc = select("#", ...)

		if argc == 0 then
			local cache_t = resolve_cache_table(cls)
			local hit = cache_t[key]
			if hit ~= nil then
				stats.hits = stats.hits + 1
				if hit.array ~= nil and hit.n ~= nil then
					return seq_n_gen, hit, 0
				end
				return seq_gen, hit, 0
			end

			local pending_t = resolve_pending_table(cls)
			local inflight = pending_t[key]
			if inflight ~= nil then
				stats.shared = stats.shared + 1
				return recording_gen, inflight, 0
			end

			local g, p, c = miss_triplet(node, cls, 0, nil)
			local entry = {
				cache_t,
				pending_t,
				key,
				{},
				0,
				false,
				g,
				p,
				c,
				value_fn ~= nil,
			}
			pending_t[key] = entry
			return recording_gen, entry, 0
		end

		local args = pack_phase_args(argc, ...)
		local cache_by_key = resolve_cache_args_table(cls)
		local cache_root = cache_by_key[key]
		if cache_root ~= nil then
			local hit = lookup_phase_args(cache_root, args, argc)
			if hit ~= nil then
				stats.hits = stats.hits + 1
				if hit.array ~= nil and hit.n ~= nil then
					return seq_n_gen, hit, 0
				end
				return seq_gen, hit, 0
			end
		end

		local pending_by_key = resolve_pending_args_table(cls)
		local pending_root = pending_by_key[key]
		if pending_root ~= nil then
			local inflight = lookup_phase_args(pending_root, args, argc)
			if inflight ~= nil then
				stats.shared = stats.shared + 1
				return recording_gen, inflight, 0
			end
		end

		if cache_root == nil then
			cache_root = {}
			cache_by_key[key] = cache_root
		end
		if pending_root == nil then
			pending_root = {}
			pending_by_key[key] = pending_root
		end

		local g, p, c = miss_triplet(node, cls, argc, args)
		local cache_parent, slot = ensure_phase_args_parent(cache_root, args, argc)
		local pending_parent = ensure_phase_args_parent(pending_root, args, argc)
		local entry = {
			cache_parent,
			pending_parent,
			slot,
			{},
			0,
			false,
			g,
			p,
			c,
			value_fn ~= nil,
		}
		pending_parent[slot] = entry
		return recording_gen, entry, 0
	end

	boundary.__call = call

	if dispatch ~= nil then
		for cls, _ in pairs(dispatch) do
			rawset(cls, name, function(node, ...)
				return call(boundary, node, ...)
			end)
		end
	end

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
		keyed_cache = setmetatable({}, { __mode = "k" })
		keyed_pending = setmetatable({}, { __mode = "k" })
		keyed_cache_args = setmetatable({}, { __mode = "k" })
		keyed_pending_args = setmetatable({}, { __mode = "k" })
		stats.calls = 0
		stats.hits = 0
		stats.shared = 0
	end

	-- inspect cached output for a node without populating
	function boundary:cached(node, ...)
		local cls, key = resolve_node(node)
		local argc = select("#", ...)
		if argc == 0 then
			local cache_t = peek_cache_table(cls)
			return cache_t ~= nil and cache_t[key] or nil
		end
		local by_key = peek_cache_args_table(cls)
		if by_key == nil then
			return nil
		end
		local root = by_key[key]
		if root == nil then
			return nil
		end
		local args = pack_phase_args(argc, ...)
		return lookup_phase_args(root, args, argc)
	end

	-- force a node's cache to be populated (eager pre-compilation)
	function boundary:warm(node, ...)
		local g, p, c = call(self, node, ...)
		while true do
			c, _ = g(p, c)
			if c == nil then
				break
			end
		end
		return self:cached(node, ...)
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

local function drain_generic(g, p, c)
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

local function drain_generic_into(g, p, c, out)
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

local function each_generic(g, p, c, fn)
	while true do
		local val
		c, val = g(p, c)
		if c == nil then
			break
		end
		fn(val)
	end
end

local function fold_generic(g, p, c, acc, fn)
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
	return drain_generic(g, p, c)
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
	return drain_generic_into(g, p, c, out)
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
		for i = c + 1, #p do
			fn(p[i])
		end
		return
	end
	if g == seq_n_gen then
		for i = c + 1, p.n do
			fn(p.array[i])
		end
		return
	end
	if g == recording_gen then
		for i = c + 1, p[REC_N] do
			fn(p[REC_BUF][i])
		end
		while advance_recording(p) do
			fn(p[REC_BUF][p[REC_N]])
		end
		return
	end
	each_generic(g, p, c, fn)
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
		for i = c + 1, #p do
			acc = fn(acc, p[i])
		end
		return acc
	end
	if g == seq_n_gen then
		for i = c + 1, p.n do
			acc = fn(acc, p.array[i])
		end
		return acc
	end
	if g == recording_gen then
		for i = c + 1, p[REC_N] do
			acc = fn(acc, p[REC_BUF][i])
		end
		while advance_recording(p) do
			acc = fn(acc, p[REC_BUF][p[REC_N]])
		end
		return acc
	end
	return fold_generic(g, p, c, acc, fn)
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
		lines[i] = string.format(
			"  %-24s calls=%-6d hits=%-6d shared=%-6d reuse=%.1f%%",
			r.name,
			r.calls,
			r.hits,
			r.shared,
			r.reuse_ratio * 100
		)
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

local function seq_rev_gen(a, i)
	i = i - 1
	if i < 1 then
		return nil
	end
	return i, a[i]
end

function pvm.seq_rev(array, n)
	n = n or #array
	if n > #array then
		n = #array
	end
	return seq_rev_gen, array, n + 1
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
local CONCAT_N = 2
local CONCAT_I = 3
local CONCAT_G = 4
local CONCAT_P = 5
local CONCAT_C = 6

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
local CHILDREN_N = 3
local CHILDREN_I = 4
local CHILDREN_G = 5
local CHILDREN_P = 6
local CHILDREN_C = 7

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
