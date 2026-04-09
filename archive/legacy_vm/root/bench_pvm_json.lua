-- bench_pvm_json.lua — pvm2 vs pvm3 on a JSON ASDL lowering benchmark
--
-- Domain:
--   Json.Value tree  ->  flat JsonCmd event stream
--
-- This is not a byte-parse benchmark. It isolates the pvm2/pvm3 lowering layer
-- over an interned JSON ASDL graph with realistic list fanout and shared subtrees.
--
-- JsonCmd constructors are cached via unique source nodes/keys inside the harness
-- so the benchmark measures lowering/traversal behavior more than repeated ASDL
-- checked-ctor work.
--
-- Variants:
--   1) canonical triplet path: pvm2.verb_memo vs pvm3.phase + drain
--   2) append sink terminal:   pvm2.verb_flat vs pvm3.phase + drain_into
--   3) cached root artifact:   pvm2.verb_flat + lower vs pvm3.phase + lower

local pvm2 = require("pvm2")
local pvm3 = require("pvm3")
local T = pvm2.T

-- ══════════════════════════════════════════════════════════════
--  ASDL
-- ══════════════════════════════════════════════════════════════

local CTX = pvm3.context():Define [[
    module Json {
        Value = Str(string value) unique
              | Num(number value) unique
              | Bool(boolean value) unique
              | Null
              | Arr(Json.Value* items) unique
              | Obj(Json.Pair* pairs) unique
        Pair = (string key, Json.Value value) unique
    }
    module JsonCmd {
        Kind = BeginObj | EndObj | BeginArr | EndArr
             | Key | Str | Num | Bool | Null
        Cmd = (JsonCmd.Kind kind, string sval, number nval) unique
    }
]]

local J = CTX.Json
local C = CTX.JsonCmd

local JStr, JNum, JBool, JNull, JArr, JObj, JPair =
    J.Str, J.Num, J.Bool, J.Null, J.Arr, J.Obj, J.Pair

local Cmd = C.Cmd
local CK_BEGIN_OBJ = C.BeginObj
local CK_END_OBJ   = C.EndObj
local CK_BEGIN_ARR = C.BeginArr
local CK_END_ARR   = C.EndArr
local CK_KEY       = C.Key
local CK_STR       = C.Str
local CK_NUM       = C.Num
local CK_BOOL      = C.Bool
local CK_NULL      = C.Null

local CMD_BEGIN_OBJ = Cmd(CK_BEGIN_OBJ, "", 0)
local CMD_END_OBJ   = Cmd(CK_END_OBJ,   "", 0)
local CMD_BEGIN_ARR = Cmd(CK_BEGIN_ARR, "", 0)
local CMD_END_ARR   = Cmd(CK_END_ARR,   "", 0)
local CMD_NULL      = Cmd(CK_NULL,      "", 0)
local CMD_TRUE      = Cmd(CK_BOOL,      "", 1)
local CMD_FALSE     = Cmd(CK_BOOL,      "", 0)

local key_cmd_cache = {}
-- J.Str/J.Num nodes are unique, so weak node-keyed caches act like value caches
-- without putting heterogeneous numeric keys in one hot table.
local str_cmd_cache = setmetatable({}, { __mode = "k" })
local num_cmd_cache = setmetatable({}, { __mode = "k" })

local function CMD_KEY(key)
    local cmd = key_cmd_cache[key]
    if cmd == nil then
        cmd = Cmd(CK_KEY, key, 0)
        key_cmd_cache[key] = cmd
    end
    return cmd
end

local function CMD_STR_NODE(node)
    local cmd = str_cmd_cache[node]
    if cmd == nil then
        cmd = Cmd(CK_STR, node.value, 0)
        str_cmd_cache[node] = cmd
    end
    return cmd
end

local function CMD_NUM_NODE(node)
    local cmd = num_cmd_cache[node]
    if cmd == nil then
        cmd = Cmd(CK_NUM, "", node.value)
        num_cmd_cache[node] = cmd
    end
    return cmd
