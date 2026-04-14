package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local Quote = require("quote")

local clock = os.clock
local fmt = string.format
local getmetatable = getmetatable
local setmetatable = setmetatable

local T = pvm.context():Define [[
    module StageBench {
        Node = Leaf(number id) unique
             | Row(StageBench.Node* children) unique
             | Clip(number tag, StageBench.Node child) unique
    }
]]

local MT_LEAF = T.StageBench.Leaf
local MT_ROW = T.StageBench.Row
local MT_CLIP = T.StageBench.Clip

local function build_tree(branch, depth, next_id)
    if depth == 0 then
        return T.StageBench.Leaf(next_id), next_id + 1
    end
    local children = {}
    for i = 1, branch do
        local child
        child, next_id = build_tree(branch, depth - 1, next_id)
        children[i] = child
    end
    return T.StageBench.Clip(depth, T.StageBench.Row(children)), next_id
end

local function build_row(n)
    local children = {}
    for i = 1, n do
        children[i] = T.StageBench.Leaf(i)
    end
    return T.StageBench.Row(children)
end

local function drain_interp(root)
    local out = {}
    local n = 0

    local function go(node)
        local mt = getmetatable(node)
        if mt == MT_LEAF then
            n = n + 1
            out[n] = node.id
        elseif mt == MT_ROW then
            local children = node.children
            for i = 1, #children do
                go(children[i])
            end
        elseif mt == MT_CLIP then
            n = n + 1
            out[n] = -node.tag
            go(node.child)
            n = n + 1
            out[n] = node.tag
        else
            error("unknown node", 2)
        end
    end

    go(root)
    return out
end

local lower_phase
lower_phase = pvm.phase("stage_bench_lower", {
    [MT_LEAF] = function(self)
        return pvm.once(self.id)
    end,
    [MT_ROW] = function(self)
        return pvm.children(lower_phase, self.children)
    end,
    [MT_CLIP] = function(self)
        local g1, p1, c1 = pvm.once(-self.tag)
        local g2, p2, c2 = lower_phase(self.child)
        local g3, p3, c3 = pvm.once(self.tag)
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,
})

local function compile_drain(root)
    local q = Quote()

    local function emit(node, indent)
        local mt = getmetatable(node)
        if mt == MT_LEAF then
            q("%sn = n + 1", indent)
            q("%sout[n] = %s", indent, tostring(node.id))
        elseif mt == MT_ROW then
            local children = node.children
            for i = 1, #children do
                emit(children[i], indent)
            end
        elseif mt == MT_CLIP then
            q("%sn = n + 1", indent)
            q("%sout[n] = -%s", indent, tostring(node.tag))
            emit(node.child, indent)
            q("%sn = n + 1", indent)
            q("%sout[n] = %s", indent, tostring(node.tag))
        else
            error("unknown node", 2)
        end
    end

    q("return function()")
    q("  local out = {}")
    q("  local n = 0")
    emit(root, "  ")
    q("  return out")
    q("end")
    return q:compile("=(experiments.pvm_shape_stage.compile)")
end

local function compile_drain_source(root)
    local q = Quote()

    local function emit(node, indent)
        local mt = getmetatable(node)
        if mt == MT_LEAF then
            q("%sn = n + 1", indent)
            q("%sout[n] = %s", indent, tostring(node.id))
        elseif mt == MT_ROW then
            local children = node.children
            for i = 1, #children do
                emit(children[i], indent)
            end
        elseif mt == MT_CLIP then
            q("%sn = n + 1", indent)
            q("%sout[n] = -%s", indent, tostring(node.tag))
            emit(node.child, indent)
            q("%sn = n + 1", indent)
            q("%sout[n] = %s", indent, tostring(node.tag))
        else
            error("unknown node", 2)
        end
    end

    q("return function()")
    q("  local out = {}")
    q("  local n = 0")
    emit(root, "  ")
    q("  return out")
    q("end")
    local _, src = q:compile("=(experiments.pvm_shape_stage.compile_source)")
    return src
end

