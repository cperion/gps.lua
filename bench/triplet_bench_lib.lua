package.path = "./?.lua;./?/init.lua;" .. package.path

local M = {}

local function load_impl(which)
    if which == "new" then
        return dofile("./triplet.lua")
    elseif which == "old" then
        return dofile("./triplet_old.lua")
    else
        error("unknown triplet impl: " .. tostring(which), 2)
    end
end

M.load_impl = load_impl

local function make_array(n)
    local t = {}
    for i = 1, n do
        t[i] = i
    end
    return t
end

local function make_letters(n)
    local t = {}
    for i = 1, n do
        t[i] = string.char(97 + ((i - 1) % 26))
    end
    return t
end

local function sum_numeric(g, p, c)
    local acc = 0
    while true do
        local nc, v = g(p, c)
        if nc == nil then
            return acc
        end
        c = nc
        acc = acc + v
    end
end

local function sum_zip(g, p, c)
    local acc = 0
    while true do
        local nc, a, b = g(p, c)
        if nc == nil then
            return acc
        end
        c = nc
        acc = acc + a + b
    end
end

local function sum_enum_pairs(g, p, c)
    local acc = 0
    while true do
        local nc, pair = g(p, c)
        if nc == nil then
            return acc
        end
        c = nc
        acc = acc + pair[1] + #pair[2]
    end
end

local function sum_chunks(g, p, c)
    local acc = 0
    while true do
        local nc, chunk = g(p, c)
        if nc == nil then
            return acc
        end
        c = nc
        for i = 1, #chunk do
            acc = acc + chunk[i]
        end
    end
end

local function sum_windows(g, p, c)
    local acc = 0
    while true do
        local nc, win = g(p, c)
        if nc == nil then
            return acc
        end
        c = nc
        for i = 1, #win do
            acc = acc + win[i]
        end
    end
end

local function sum_partial_numeric(g, p, c, limit)
    local acc = 0
    for _ = 1, limit do
        local nc, v = g(p, c)
        if nc == nil then
            return acc
        end
        c = nc
        acc = acc + v
    end
    return acc
end

local function sum_tee_balanced(copies)
    local g1, p1, c1 = copies[1][1], copies[1][2], copies[1][3]
    local g2, p2, c2 = copies[2][1], copies[2][2], copies[2][3]
    local acc = 0

    while true do
        local nc1, v1 = g1(p1, c1)
        local nc2, v2 = g2(p2, c2)
        if nc1 == nil then
            if nc2 ~= nil then
                error("tee balanced: branch 2 still had data after branch 1 ended")
            end
            return acc
        end
        if nc2 == nil then
            error("tee balanced: branch 1 still had data after branch 2 ended")
        end
        c1 = nc1
        c2 = nc2
        acc = acc + v1 + v2
    end
end

local function sum_tee_skewed(copies)
    local g1, p1, c1 = copies[1][1], copies[1][2], copies[1][3]
    local g2, p2, c2 = copies[2][1], copies[2][2], copies[2][3]
    local acc = 0

    while true do
        local nc, v = g1(p1, c1)
        if nc == nil then
            break
        end
        c1 = nc
        acc = acc + v
    end

    while true do
        local nc, v = g2(p2, c2)
        if nc == nil then
            break
        end
        c2 = nc
        acc = acc + v
    end

    return acc
end

local function mf_map1(x)
    return x + 3
end

local function mf_pred(x)
    return x % 3 ~= 0
end

local function mf_map2(x)
    return x * 2
end

local function scan_add(acc, v)
    return acc + v
end

local function zip_add(a, b)
    return a + b
end

local function less_than_100(x)
    return x < 100
end

local function flatmap_two(T, x)
    local g1, p1, c1 = T.unit(x)
    local g2, p2, c2 = T.unit(x + 1)
    return T.concat(g1, p1, c1, g2, p2, c2)
end

