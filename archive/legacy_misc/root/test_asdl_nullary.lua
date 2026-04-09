package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local T = pvm.context():Define [[
module G {
    Expr = Num | Add(G.Expr left, G.Expr right) unique
}
]]

local Num = T.G.Num
local Add = T.G.Add

assert(Num == Num(), "nullary constructor should be callable and return the singleton")
assert(Num == Num()(), "nullary singleton should itself be callable")
assert(tostring(Num) == "G.Num", "nullary singleton tostring should stay constructor name")

local node = Add(Num(), Num)
assert(node.left == Num and node.right == Num, "nullary values should be usable directly in fields")

local tag = pvm.verb("tag", {
    [Num] = function() return "num" end,
    [Add] = function() return "add" end,
})

assert(Num:tag() == "num", "verb dispatch should accept exported nullary constructor values")
assert(Num():tag() == "num", "verb dispatch should work on callable nullary values")
assert(node:tag() == "add", "verb dispatch should still work on normal constructors")

print("== ALL PASS ==")
