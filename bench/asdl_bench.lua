#!/usr/bin/env luajit
-- asdl_bench.lua
--
-- Benchmark the closure-only ASDL runtime:
--   - canonical hit throughput
--   - plain constructor throughput
--   - generic wide-arity fallback throughput
--   - nested/list normalization cost
--   - retention sanity for repeated equal values

package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("pvm")
local UIT = require("ui.asdl").T

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } asdl_bench_ts;
    int clock_gettime(int, asdl_bench_ts *);
]]
local ts = ffi.new("asdl_bench_ts")
local function now()
    ffi.C.clock_gettime(1, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

local function gc_full()
    collectgarbage("collect")
    collectgarbage("collect")
end

local function bench(label, iters, fn)
    for i = 1, math.min(iters, 256) do
        fn(i)
    end
    gc_full()
    collectgarbage("stop")
    local t0 = now()
    local r
    for i = 1, iters do
        r = fn(i)
    end
    local t1 = now()
    collectgarbage("restart")
    local us = (t1 - t0) / iters * 1e6
    local value, unit
    if us < 1 then
        value, unit = us * 1000, "ns/op"
    else
        value, unit = us, "us/op"
    end
    print(string.format("  %-42s %9.3f %s", label, value, unit))
    return r, us
end

local function retention_probe(label, n, fn)
    gc_full()
    local kb0 = collectgarbage("count")
    for i = 1, n do
        fn(i)
    end
    local kb1 = collectgarbage("count")
    gc_full()
    local kb2 = collectgarbage("count")
    print(string.format(
        "  %-42s start=%8.1f KB  after=%8.1f KB  post-gc=%8.1f KB  retained=%7.1f KB",
        label, kb0, kb1, kb2, kb2 - kb0))
end

local CTX = pvm.context():Define [[
    module Bench {
        Flag = On | Off | Maybe

        Pair = (number a, number b) unique
        Quad = (number a, number b, number c, number d) unique
        Plain4 = (number a, number b, number c, number d)

        Box = (Bench.Pair pair,
               string? label,
               Bench.Flag* flags) unique

        Wide = (number a, number b, number c, number d, number e,
                number f, number g, number h, number i, number j) unique

        WidePlain = (number a, number b, number c, number d, number e,
                     number f, number g, number h, number i, number j)
    }
]]

local B = CTX.Bench
local U = UIT

local ON = B.On
local OFF = B.Off
local MAYBE = B.Maybe
local FLAGS = { ON, OFF, MAYBE }
local PAIR = B.Pair(1, 2)
local BOX = B.Box(PAIR, nil, FLAGS)

local function frame_constraint(w, h)
    return U.Facts.Constraint(U.Facts.SpanExact(w), U.Facts.SpanExact(h))
end

local HIT_N = 1024
local hit_nums = {}
local hit_labels = {}
local hit_pairs = {}
local hit_ws = {}
local hit_hs = {}
for i = 1, HIT_N do
    local x = i
    hit_nums[i] = x
    hit_labels[i] = (i % 2 == 0) and "tag" or nil
    hit_pairs[i] = B.Pair(x, x + 1)
    hit_ws[i] = 1200 + (i % 64)
    hit_hs[i] = 700 + (i % 32)
end

local function idx(i)
    return ((i - 1) % HIT_N) + 1
end

print("asdl_bench: closure-only ASDL runtime")
print("")

print("-- canonical hit throughput --")
bench("Bench.Pair unique hit", 1000000, function(i)
    local j = idx(i)
    local x = hit_nums[j]
    local obj = B.Pair(x, x + 1)
    return obj.a
end)
bench("Bench.Quad unique hit", 1000000, function(i)
    local j = idx(i)
    local x = hit_nums[j]
    local obj = B.Quad(x, x + 1, x + 2, x + 3)
    return obj.a
end)
bench("Bench.Box unique hit (nested+list)", 500000, function(i)
    local j = idx(i)
    local obj = B.Box(hit_pairs[j], hit_labels[j], FLAGS)
    return obj.pair.a
end)
bench("Bench.Wide unique hit (arity 10)", 250000, function(i)
    local j = idx(i)
    local x = hit_nums[j]
    local obj = B.Wide(x,x+1,x+2,x+3,x+4,x+5,x+6,x+7,x+8,x+9)
    return obj.a
end)
bench("UI Layout.SizePx hit", 1000000, function(i)
    local x = hit_nums[idx(i)]
    local obj = U.Layout.SizePx(x)
    return obj.px
end)
bench("UI Facts.Constraint hit", 500000, function(i)
    local j = idx(i)
    local obj = frame_constraint(hit_ws[j], hit_hs[j])
    return obj.w.px
end)
bench("pvm.with(Box, {label='x'})", 300000, function(i)
    local j = idx(i)
    local obj = pvm.with(B.Box(hit_pairs[j], nil, FLAGS), { label = "x" })
    return obj.pair.a
end)

print("")
print("-- retention sanity (same value repeated) --")
retention_probe("UI Layout.SizePx(10) repeated", 500000, function()
    return U.Layout.SizePx(10)
end)
retention_probe("UI Facts.SpanExact(1600) repeated", 500000, function()
    return U.Facts.SpanExact(1600)
end)
retention_probe("UI Facts.Constraint(1600,920) repeated", 500000, function()
    return frame_constraint(1600, 920)
end)
retention_probe("Bench.Box same value repeated", 200000, function()
    return B.Box(PAIR, nil, FLAGS)
end)

print("")
print("-- constructor throughput (fresh / non-unique / missy) --")
bench("Bench.Plain4 fresh", 1000000, function(i)
    return B.Plain4(i, i + 1, i + 2, i + 3)
end)
bench("Bench.WidePlain fresh (arity 10)", 250000, function(i)
    return B.WidePlain(i,i+1,i+2,i+3,i+4,i+5,i+6,i+7,i+8,i+9)
end)
bench("Bench.Pair unique miss wave", 200000, function(i)
    local x = i % 65521
    return B.Pair(x, x + 1)
end)
bench("Bench.Wide unique miss wave", 50000, function(i)
    local x = i % 65521
    return B.Wide(x,x+1,x+2,x+3,x+4,x+5,x+6,x+7,x+8,x+9)
end)
bench("Bench.Box unique miss wave", 100000, function(i)
    local x = i % 8191
    return B.Box(B.Pair(x, x + 1), (x % 3 == 0) and "tag" or nil, FLAGS)
end)

print("")
print("note: distinct unique values retain by design; the probes above only")
print("check that repeated equal values stay bounded.")
