print("=== Terra Disassembly ===\n")

local terra sum_loop(n: int64): int64
    var i: int64 = 0
    var acc: int64 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end

sum_loop:compile()
sum_loop:disas()
print()

local terra sum_loop_opt(n: int64): int64
    var i: int64 = 0
    var acc: int64 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end
sum_loop_opt:setoptimized(true)
sum_loop_opt:compile()
print("--- Optimized ---")
sum_loop_opt:disas()