end

-- ══════════════════════════════════════════════════════════════
--  JSON graph generator
-- ══════════════════════════════════════════════════════════════

local function make_document(count)
    local shared_tags = JArr({ JStr("a"), JStr("b"), JStr("c") })
    local shared_nums = JArr({ JNum(1), JNum(2), JNum(3), JNum(4) })
    local shared_meta = JObj({
        JPair("kind", JStr("bench")),
        JPair("nums", shared_nums),
        JPair("ready", JBool(true)),
        JPair("none", JNull),
    })

    local pair_tags = JPair("tags", shared_tags)
    local pair_meta = JPair("meta", shared_meta)
    local pair_enabled_true = JPair("enabled", JBool(true))
    local pair_enabled_false = JPair("enabled", JBool(false))

    local items = {}
    for i = 1, count do
        items[i] = JObj({
            JPair("id", JNum(i)),
            JPair("name", JStr("item_" .. i)),
            JPair("score", JNum(i * 1.25)),
            pair_tags,
            pair_meta,
            (i % 2 == 0) and pair_enabled_true or pair_enabled_false,
        })
    end

    return JObj({
        JPair("items", JArr(items)),
        JPair("meta", shared_meta),
        JPair("tags", shared_tags),
    })
end

local function update_item_name(doc, index, suffix)
    local root_pairs = doc.pairs
    local items_pair = root_pairs[1]
    local items_arr = items_pair.value

    local items = items_arr.items
    local new_items = {}
    for i = 1, #items do new_items[i] = items[i] end

    local item = items[index]
    local pairs = item.pairs
    local new_pairs = {}
    for i = 1, #pairs do new_pairs[i] = pairs[i] end

    new_pairs[2] = pvm3.with(pairs[2], { value = JStr("item_" .. index .. suffix) })
    new_items[index] = pvm3.with(item, { pairs = new_pairs })

    local new_items_arr = pvm3.with(items_arr, { items = new_items })
    local new_root_pairs = {}
    for i = 1, #root_pairs do new_root_pairs[i] = root_pairs[i] end
    new_root_pairs[1] = pvm3.with(items_pair, { value = new_items_arr })

    return pvm3.with(doc, { pairs = new_root_pairs })
end

-- ══════════════════════════════════════════════════════════════
--  Handwritten baseline
-- ══════════════════════════════════════════════════════════════

local function emit_handwritten(root)
    local out, n = {}, 0

    local function emit(node)
        local kind = node.kind
        if kind == "Str" then
            n = n + 1; out[n] = CMD_STR_NODE(node)
        elseif kind == "Num" then
            n = n + 1; out[n] = CMD_NUM_NODE(node)
        elseif kind == "Bool" then
            n = n + 1; out[n] = node.value and CMD_TRUE or CMD_FALSE
        elseif kind == "Null" then
            n = n + 1; out[n] = CMD_NULL
        elseif kind == "Arr" then
            n = n + 1; out[n] = CMD_BEGIN_ARR
            local items = node.items
            for i = 1, #items do emit(items[i]) end
            n = n + 1; out[n] = CMD_END_ARR
        elseif kind == "Obj" then
            n = n + 1; out[n] = CMD_BEGIN_OBJ
            local pairs = node.pairs
            for i = 1, #pairs do
                local pair = pairs[i]
                n = n + 1; out[n] = CMD_KEY(pair.key)
                emit(pair.value)
            end
            n = n + 1; out[n] = CMD_END_OBJ
        elseif kind == "Pair" then
            n = n + 1; out[n] = CMD_KEY(node.key)
            emit(node.value)
        else
            error("unexpected json node kind: " .. tostring(kind))
        end
    end

    emit(root)
    return out
end

-- ══════════════════════════════════════════════════════════════
--  pvm2 variants
-- ══════════════════════════════════════════════════════════════

