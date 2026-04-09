-- trace_pvm.lua — focused LuaJIT trace study for pvm2 vs pvm3

local jit = require("jit")
jit.off()

local pvm2 = require("pvm2")
local pvm3 = require("pvm3")
local T = pvm2.T

local mode = arg[1] or "pvm3_trip_hit"
local depth = tonumber(arg[2]) or 10
local iters = tonumber(arg[3]) or 80

local CTX = pvm3.context():Define [[
    module Ex {
        Expr = BinOp(string op, Ex.Expr lhs, Ex.Expr rhs) unique
             | Lit(number val) unique
    }
]]
local BinOp, Lit = CTX.Ex.BinOp, CTX.Ex.Lit

local function make_tree(level, seed)
    if level <= 0 then return Lit(seed) end
    return BinOp("+", make_tree(level - 1, seed), make_tree(level - 1, seed))
end

local root = make_tree(depth, 1)
local unique_roots = {}
for i = 1, iters do
    unique_roots[i] = make_tree(depth, i)
end

local emit2_trip
emit2_trip = pvm2.verb_memo("trace_emit2_trip", {
    [CTX.Ex.Lit] = function(node)
        return T.unit(tostring(node.val))
    end,
    [CTX.Ex.BinOp] = function(node)
        return pvm2.concat_all({
            { emit2_trip(node.lhs) },
            { T.unit(node.op) },
            { emit2_trip(node.rhs) },
        })
    end,
})

local emit2_flat
emit2_flat = pvm2.verb_flat("trace_emit2_flat", {
    [CTX.Ex.Lit] = function(node, out)
        out[#out + 1] = tostring(node.val)
    end,
    [CTX.Ex.BinOp] = function(node, out)
        emit2_flat(node.lhs, out)
        out[#out + 1] = node.op
        emit2_flat(node.rhs, out)
    end,
})

local emit3
emit3 = pvm3.phase("trace_emit3", {
    [CTX.Ex.Lit] = function(node)
        return pvm3.once(tostring(node.val))
    end,
    [CTX.Ex.BinOp] = function(node)
        local g1, p1, c1 = emit3(node.lhs)
        local g2, p2, c2 = pvm3.once(node.op)
        local g3, p3, c3 = emit3(node.rhs)
        return pvm3.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
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

local function run_pvm3_phase(node)
    return pvm3.drain(emit3(node))
end

local function run_pvm3_into(node)
    local g, p, c = emit3(node)
    return pvm3.drain_into(g, p, c, {})
end

local function warm_trip()
    if mode == "pvm2_trip_hit" then
        emit2_trip:reset()
        run_pvm2_trip(root)
        for i = 1, iters do run_pvm2_trip(root) end
        print(pvm2.report({ emit2_trip }))
    elseif mode == "pvm3_trip_hit" then
        emit3:reset()
        run_pvm3_phase(root)
        for i = 1, iters do run_pvm3_phase(root) end
        print(pvm3.report_string({ emit3 }))
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
        return false
    end
    return true
end

local function miss_trip()
    if mode == "pvm2_trip_miss" then
        emit2_trip:reset()
        for i = 1, iters do run_pvm2_trip(unique_roots[i]) end
        print(pvm2.report({ emit2_trip }))
    elseif mode == "pvm3_trip_miss" then
        emit3:reset()
        for i = 1, iters do run_pvm3_phase(unique_roots[i]) end
        print(pvm3.report_string({ emit3 }))
    elseif mode == "pvm2_flat_miss" then
        emit2_flat:reset()
        for i = 1, iters do run_pvm2_flat(unique_roots[i]) end
        print(pvm2.report({ emit2_flat }))
    elseif mode == "pvm3_into_miss" then
        emit3:reset()
        for i = 1, iters do run_pvm3_into(unique_roots[i]) end
        print(pvm3.report_string({ emit3 }))
    else
        return false
    end
    return true
end

collectgarbage("collect")
collectgarbage("collect")

jit.flush()
jit.on()
jit.opt.start("hotloop=3", "hotexit=2")

print(string.format("mode=%s depth=%d iters=%d", mode, depth, iters))

if not warm_trip() and not miss_trip() then
    error("unknown mode: " .. tostring(mode))
end
