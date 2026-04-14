package.path = "./?.lua;./?/init.lua;" .. package.path

local X = require("experiments.traversal_stage")

local function dump(label, t)
    io.write(label, ": [")
    for i = 1, #t do
        if i > 1 then io.write(", ") end
        io.write(tostring(t[i]))
    end
    print("]")
end

local desc = X.concat(
    X.filter("keep_div20", function(v) return v % 20 == 0 end,
        X.map("times10", function(v) return v * 10 end,
            X.seq({ 1, 2, 3, 4, 5 })
        )
    ),
    X.map("plus1", function(v) return v + 1 end,
        X.seq({ 100, 200 })
    )
)

local interpreted = X.drain(desc)
local compiled = X.compile_drain(desc)
local residual = compiled()

dump("interpreted", interpreted)
dump("compiled", residual)
print("same length", #interpreted == #residual)
for i = 1, #interpreted do
    assert(interpreted[i] == residual[i])
end
print("same values", true)
print()
print("generated source:")
print(X.compile_drain_source(desc))
print()
print("compiled each:")
local sink_out = {}
local n = 0
local run_each = X.compile_each(desc, function(v)
    n = n + 1
    sink_out[n] = v
end)
run_each()
dump("each sink", sink_out)