local scenarios = {}
local scenario_order = {
    "construct_map_filter",
    "drain_map_filter",
    "partial_map_filter",
    "drain_drop_scan",
    "drain_zip_with",
    "drain_flatmap",
    "drain_interleave",
    "drain_tee_balanced",
    "drain_tee_skewed",
    "drain_chunk",
    "drain_window",
    "drain_enumerate",
}

scenarios.construct_map_filter = {
    label = "construct map/filter chain",
    compare_checksum = false,
    default_n = 100000,
    default_iters = 200000,
    units_label = "chains",
    units_per_run = function() return 1 end,
    prepare = function(n)
        return { values = make_array(n) }
    end,
    run_once = function(T, payload)
        local g, p, c = T.seq(payload.values)
        g, p, c = T.map(mf_map1, g, p, c)
        g, p, c = T.filter(mf_pred, g, p, c)
        g, p, c = T.map(mf_map2, g, p, c)
        local acc = 0
        if type(g) == "function" then acc = acc + 1 end
        if type(p) == "table" then acc = acc + #p end
        if type(c) == "number" then acc = acc + c end
        if type(c) == "boolean" and c then acc = acc + 1 end
        return acc
    end,
}

scenarios.drain_map_filter = {
    label = "full drain: seq -> map -> filter -> map",
    default_n = 100000,
    default_iters = 200,
    units_label = "input elems",
    units_per_run = function(n) return n end,
    prepare = function(n)
        return { values = make_array(n) }
    end,
    run_once = function(T, payload)
        local g, p, c = T.seq(payload.values)
        g, p, c = T.map(mf_map1, g, p, c)
        g, p, c = T.filter(mf_pred, g, p, c)
        g, p, c = T.map(mf_map2, g, p, c)
        return sum_numeric(g, p, c)
    end,
}

scenarios.partial_map_filter = {
    label = "partial drain: first k of map/filter chain",
    default_n = 100000,
    default_iters = 50000,
    default_partial = 32,
    units_label = "pulled elems",
    units_per_run = function(_, partial) return partial end,
    prepare = function(n, partial)
        return { values = make_array(n), partial = partial }
    end,
    run_once = function(T, payload)
        local g, p, c = T.seq(payload.values)
        g, p, c = T.map(mf_map1, g, p, c)
        g, p, c = T.filter(mf_pred, g, p, c)
        g, p, c = T.map(mf_map2, g, p, c)
        return sum_partial_numeric(g, p, c, payload.partial)
    end,
}

scenarios.drain_drop_scan = {
    label = "full drain: drop -> drop_while -> scan",
    default_n = 100000,
    default_iters = 200,
    units_label = "input elems",
    units_per_run = function(n) return n end,
    prepare = function(n)
        return { values = make_array(n) }
    end,
    run_once = function(T, payload)
        local g, p, c = T.seq(payload.values)
        g, p, c = T.drop(5, g, p, c)
        g, p, c = T.drop_while(less_than_100, g, p, c)
        g, p, c = T.scan(scan_add, 0, g, p, c)
        return sum_numeric(g, p, c)
    end,
}

scenarios.drain_zip_with = {
    label = "full drain: zip_with over two arrays",
    default_n = 100000,
    default_iters = 200,
    units_label = "zipped elems",
    units_per_run = function(n) return n end,
    prepare = function(n)
        return { a = make_array(n), b = make_array(n) }
    end,
    run_once = function(T, payload)
        local g1, p1, c1 = T.seq(payload.a)
        local g2, p2, c2 = T.seq(payload.b)
        local g, p, c = T.zip_with(zip_add, g1, p1, c1, g2, p2, c2)
        return sum_numeric(g, p, c)
    end,
}

scenarios.drain_flatmap = {
    label = "full drain: flatmap x -> [x, x+1]",
    default_n = 50000,
    default_iters = 200,
    units_label = "output elems",
    units_per_run = function(n) return n * 2 end,
    prepare = function(n)
        return { values = make_array(n) }
    end,
    run_once = function(T, payload)
        local g, p, c = T.seq(payload.values)
        g, p, c = T.flatmap(function(x) return flatmap_two(T, x) end, g, p, c)
        return sum_numeric(g, p, c)
    end,
}

