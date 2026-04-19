local iter = require("watjit.iter")

return {
    compile_drain_into = iter.compile_drain_into,
    compile_fold = iter.compile_fold,
    compile_sum = iter.compile_sum,
    compile_count = iter.compile_count,
    compile_one = iter.compile_one,
}
