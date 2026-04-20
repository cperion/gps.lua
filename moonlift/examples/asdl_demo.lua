local ml = require("moonlift")
ml.use()

local T = asdl[[
enum Color : u8
    Red = 1
    Green = 2
    Blue = 3
end

type Points = []Point

@unique
struct Point
    x: i32
    y: i32
end

@unique
tagged union Expr
    Int
        value: i64
    end

    Add
        lhs: Expr
        rhs: Expr
    end

    Hole
end

@unique
struct Cloud
    points: Points
end

@unique
tagged union Widget
    Button
        tag: string
        color: Color
    end

    Row
        children: []Widget
    end
end
]]

local p1 = T.Point { x = 20, y = 22 }
local p2 = T.Point { x = 20, y = 22 }
assert(p1 == p2)
assert(T.classof(p1) == T.Point)
assert(T.is(p1, T.Point))
print("p1 =", p1)

local cloud1 = T.Cloud { points = { p1, T.Point { x = 1, y = 2 } } }
local cloud2 = T.Cloud { points = { T.Point { x = 20, y = 22 }, T.Point { x = 1, y = 2 } } }
assert(cloud1 == cloud2)
assert(#cloud1.points == 2)
assert(cloud1.points[1] == p1)
print("cloud1 =", cloud1)

local a = T.Expr.Int { value = 40 }
local b = T.Expr.Int { value = 2 }
local expr = T.Expr.Add { lhs = a, rhs = b }
assert(T.classof(expr) == T.Expr.Add)
assert(T.is(expr, T.Expr))
assert(expr.lhs == a)
assert(expr.rhs == b)
print("expr =", expr)

local expr2 = T.with(expr, { rhs = T.Expr.Int { value = 3 } })
assert(expr2 ~= expr)
assert(expr2.lhs == expr.lhs)
assert(expr2.rhs.value == 3)
print("expr2 =", expr2)

assert(T.Expr.Hole == T.Expr.Hole)
assert(T.is(T.Expr.Hole, T.Expr))
print("hole =", T.Expr.Hole)

local row1 = T.Widget.Row {
    children = {
        T.Widget.Button { tag = "a", color = T.Color.Red },
        T.Widget.Button { tag = "b", color = T.Color.Blue },
    },
}
local row2 = T.Widget.Row {
    children = {
        T.Widget.Button { tag = "a", color = T.Color.Red },
        T.Widget.Button { tag = "b", color = T.Color.Blue },
    },
}
assert(row1 == row2)
assert(#row1.children == 2)
assert(row1.children[2].tag == "b")
print("row1 =", row1)

print("\nmoonlift asdl demo ok")
