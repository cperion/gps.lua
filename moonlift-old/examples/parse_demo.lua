local ml = require("moonlift")
ml.use()

local function show(title, ast, dump)
    print(("\n== %s =="):format(title))
    print("pretty:")
    print(parse.pretty(ast))
    print("dump:")
    print(dump)
end

show("code", parse.code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]], parse.dump_code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]])

show("module", parse.module[[
struct Pair
    a: i32
    b: i32
end

impl Pair
    func sum(self: &Pair) -> i32
        return self.a + self.b
    end
end

func pair_sum(p: &Pair) -> i32
    return p:sum()
end
]], parse.dump_module[[
struct Pair
    a: i32
    b: i32
end

impl Pair
    func sum(self: &Pair) -> i32
        return self.a + self.b
    end
end

func pair_sum(p: &Pair) -> i32
    return p:sum()
end
]])

show("expr", parse.expr[[
if x < y then ?lhs: i32 else @{fallback} end
]], parse.dump_expr[[
if x < y then ?lhs: i32 else @{fallback} end
]])

show("type", parse.type[[
func(&u8, usize) -> void
]], parse.dump_type[[
func(&u8, usize) -> void
]])

show("extern", parse.extern[[
@abi("C")
extern func abs(x: i32) -> i32
]], parse.dump_extern[[
@abi("C")
extern func abs(x: i32) -> i32
]])
