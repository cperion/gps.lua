-- experiments/traversal_stage.lua
--
-- Side experiment: one traversal description, two interpretations.
--
-- This is not a replacement for triplet.lua. It is a descriptive twin used to
-- explore the idea that traversal and code building are the same algebra with
-- different terminals.
--
-- Constructors build a tiny stream description:
--   seq(array)                 source
--   map(name, fn, src)         value transform
--   filter(name, pred, src)    value guard
--   concat(a, b)               append two streams
--
-- Terminals:
--   drain(desc)                interpret now
--   each(desc, sink)           interpret now
--   compile_drain(desc)        residualize a drain function via quote.lua
--   compile_each(desc, sink)   residualize an executor via quote.lua
--
-- The key point: the recursive traversal structure is primary. Runtime
-- execution and code generation are just two consumers of it.

local Quote = require("quote")

local M = {}

local function node(tag, fields)
    fields.tag = tag
    return fields
end

function M.seq(array)
    return node("seq", { array = array })
end

function M.map(name, fn, src)
    return node("map", {
        name = name or "map",
        fn = fn,
        src = src,
    })
end

function M.filter(name, pred, src)
    return node("filter", {
        name = name or "pred",
        pred = pred,
        src = src,
    })
end

function M.concat(a, b)
    return node("concat", { a = a, b = b })
end

local function walk(desc, sink)
    local tag = desc.tag
    if tag == "seq" then
        local t = desc.array
        for i = 1, #t do
            sink(t[i])
        end
    elseif tag == "map" then
        local fn = desc.fn
        walk(desc.src, function(v)
            sink(fn(v))
        end)
    elseif tag == "filter" then
        local pred = desc.pred
        walk(desc.src, function(v)
            if pred(v) then
                sink(v)
            end
        end)
    elseif tag == "concat" then
        walk(desc.a, sink)
        walk(desc.b, sink)
    else
        error("unknown traversal node: " .. tostring(tag), 2)
    end
end

function M.each(desc, sink)
    walk(desc, sink)
end

function M.drain(desc)
    local out = {}
    local n = 0
    walk(desc, function(v)
        n = n + 1
        out[n] = v
    end)
    return out
end

local function gen_node(q, desc, emit_value, indent)
    indent = indent or ""
    local tag = desc.tag

    if tag == "seq" then
        local array = q:val(desc.array, "array")
        local i = q:sym("i")
        local v = q:sym("v")
        q("%sfor %s = 1, #%s do", indent, i, array)
        q("%s  local %s = %s[%s]", indent, v, array, i)
        emit_value(v, indent .. "  ")
        q("%send", indent)
        return
    end

    if tag == "map" then
        local fn = q:val(desc.fn, desc.name or "map")
        gen_node(q, desc.src, function(v, child_indent)
            local mapped = q:sym("mapped")
            q("%slocal %s = %s(%s)", child_indent, mapped, fn, v)
            emit_value(mapped, child_indent)
        end, indent)
        return
    end

    if tag == "filter" then
        local pred = q:val(desc.pred, desc.name or "pred")
        gen_node(q, desc.src, function(v, child_indent)
            q("%sif %s(%s) then", child_indent, pred, v)
            emit_value(v, child_indent .. "  ")
            q("%send", child_indent)
        end, indent)
        return
    end

    if tag == "concat" then
        gen_node(q, desc.a, emit_value, indent)
        gen_node(q, desc.b, emit_value, indent)
        return
    end

    error("unknown traversal node: " .. tostring(tag), 2)
end

function M.compile_drain(desc)
    local q = Quote()
    q("return function()")
    q("  local out = {}")
    q("  local n = 0")
    gen_node(q, desc, function(v, indent)
        q("%sn = n + 1", indent)
        q("%sout[n] = %s", indent, v)
    end, "  ")
    q("  return out")
    q("end")
    return q:compile("=(experiments.traversal_stage.compile_drain)")
end

function M.compile_each(desc, sink)
    local q = Quote()
    local sink_name = q:val(sink, "sink")
    q("return function()")
    gen_node(q, desc, function(v, indent)
        q("%s%s(%s)", indent, sink_name, v)
    end, "  ")
    q("end")
    return q:compile("=(experiments.traversal_stage.compile_each)")
end

function M.compile_drain_source(desc)
    local q = Quote()
    q("return function()")
    q("  local out = {}")
    q("  local n = 0")
    gen_node(q, desc, function(v, indent)
        q("%sn = n + 1", indent)
        q("%sout[n] = %s", indent, v)
    end, "  ")
    q("  return out")
    q("end")
    local _, src = q:compile("=(experiments.traversal_stage.compile_drain_source)")
    return src
end

return M