local function sum_interp(root)
    local total = 0

    local function go(node)
        local mt = getmetatable(node)
        if mt == MT_LEAF then
            total = total + node.id
        elseif mt == MT_ROW then
            local children = node.children
            for i = 1, #children do
                go(children[i])
            end
        elseif mt == MT_CLIP then
            total = total - node.tag
            go(node.child)
            total = total + node.tag
        else
            error("unknown node", 2)
        end
    end

    go(root)
    return total
end

local function compile_sum(root)
    local q = Quote()

    local function emit(node, indent)
        local mt = getmetatable(node)
        if mt == MT_LEAF then
            q("%stotal = total + %s", indent, tostring(node.id))
        elseif mt == MT_ROW then
            local children = node.children
            for i = 1, #children do
                emit(children[i], indent)
            end
        elseif mt == MT_CLIP then
            q("%stotal = total - %s", indent, tostring(node.tag))
            emit(node.child, indent)
            q("%stotal = total + %s", indent, tostring(node.tag))
        else
            error("unknown node", 2)
        end
    end

    q("return function()")
    q("  local total = 0")
    emit(root, "  ")
    q("  return total")
    q("end")
    return q:compile("=(experiments.pvm_shape_stage.compile_sum)")
end

local function sum_array(t)
    local s = 0
    for i = 1, #t do
        s = s + t[i]
    end
    return s
end

local function bench(run, warm, reps)
    for _ = 1, warm do run() end
    collectgarbage("collect")
    local t0 = clock()
    for _ = 1, reps do run() end
    local t1 = clock()
    return (t1 - t0) * 1e6 / reps
end

local function add(acc, v)
    return acc + v
end

local function choose_reps(out_n)
    if out_n <= 32 then return 5000, 500 end
    if out_n <= 512 then return 2000, 300 end
    if out_n <= 4096 then return 500, 120 end
    return 120, 40
end

local function print_row(cols, widths)
    local out = {}
    for i = 1, #cols do
        out[i] = fmt("%-" .. widths[i] .. "s", tostring(cols[i]))
    end
    print(table.concat(out, "  "))
end

