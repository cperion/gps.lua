-- trace_pvm_json.lua — focused LuaJIT trace study for pvm2 vs pvm3 on JSON lowering
--
-- JsonCmd constructors are cached via unique source nodes/keys in this harness so
-- traces focus more on lowering/traversal behavior than repeated ASDL checked-ctor
-- churn.

local jit = require("jit")
jit.off()

local pvm2 = require("pvm2")
local pvm3 = require("pvm3")
local T = pvm2.T

local mode = arg[1] or "pvm3_trip_hit"
local items = tonumber(arg[2]) or 100
local iters = tonumber(arg[3]) or 40

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

local function make_document(count, salt)
    salt = salt or 0
    local shared_tags = JArr({ JStr("a_" .. salt), JStr("b_" .. salt), JStr("c_" .. salt) })
    local shared_nums = JArr({ JNum(1 + salt), JNum(2 + salt), JNum(3 + salt), JNum(4 + salt) })
    local shared_meta = JObj({
        JPair("kind", JStr("bench_" .. salt)),
        JPair("nums", shared_nums),
        JPair("ready", JBool(true)),
        JPair("none", JNull),
    })

    local pair_tags = JPair("tags", shared_tags)
    local pair_meta = JPair("meta", shared_meta)
    local pair_enabled_true = JPair("enabled", JBool(true))
    local pair_enabled_false = JPair("enabled", JBool(false))

    local arr = {}
    for i = 1, count do
        arr[i] = JObj({
            JPair("id", JNum(i + salt * 1000)),
            JPair("name", JStr("item_" .. i .. "_" .. salt)),
            JPair("score", JNum(i * 1.25 + salt)),
            pair_tags,
            pair_meta,
            (i % 2 == 0) and pair_enabled_true or pair_enabled_false,
        })
    end

    return JObj({
        JPair("items", JArr(arr)),
        JPair("meta", shared_meta),
        JPair("tags", shared_tags),
    })
end

local root = make_document(items, 0)
local variants = {}
for i = 1, iters do
    variants[i] = make_document(items, i)
end