scenarios.drain_interleave = {
    label = "full drain: interleave two arrays",
    default_n = 100000,
    default_iters = 200,
    units_label = "output elems",
    units_per_run = function(n) return n * 2 end,
    prepare = function(n)
        return { a = make_array(n), b = make_array(n) }
    end,
    run_once = function(T, payload)
        local g1, p1, c1 = T.seq(payload.a)
        local g2, p2, c2 = T.seq(payload.b)
        local g, p, c = T.interleave(g1, p1, c1, g2, p2, c2)
        return sum_numeric(g, p, c)
    end,
}

scenarios.drain_tee_balanced = {
    label = "full drain: tee(2) balanced consumption",
    default_n = 50000,
    default_iters = 200,
    units_label = "output elems",
    units_per_run = function(n) return n * 2 end,
    prepare = function(n)
        return { values = make_array(n) }
    end,
    run_once = function(T, payload)
        local copies = T.tee(2, T.seq(payload.values))
        return sum_tee_balanced(copies)
    end,
}

scenarios.drain_tee_skewed = {
    label = "full drain: tee(2) skewed consumption",
    default_n = 50000,
    default_iters = 200,
    units_label = "output elems",
    units_per_run = function(n) return n * 2 end,
    prepare = function(n)
        return { values = make_array(n) }
    end,
    run_once = function(T, payload)
        local copies = T.tee(2, T.seq(payload.values))
        return sum_tee_skewed(copies)
    end,
}

scenarios.drain_chunk = {
    label = "full drain: chunk(8)",
    default_n = 100000,
    default_iters = 100,
    units_label = "input elems",
    units_per_run = function(n) return n end,
    prepare = function(n)
        return { values = make_array(n) }
    end,
    run_once = function(T, payload)
        local g, p, c = T.chunk(8, T.seq(payload.values))
        return sum_chunks(g, p, c)
    end,
}

scenarios.drain_window = {
    label = "full drain: window(8)",
    default_n = 30000,
    default_iters = 60,
    units_label = "windows",
    units_per_run = function(n) return n - 7 end,
    prepare = function(n)
        return { values = make_array(n) }
    end,
    run_once = function(T, payload)
        local g, p, c = T.window(8, T.seq(payload.values))
        return sum_windows(g, p, c)
    end,
}

scenarios.drain_enumerate = {
    label = "full drain: enumerate(chars)",
    default_n = 100000,
    default_iters = 150,
    units_label = "pairs",
    units_per_run = function(n) return n end,
    prepare = function(n)
        return { values = make_letters(n) }
    end,
    run_once = function(T, payload)
        local g, p, c = T.seq(payload.values)
        g, p, c = T.enumerate(g, p, c)
        return sum_enum_pairs(g, p, c)
    end,
}

M.scenarios = scenarios
M.scenario_order = scenario_order

function M.get_scenario(name)
    local s = scenarios[name]
    if not s then
        error("unknown scenario: " .. tostring(name), 2)
    end
    return s
end

function M.prepare(name, n, partial)
    local scenario = M.get_scenario(name)
    return scenario.prepare(n or scenario.default_n, partial or scenario.default_partial)
end

function M.run_once(T, name, payload)
    return M.get_scenario(name).run_once(T, payload)
end

function M.units_per_run(name, n, partial)
    local scenario = M.get_scenario(name)
    return scenario.units_per_run(n or scenario.default_n, partial or scenario.default_partial)
end

function M.default_n(name)
    return M.get_scenario(name).default_n
end

function M.default_iters(name)
    return M.get_scenario(name).default_iters
end

function M.default_partial(name)
    return M.get_scenario(name).default_partial
end

return M