local function run_drain_case(name, root)
    local interp_out = drain_interp(root)
    local pvm_out = pvm.drain(lower_phase(root))
    local compiled = compile_drain(root)
    local compiled_out = compiled()

    assert(#interp_out == #pvm_out)
    assert(#interp_out == #compiled_out)
    assert(sum_array(interp_out) == sum_array(pvm_out))
    assert(sum_array(interp_out) == sum_array(compiled_out))

    local reps, warm = choose_reps(#interp_out)

    local interp_us = bench(function()
        local out = drain_interp(root)
        return out[1]
    end, warm, reps)

    -- pvm hot path: warm cache before timing
    pvm.drain(lower_phase(root))
    local pvm_hot_us = bench(function()
        local out = pvm.drain(lower_phase(root))
        return out[1]
    end, warm, reps)

    local compiled_us = bench(function()
        local out = compiled()
        return out[1]
    end, warm, reps)

    local compile_us = bench(function()
        local fn = compile_drain(root)
        return fn
    end, 3, math.max(10, math.floor(reps / 20)))

    return {
        name = name,
        out_n = #interp_out,
        interp_us = interp_us,
        pvm_hot_us = pvm_hot_us,
        compiled_us = compiled_us,
        compile_us = compile_us,
        speedup_vs_interp = interp_us / compiled_us,
        speedup_vs_pvm = pvm_hot_us / compiled_us,
        break_even = (interp_us > compiled_us) and (compile_us / (interp_us - compiled_us)) or math.huge,
        src_bytes = #compile_drain_source(root),
    }
end

local function run_sum_case(name, root)
    local expected = sum_interp(root)
    local compiled = compile_sum(root)
    assert(expected == compiled())
    do
        local g, p, c = lower_phase(root)
        assert(expected == pvm.fold(g, p, c, 0, add))
    end

    local out_n = #drain_interp(root)
    local reps, warm = choose_reps(out_n)

    local interp_us = bench(function()
        return sum_interp(root)
    end, warm, reps)

    pvm.drain(lower_phase(root))
    local pvm_hot_us = bench(function()
        local g, p, c = lower_phase(root)
        return pvm.fold(g, p, c, 0, add)
    end, warm, reps)

    local compiled_us = bench(function()
        return compiled()
    end, warm, reps)

    local compile_us = bench(function()
        local fn = compile_sum(root)
        return fn
    end, 3, math.max(10, math.floor(reps / 20)))

    return {
        name = name,
        out_n = out_n,
        interp_us = interp_us,
        pvm_hot_us = pvm_hot_us,
        compiled_us = compiled_us,
        compile_us = compile_us,
        speedup_vs_interp = interp_us / compiled_us,
        speedup_vs_pvm = pvm_hot_us / compiled_us,
        break_even = (interp_us > compiled_us) and (compile_us / (interp_us - compiled_us)) or math.huge,
        total = expected,
    }
end

local cases = {
    { "leaf", T.StageBench.Leaf(1) },
    { "row16", build_row(16) },
    { "tree4x4", (function() local root = build_tree(4, 4, 1); return root end)() },
    { "tree4x6", (function() local root = build_tree(4, 6, 1); return root end)() },
}

local drain_rows = {}
local sum_rows = {}
for i = 1, #cases do
    drain_rows[i] = run_drain_case(cases[i][1], cases[i][2])
    sum_rows[i] = run_sum_case(cases[i][1], cases[i][2])
end

print("pvm-shape stage microbench")
print("ASDL tree -> flat command array")
print()
print("drain terminal")
print("direct recursion vs pvm hot drain vs staged drain")
print_row(
    { "case", "out", "interp_us", "pvm_hot_us", "compiled_us", "vs_interp", "vs_pvm", "compile_us", "break_even", "src_bytes" },
    { 10, 8, 12, 12, 12, 10, 8, 12, 12, 10 }
)
print_row(
    { string.rep("-", 10), string.rep("-", 8), string.rep("-", 12), string.rep("-", 12), string.rep("-", 12), string.rep("-", 10), string.rep("-", 8), string.rep("-", 12), string.rep("-", 12), string.rep("-", 10) },
    { 10, 8, 12, 12, 12, 10, 8, 12, 12, 10 }
)
for _, row in ipairs(drain_rows) do
    print_row({
        row.name,
        row.out_n,
        fmt("%.2f", row.interp_us),
        fmt("%.2f", row.pvm_hot_us),
        fmt("%.2f", row.compiled_us),
        fmt("%.2fx", row.speedup_vs_interp),
        fmt("%.2fx", row.speedup_vs_pvm),
        fmt("%.2f", row.compile_us),
        fmt("%.2f", row.break_even),
        row.src_bytes,
    }, { 10, 8, 12, 12, 12, 10, 8, 12, 12, 10 })
end
print()
print("sum terminal")
print("direct recursion vs pvm hot fold vs staged sum")
print_row(
    { "case", "out", "interp_us", "pvm_hot_us", "compiled_us", "vs_interp", "vs_pvm", "compile_us", "break_even", "total" },
    { 10, 8, 12, 12, 12, 10, 8, 12, 12, 12 }
)
print_row(
    { string.rep("-", 10), string.rep("-", 8), string.rep("-", 12), string.rep("-", 12), string.rep("-", 12), string.rep("-", 10), string.rep("-", 8), string.rep("-", 12), string.rep("-", 12), string.rep("-", 12) },
    { 10, 8, 12, 12, 12, 10, 8, 12, 12, 12 }
)
for _, row in ipairs(sum_rows) do
    print_row({
        row.name,
        row.out_n,
        fmt("%.2f", row.interp_us),
        fmt("%.2f", row.pvm_hot_us),
        fmt("%.2f", row.compiled_us),
        fmt("%.2fx", row.speedup_vs_interp),
        fmt("%.2fx", row.speedup_vs_pvm),
        fmt("%.2f", row.compile_us),
        fmt("%.2f", row.break_even),
        row.total,
    }, { 10, 8, 12, 12, 12, 10, 8, 12, 12, 12 })
end
print()
print("note: pvm_hot_us is measured after the boundary cache is populated")