local emit2_trip
emit2_trip = pvm2.verb_memo("trace_json_emit2_trip", {
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
emit2_flat = pvm2.verb_flat("trace_json_emit2_flat", {
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

local EMIT3_PAIR_KEY = 1
local EMIT3_PAIR_G   = 2
local EMIT3_PAIR_P   = 3
local EMIT3_PAIR_C   = 4

local function emit3_pair_gen(s, phase)
    if phase == 0 then
        return 1, CMD_KEY(s[EMIT3_PAIR_KEY])
    end
    if phase ~= 1 then
        return nil
    end
    local nc, v = s[EMIT3_PAIR_G](s[EMIT3_PAIR_P], s[EMIT3_PAIR_C])
    if nc == nil then
        return nil
    end
    s[EMIT3_PAIR_C] = nc
    return 1, v
end

local function emit3_pair(node, phase_fn)
    local g, p, c = phase_fn(node.value)
    return emit3_pair_gen, { node.key, g, p, c }, 0
end

local EMIT3_WRAP_BEGIN = 1
local EMIT3_WRAP_PHASE = 2
local EMIT3_WRAP_ARRAY = 3
local EMIT3_WRAP_N     = 4
local EMIT3_WRAP_I     = 5
local EMIT3_WRAP_G     = 6
local EMIT3_WRAP_P     = 7
local EMIT3_WRAP_C     = 8
local EMIT3_WRAP_END   = 9

local function emit3_wrap_children_gen(s, phase)
    if phase == 0 then
        return 1, s[EMIT3_WRAP_BEGIN]
    end
    if phase ~= 1 then
        return nil
    end
    while true do
        local g = s[EMIT3_WRAP_G]
        if g ~= nil then
            local c, v = g(s[EMIT3_WRAP_P], s[EMIT3_WRAP_C])
            if c ~= nil then
                s[EMIT3_WRAP_C] = c
                return 1, v
            end
            s[EMIT3_WRAP_G] = nil
        end
        local i = s[EMIT3_WRAP_I] + 1
        if i > s[EMIT3_WRAP_N] then
            return 2, s[EMIT3_WRAP_END]
        end
        s[EMIT3_WRAP_I] = i
        local next_g, next_p, next_c = s[EMIT3_WRAP_PHASE](s[EMIT3_WRAP_ARRAY][i])
        if next_g ~= nil then
            s[EMIT3_WRAP_G] = next_g
            s[EMIT3_WRAP_P] = next_p
            s[EMIT3_WRAP_C] = next_c
        end
    end
end

local function emit3_wrap_children(begin_token, phase_fn, array, end_token)
    return emit3_wrap_children_gen, { begin_token, phase_fn, array, #array, 0, nil, nil, nil, end_token }, 0
end

local emit3
emit3 = pvm3.phase("trace_json_emit3", {
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

-- Wrapped probe: same lowering semantics, but JSON pair/array/object nodes use
-- one benchmark-local generator each instead of concat2/concat3 + once/children.
-- This keeps the public pvm3 API unchanged while giving us a cleaner trace target
-- for miss-path study on this specific workload.
local emit3_wrapped
emit3_wrapped = pvm3.phase("trace_json_emit3_wrapped", {
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
        return emit3_pair(node, emit3_wrapped)
    end,
    [J.Arr] = function(node)
        return emit3_wrap_children(CMD_BEGIN_ARR, emit3_wrapped, node.items, CMD_END_ARR)
    end,
    [J.Obj] = function(node)
        return emit3_wrap_children(CMD_BEGIN_OBJ, emit3_wrapped, node.pairs, CMD_END_OBJ)
    end,
})

local function run_pvm2_trip(node)
    return T.collect(emit2_trip(node))
end

local function run_pvm2_flat(node)
    local out = {}
    emit2_flat(node, out)
    return out
end

local function run_pvm3_trip(node)
    return pvm3.drain(emit3(node))
end

local function run_pvm3_trip_wrapped(node)
    return pvm3.drain(emit3_wrapped(node))
end

local function run_pvm3_into(node)
    local g, p, c = emit3(node)
    return pvm3.drain_into(g, p, c, {})
end

collectgarbage("collect")
collectgarbage("collect")

jit.flush()
jit.on()
jit.opt.start("hotloop=3", "hotexit=2")

print(string.format("mode=%s items=%d iters=%d", mode, items, iters))

if mode == "pvm2_trip_hit" then
    emit2_trip:reset()
    run_pvm2_trip(root)
    for i = 1, iters do run_pvm2_trip(root) end
    print(pvm2.report({ emit2_trip }))
elseif mode == "pvm3_trip_hit" then
    emit3:reset()
    run_pvm3_trip(root)
    for i = 1, iters do run_pvm3_trip(root) end
    print(pvm3.report_string({ emit3 }))
elseif mode == "pvm3_trip_hit_wrapped" then
    emit3_wrapped:reset()
    run_pvm3_trip_wrapped(root)
    for i = 1, iters do run_pvm3_trip_wrapped(root) end
    print(pvm3.report_string({ emit3_wrapped }))
elseif mode == "pvm2_trip_miss" then
    emit2_trip:reset()
    for i = 1, iters do run_pvm2_trip(variants[i]) end
    print(pvm2.report({ emit2_trip }))
elseif mode == "pvm3_trip_miss" then
    emit3:reset()
    for i = 1, iters do run_pvm3_trip(variants[i]) end
    print(pvm3.report_string({ emit3 }))
elseif mode == "pvm3_trip_miss_wrapped" then
    emit3_wrapped:reset()
    for i = 1, iters do run_pvm3_trip_wrapped(variants[i]) end
    print(pvm3.report_string({ emit3_wrapped }))
elseif mode == "pvm2_flat_hit" then
    emit2_flat:reset()
    run_pvm2_flat(root)
    for i = 1, iters do run_pvm2_flat(root) end
    print(pvm2.report({ emit2_flat }))
elseif mode == "pvm3_into_hit" then
    emit3:reset()
    run_pvm3_into(root)
    for i = 1, iters do run_pvm3_into(root) end
    print(pvm3.report_string({ emit3 }))
else
    error("unknown mode: " .. tostring(mode))
end
