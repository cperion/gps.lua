package.path = "./?.lua;./?/init.lua;" .. package.path

local json = require("json")
local J = require("json.asdl")

local function check(label, cond)
    print(label, cond)
    assert(cond)
end

local s = json.parse_string('"x"')
check("str", s == J.str("x"))

local n = json.parse_string("42")
check("num", n == J.num("42"))

local a = json.parse_string('["x",42,true,null]')
local aa = J.arr({ J.str("x"), J.num("42"), J.bool(true), J.NULL })
check("arr", a == aa)
check("arr[1]", a.items[1] == J.str("x"))
check("arr[2]", a.items[2] == J.num("42"))

local o = json.parse_string('{"k":"x","k2":["x",42]}')
local oo = J.obj({
    J.member("k", J.str("x")),
    J.member("k2", J.arr({ J.str("x"), J.num("42") })),
})
check("obj", o == oo)
check("member[1]", o.entries[1] == J.member("k", J.str("x")))
check("member[2]", o.entries[2] == J.member("k2", J.arr({ J.str("x"), J.num("42") })))
check("nested arr", o.entries[2].value == J.arr({ J.str("x"), J.num("42") }))

print("ok")