local emit2_trip
emit2_trip = pvm2.verb_memo("emit2_json_trip", {
    [J.Str] = function(node)
        return T.unit(CMD_STR_NODE(node))
    end,
    [J.Num] = function(node)
        return T.unit(CMD_NUM_NODE(node))
    end,
    [J.Bool] = function(node)
        return T.unit(node.value and CMD_TRUE or CMD_FALSE)
    end,
    [J.Null] = function()
        return T.unit(CMD_NULL)
    end,
    [J.Pair] = function(node)
        return pvm2.concat_all({
            { T.unit(CMD_KEY(node.key)) },
            { emit2_trip(node.value) },
        })
    end,
    [J.Arr] = function(node)
        local parts = { { T.unit(CMD_BEGIN_ARR) } }
        for i = 1, #node.items do
            parts[#parts + 1] = { emit2_trip(node.items[i]) }
        end
        parts[#parts + 1] = { T.unit(CMD_END_ARR) }
        return pvm2.concat_all(parts)
    end,
    [J.Obj] = function(node)
        local parts = { { T.unit(CMD_BEGIN_OBJ) } }
        for i = 1, #node.pairs do
            parts[#parts + 1] = { emit2_trip(node.pairs[i]) }
        end
        parts[#parts + 1] = { T.unit(CMD_END_OBJ) }
        return pvm2.concat_all(parts)
    end,
})

local emit2_flat
emit2_flat = pvm2.verb_flat("emit2_json_flat", {
    [J.Str] = function(node, out)
        out[#out + 1] = CMD_STR_NODE(node)
    end,
    [J.Num] = function(node, out)
        out[#out + 1] = CMD_NUM_NODE(node)
    end,
    [J.Bool] = function(node, out)
        out[#out + 1] = node.value and CMD_TRUE or CMD_FALSE
    end,
    [J.Null] = function(_, out)
        out[#out + 1] = CMD_NULL
    end,
    [J.Pair] = function(node, out)
        out[#out + 1] = CMD_KEY(node.key)
        emit2_flat(node.value, out)
    end,
    [J.Arr] = function(node, out)
        out[#out + 1] = CMD_BEGIN_ARR
        local items = node.items
        for i = 1, #items do emit2_flat(items[i], out) end
        out[#out + 1] = CMD_END_ARR
    end,
    [J.Obj] = function(node, out)
        out[#out + 1] = CMD_BEGIN_OBJ
        local pairs = node.pairs
        for i = 1, #pairs do emit2_flat(pairs[i], out) end
        out[#out + 1] = CMD_END_OBJ
    end,
})

local compile2 = pvm2.lower("compile_json2", function(root)
    local out = {}
    emit2_flat(root, out)
    return out
end)

local function run_pvm2_trip(root)
    return T.collect(emit2_trip(root))
end

local function run_pvm2_flat(root)
    local out = {}
    emit2_flat(root, out)
    return out
end

local function run_pvm2_lower(root)
    return compile2(root)
end

-- ══════════════════════════════════════════════════════════════
--  pvm3 variants
-- ══════════════════════════════════════════════════════════════

local emit3
emit3 = pvm3.phase("emit3_json", {
    [J.Str] = function(node)
        return pvm3.once(CMD_STR_NODE(node))
    end,
    [J.Num] = function(node)
        return pvm3.once(CMD_NUM_NODE(node))
    end,
    [J.Bool] = function(node)
        return pvm3.once(node.value and CMD_TRUE or CMD_FALSE)
    end,
    [J.Null] = function()
        return pvm3.once(CMD_NULL)
    end,
    [J.Pair] = function(node)
        local g1, p1, c1 = pvm3.once(CMD_KEY(node.key))
        local g2, p2, c2 = emit3(node.value)
        return pvm3.concat2(g1, p1, c1, g2, p2, c2)
    end,
    [J.Arr] = function(node)
        local g1, p1, c1 = pvm3.once(CMD_BEGIN_ARR)
        local g2, p2, c2 = pvm3.children(emit3, node.items)
        local g3, p3, c3 = pvm3.once(CMD_END_ARR)
        return pvm3.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,
    [J.Obj] = function(node)
        local g1, p1, c1 = pvm3.once(CMD_BEGIN_OBJ)
        local g2, p2, c2 = pvm3.children(emit3, node.pairs)
        local g3, p3, c3 = pvm3.once(CMD_END_OBJ)
        return pvm3.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,
})

local compile3 = pvm3.lower("compile_json3", function(root)
    return pvm3.drain(emit3(root))
end)

local function run_pvm3_trip(root)
    return pvm3.drain(emit3(root))
end

local function run_pvm3_into(root)
    local g, p, c = emit3(root)
    return pvm3.drain_into(g, p, c, {})
end

local function run_pvm3_lower(root)
    return compile3(root)
end

-- ══════════════════════════════════════════════════════════════
--  Harness
-- ══════════════════════════════════════════════════════════════

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function bench(fn, root, iters)
    for i = 1, math.min(iters, 40) do fn(root) end
    local t0 = os.clock()
    local result
    for i = 1, iters do result = fn(root) end
    return (os.clock() - t0) / iters * 1e6, result
end

local function bench_pair(setup_fn, run_fn, root1, root2, iters)
    for i = 1, math.min(iters, 20) do
        setup_fn()
        run_fn(root1)
        run_fn(root2)
    end
    local t0 = os.clock()
    for i = 1, iters do
        setup_fn()
        run_fn(root1)
        run_fn(root2)
    end
    return (os.clock() - t0) / iters * 1e6
end

local function fmt(us)
    return string.format("%8.1f µs", us)
end

local function row(label, us, ref)
    local ratio = ref and string.format("  (%4.2fx hand)", us / ref) or ""
    print(string.format("  %-32s %s%s", label, fmt(us), ratio))
end

-- ══════════════════════════════════════════════════════════════
--  Run
-- ══════════════════════════════════════════════════════════════

for _, count in ipairs({ 20, 100, 300 }) do
    local root = make_document(count)
    local changed = update_item_name(root, math.max(1, math.floor(count / 2)), "_edit")

    emit2_trip:reset(); emit2_flat:reset(); compile2:reset(); emit3:reset(); compile3:reset()

    local hand = emit_handwritten(root)
    local r2t = run_pvm2_trip(root)
    local r2f = run_pvm2_flat(root)
    local r2l = run_pvm2_lower(root)
    local r3t = run_pvm3_trip(root)
    local r3i = run_pvm3_into(root)
    local r3l = run_pvm3_lower(root)

    assert(same(hand, r2t), "pvm2 trip mismatch")
    assert(same(hand, r2f), "pvm2 flat mismatch")
    assert(same(hand, r2l), "pvm2 lower mismatch")
    assert(same(hand, r3t), "pvm3 trip mismatch")
    assert(same(hand, r3i), "pvm3 into mismatch")
    assert(same(hand, r3l), "pvm3 lower mismatch")

    local N = math.max(40, math.floor(30000 / #hand))

    print(string.format("\n═══ items=%d  commands=%d  iters=%d ═══", count, #hand, N))

    local hand_cold = bench(emit_handwritten, root, N)

    local cold_p2_trip = bench(function(x)
        emit2_trip:reset()
        return run_pvm2_trip(x)
    end, root, N)

    local cold_p3_trip = bench(function(x)
        emit3:reset()
        return run_pvm3_trip(x)
    end, root, N)

    local cold_p2_flat = bench(function(x)
        emit2_flat:reset()
        return run_pvm2_flat(x)
    end, root, N)

    local cold_p3_into = bench(function(x)
        emit3:reset()
        return run_pvm3_into(x)
    end, root, N)

    local cold_p2_lower = bench(function(x)
        emit2_flat:reset(); compile2:reset()
        return run_pvm2_lower(x)
    end, root, N)

    local cold_p3_lower = bench(function(x)
        emit3:reset(); compile3:reset()
        return run_pvm3_lower(x)
    end, root, N)

    emit2_trip:reset(); run_pvm2_trip(root)
    local warm_p2_trip = bench(run_pvm2_trip, root, N)

    emit3:reset(); run_pvm3_trip(root)
    local warm_p3_trip = bench(run_pvm3_trip, root, N)

    emit2_flat:reset(); run_pvm2_flat(root)
    local warm_p2_flat = bench(run_pvm2_flat, root, N)

    emit3:reset(); run_pvm3_into(root)
    local warm_p3_into = bench(run_pvm3_into, root, N)

    emit2_flat:reset(); compile2:reset(); run_pvm2_lower(root)
    local warm_p2_lower = bench(run_pvm2_lower, root, N)

    emit3:reset(); compile3:reset(); run_pvm3_lower(root)
    local warm_p3_lower = bench(run_pvm3_lower, root, N)

    local inc_p2_trip = bench_pair(function() emit2_trip:reset() end, run_pvm2_trip, root, changed, N)
    local inc_p3_trip = bench_pair(function() emit3:reset() end, run_pvm3_trip, root, changed, N)
    local inc_p2_flat = bench_pair(function() emit2_flat:reset() end, run_pvm2_flat, root, changed, N)
    local inc_p3_into = bench_pair(function() emit3:reset() end, run_pvm3_into, root, changed, N)
    local inc_p2_lower = bench_pair(function() emit2_flat:reset(); compile2:reset() end, run_pvm2_lower, root, changed, N)
    local inc_p3_lower = bench_pair(function() emit3:reset(); compile3:reset() end, run_pvm3_lower, root, changed, N)

    print("  cold")
    row("handwritten", hand_cold)
    row("pvm2 verb_memo + collect", cold_p2_trip, hand_cold)
    row("pvm3 phase + drain", cold_p3_trip, hand_cold)
    row("pvm2 verb_flat", cold_p2_flat, hand_cold)
    row("pvm3 phase + drain_into", cold_p3_into, hand_cold)
    row("pvm2 verb_flat + lower", cold_p2_lower, hand_cold)
    row("pvm3 phase + lower", cold_p3_lower, hand_cold)

    print("  warm")
    row("pvm2 verb_memo + collect", warm_p2_trip, hand_cold)
    row("pvm3 phase + drain", warm_p3_trip, hand_cold)
    row("pvm2 verb_flat", warm_p2_flat, hand_cold)
    row("pvm3 phase + drain_into", warm_p3_into, hand_cold)
    row("pvm2 verb_flat + lower", warm_p2_lower, hand_cold)
    row("pvm3 phase + lower", warm_p3_lower, hand_cold)

    print("  incremental (root -> one edited item, per pair)")
    row("pvm2 verb_memo + collect", inc_p2_trip, hand_cold)
    row("pvm3 phase + drain", inc_p3_trip, hand_cold)
    row("pvm2 verb_flat", inc_p2_flat, hand_cold)
    row("pvm3 phase + drain_into", inc_p3_into, hand_cold)
    row("pvm2 verb_flat + lower", inc_p2_lower, hand_cold)
    row("pvm3 phase + lower", inc_p3_lower, hand_cold)
end

print("\n═══ Cache quality snapshot (items=100, edit one item name) ═══")
local root = make_document(100)
local changed = update_item_name(root, 50, "_edit")

emit2_trip:reset()
run_pvm2_trip(root)
run_pvm2_trip(changed)
print("\npvm2 triplet boundary:")
print(pvm2.report({ emit2_trip }))

emit2_flat:reset(); compile2:reset()
run_pvm2_lower(root)
run_pvm2_lower(changed)
print("\npvm2 flat+lower:")
print(pvm2.report({ emit2_flat, compile2 }))

emit3:reset()
run_pvm3_trip(root)
run_pvm3_trip(changed)
print("\npvm3 phase:")
print(pvm3.report_string({ emit3 }))

emit3:reset(); compile3:reset()
run_pvm3_lower(root)
run_pvm3_lower(changed)
print("\npvm3 phase+lower:")
print(pvm3.report_string({ emit3, compile3 }))
