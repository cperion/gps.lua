package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local aj = require("asdljit")

local schema = aj.compile([[
module Bench {
    Polyline = (i32* coords) unique
    Shape = Path(i32* coords) unique
}
]], {
    type_map = {
        i32 = wj.i32,
    },
})

local coords_rt = schema:list_runtime("i32", {
    capacity = 32,
    elem_capacity = 256,
    scratch_capacity = 32,
    name = "Bench_i32_List",
})

local l1 = coords_rt:new({ 1, 2, 3, 4 })
local l2 = coords_rt:new({ 1, 2, 3, 4 })
local l3 = coords_rt:new({ 1, 2, 3, 5 })
local l4 = coords_rt:new({})
local l5 = coords_rt:new({})

assert(l1 == l2)
assert(l3 ~= l1)
assert(l4 == l5)
assert(coords_rt:handle_count() == 3)

local values = coords_rt:get(l1)
assert(#values == 4)
assert(values[1] == 1)
assert(values[4] == 4)
assert(#coords_rt:raw(l4) == 0)

local Polyline = schema.Bench.Polyline
local Path = schema.Bench.Path

local polys = Polyline:runtime {
    capacity = 32,
    list_runtimes = {
        coords = coords_rt,
    },
}

local p1 = polys:new({ 1, 2, 3, 4 })
local p2 = polys:new({ 1, 2, 3, 4 })
local p3 = polys:new({ 1, 2, 3, 5 })
assert(p1 == p2)
assert(p3 ~= p1)
assert(polys:len() == 2)

local prec = polys:get(p1)
assert(#prec.coords == 4)
assert(prec.coords[2] == 2)
assert(prec.coords[4] == 4)

local paths = Path:runtime {
    capacity = 32,
    list_runtimes = {
        coords = coords_rt,
    },
}
local h1 = paths:new({ 9, 8, 7 })
local h2 = paths:new({ 9, 8, 7 })
assert(h1 == h2)

local wat = coords_rt:wat()
assert(wat:find("_hash_fn", 1, true))
assert(wat:find("_eq_slot_fn", 1, true))
assert(wat:find("_store_fn", 1, true))
assert(not wat:find("(call $asdljit_mix_u32", 1, true), wat)

print("asdljit: list runtime MVP ok")
