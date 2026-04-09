-- test_pvm3.lua — tests for pvm3: the recording phase boundary

local pvm3 = require("pvm3")
local T = pvm3.T

local pass, fail = 0, 0
local function check(cond, name)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        io.write("  FAIL: " .. name .. "\n")
    end
end

local function section(name)
    io.write("── " .. name .. " ──\n")
end

-- ══════════════════════════════════════════════════════════════
--  Setup: ASDL types for testing
-- ══════════════════════════════════════════════════════════════

local CTX = pvm3.context():Define [[
    module Ex {
        Expr = BinOp(string op, Ex.Expr lhs, Ex.Expr rhs) unique
             | Lit(number val) unique
             | Call(string name, Ex.Expr* args) unique
    }
]]

local BinOp = CTX.Ex.BinOp
local Lit   = CTX.Ex.Lit
local Call  = CTX.Ex.Call

local tree = BinOp("+", Lit(1), BinOp("*", Lit(2), Lit(3)))
local call_tree = Call("f", { Lit(1), Lit(2), Lit(3) })
local partial_tree = BinOp("+", BinOp("*", Lit(1), Lit(2)), BinOp("-", Lit(3), Lit(4)))

-- ══════════════════════════════════════════════════════════════
--  TEST: primitive triplets
-- ══════════════════════════════════════════════════════════════
section("primitives")

do
    local one = pvm3.drain(pvm3.once("x"))
    check(#one == 1 and one[1] == "x", "once yields one element")

    local empty = pvm3.drain(pvm3.empty())
    check(#empty == 0, "empty yields zero elements")
end

do
    local seq = T.collect(pvm3.seq({ 1, 2, 3, 4 }, 2))
    check(#seq == 2, "seq respects explicit n")
    check(seq[1] == 1 and seq[2] == 2, "seq explicit n values")

    local rev = T.collect(pvm3.seq_rev({ "a", "b", "c" }, 5))
    check(#rev == 3, "seq_rev clamps n to array size")
    check(rev[1] == "c" and rev[3] == "a", "seq_rev values")
end

do
    local g1, p1, c1 = pvm3.once("a")
    local g2, p2, c2 = pvm3.seq({ "b", "c" })
    local joined2 = pvm3.drain(pvm3.concat2(g1, p1, c1, g2, p2, c2))
    check(#joined2 == 3, "concat2 count")
    check(table.concat(joined2, " ") == "a b c", "concat2 values")

    local h1, q1, r1 = pvm3.once("a")
    local h2, q2, r2 = pvm3.seq({ "b", "c" })
    local h3, q3, r3 = pvm3.once("d")
    local joined3 = pvm3.drain(pvm3.concat3(h1, q1, r1, h2, q2, r2, h3, q3, r3))
    check(#joined3 == 4, "concat3 count")
    check(table.concat(joined3, " ") == "a b c d", "concat3 values")

    local joined = pvm3.drain(pvm3.concat_all({
        { pvm3.once("a") },
        { pvm3.seq({ "b", "c" }) },
        { pvm3.once("d") },
    }))
    check(#joined == 4, "concat_all count")
    check(table.concat(joined, " ") == "a b c d", "concat_all values")

    local joined4 = pvm3.drain(pvm3.concat_all({
        { pvm3.once("a") },
        { pvm3.seq({ "b" }) },
        { pvm3.once("c") },
        { pvm3.seq({ "d", "e" }) },
    }))
    check(#joined4 == 5, "concat_all fallback count")
    check(table.concat(joined4, " ") == "a b c d e", "concat_all fallback values")
end

 do
    local g, p, c = pvm3.seq({ 10, 20, 30, 40 })
    c = g(p, c)
    local rest = pvm3.drain(g, p, c)
    check(#rest == 3 and rest[1] == 20 and rest[3] == 40, "drain respects advanced seq state")

    local g2, p2, c2 = pvm3.seq({ "x", "y", "z" })
    c2 = g2(p2, c2)
    local out = { "start" }
    pvm3.drain_into(g2, p2, c2, out)
    check(#out == 3 and out[1] == "start" and out[2] == "y" and out[3] == "z", "drain_into respects advanced seq state")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: phase basic behavior
-- ══════════════════════════════════════════════════════════════
section("phase")

do
    local emit
    emit = pvm3.phase("emit", {
        [CTX.Ex.Lit] = function(node)
            return pvm3.once(tostring(node.val))
        end,
        [CTX.Ex.BinOp] = function(node)
            return pvm3.concat_all({
                { emit(node.lhs) },
                { pvm3.once(node.op) },
                { emit(node.rhs) },
            })
        end,
        [CTX.Ex.Call] = function(node)
            local parts = {
                { pvm3.once(node.name) },
                { pvm3.once("(") },
            }
            for i, arg in ipairs(node.args) do
                if i > 1 then
                    parts[#parts + 1] = { pvm3.once(",") }
                end
                parts[#parts + 1] = { emit(arg) }
            end
            parts[#parts + 1] = { pvm3.once(")") }
            return pvm3.concat_all(parts)
        end,
    })

    local out = pvm3.drain(emit(tree))
    check(#out == 5, "phase basic count")
    check(table.concat(out, " ") == "1 + 2 * 3", "phase basic values")

    local s1 = emit:stats()
    check(s1.calls == 5 and s1.hits == 0, "phase cold stats")
    check(emit:cached(tree) ~= nil, "phase root cached after full drain")

    local out2 = pvm3.drain(tree:emit())
    check(table.concat(out2, " ") == "1 + 2 * 3", "phase method syntax")
    local s2 = emit:stats()
    check(s2.calls == 6 and s2.hits == 1, "phase warm root hit stats")

    local call_out = pvm3.drain(emit(call_tree))
    check(table.concat(call_out, " ") == "f ( 1 , 2 , 3 )", "phase Call values")

    emit:reset()
    check(emit:stats().calls == 0 and emit:stats().hits == 0, "phase reset clears stats")
    check(emit:cached(tree) == nil, "phase reset clears cache")

    local warmed = emit:warm(tree)
    check(type(warmed) == "table", "phase warm returns cached array")
    check(table.concat(warmed, " ") == "1 + 2 * 3", "phase warm values")
    check(emit:cached(tree) == warmed, "phase warm populates cache")

    local out3 = { "begin" }
    local g3, p3, c3 = emit(tree)
    pvm3.drain_into(g3, p3, c3, out3)
    check(#out3 == 6, "drain_into appends into existing array")
    check(out3[1] == "begin" and out3[2] == "1" and out3[6] == "3", "drain_into values")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: incremental sharing
-- ══════════════════════════════════════════════════════════════
section("incremental")

do
    local handler_calls = {}
    local emit_inc
    emit_inc = pvm3.phase("emit_inc", {
        [CTX.Ex.Lit] = function(node)
            handler_calls[#handler_calls + 1] = "Lit(" .. node.val .. ")"
            return pvm3.once(node.val)
        end,
        [CTX.Ex.BinOp] = function(node)
            handler_calls[#handler_calls + 1] = "BinOp(" .. node.op .. ")"
            return pvm3.concat_all({
                { emit_inc(node.lhs) },
                { pvm3.once(node.op) },
                { emit_inc(node.rhs) },
            })
        end,
        [CTX.Ex.Call] = function(node)
            handler_calls[#handler_calls + 1] = "Call(" .. node.name .. ")"
            return pvm3.once(node.name)
        end,
    })

    handler_calls = {}
    pvm3.drain(emit_inc(tree))
    check(#handler_calls == 5, "incremental prime runs all handlers")

    local changed = BinOp("+", tree.lhs, pvm3.with(tree.rhs, { rhs = Lit(99) }))

    handler_calls = {}
    local out = pvm3.drain(emit_inc(changed))
    check(#handler_calls == 3, "incremental reruns only changed path")

    local saw_lit99, saw_lit1, saw_lit2 = false, false, false
    for _, item in ipairs(handler_calls) do
        if item == "Lit(99)" then saw_lit99 = true end
        if item == "Lit(1)" then saw_lit1 = true end
        if item == "Lit(2)" then saw_lit2 = true end
    end
    check(saw_lit99, "incremental new leaf reran")
    check(not saw_lit1 and not saw_lit2, "incremental shared leaves hit cache")
    check(out[1] == 1 and out[3] == 2 and out[5] == 99, "incremental output values")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: in-flight sharing
-- ══════════════════════════════════════════════════════════════
section("in-flight sharing")

do
    local shared = BinOp("*", Lit(2), Lit(3))
    local dag = BinOp("+", shared, shared)
    local handler_calls = 0
    local emit_dag
    emit_dag = pvm3.phase("emit_dag", {
        [CTX.Ex.Lit] = function(node)
            handler_calls = handler_calls + 1
            return pvm3.once(tostring(node.val))
        end,
        [CTX.Ex.BinOp] = function(node)
            handler_calls = handler_calls + 1
            return pvm3.concat_all({
                { emit_dag(node.lhs) },
                { pvm3.once(node.op) },
                { emit_dag(node.rhs) },
            })
        end,
    })

    local g, p, c = emit_dag(dag)
    check(emit_dag:inflight(shared) ~= nil, "shared subtree is in flight before drain")

    local out = pvm3.drain(g, p, c)
    check(table.concat(out, " ") == "2 * 3 + 2 * 3", "in-flight shared output")
    check(handler_calls == 4, "in-flight shared subtree built once")
    check(emit_dag:inflight(shared) == nil, "in-flight entry clears after commit")
    check(emit_dag:cached(shared) ~= nil and emit_dag:cached(dag) ~= nil, "in-flight full drain caches shared subtree and root")

    local stats = emit_dag:stats()
    check(stats.calls == 5 and stats.hits == 0 and stats.shared == 1, "in-flight sharing stats")
    check(emit_dag:reuse_ratio() > emit_dag:hit_ratio(), "reuse_ratio counts in-flight sharing")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: partial drain semantics
-- ══════════════════════════════════════════════════════════════
section("partial drain")

do
    local emit_partial
    emit_partial = pvm3.phase("emit_partial", {
        [CTX.Ex.Lit] = function(node)
            return pvm3.once(tostring(node.val))
        end,
        [CTX.Ex.BinOp] = function(node)
            return pvm3.concat_all({
                { emit_partial(node.lhs) },
                { pvm3.once(node.op) },
                { emit_partial(node.rhs) },
            })
        end,
        [CTX.Ex.Call] = function(node)
            return pvm3.once(node.name)
        end,
    })

    local g, p, c = emit_partial(partial_tree)
    local pulled = {}
    for i = 1, 4 do
        c, pulled[i] = g(p, c)
    end

    check(table.concat(pulled, " ") == "1 * 2 +", "partial drain consumed first subtree and separator")
    check(emit_partial:cached(partial_tree) == nil, "partial drain leaves root uncached")
    check(emit_partial:cached(partial_tree.lhs) ~= nil, "partial drain can commit exhausted inner phase")
    check(emit_partial:cached(partial_tree.rhs) == nil, "partial drain leaves untouched subtree uncached")

    local out = pvm3.drain(emit_partial(partial_tree))
    check(table.concat(out, " ") == "1 * 2 + 3 - 4", "full drain still works after partial drain")
    check(emit_partial:cached(partial_tree) ~= nil, "full drain caches root")

    emit_partial:reset()
    local rg, rp, rc = emit_partial(partial_tree)
    rc = rg(rp, rc)
    local tail = pvm3.drain(rg, rp, rc)
    check(table.concat(tail, " ") == "* 2 + 3 - 4", "drain respects advanced recording state")

    emit_partial:reset()
    local ig, ip, ic = emit_partial(partial_tree)
    ic = ig(ip, ic)
    local appended = { "start" }
    pvm3.drain_into(ig, ip, ic, appended)
    check(table.concat(appended, " ") == "start * 2 + 3 - 4", "drain_into respects advanced recording state")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: children / each / fold / lower / report
-- ══════════════════════════════════════════════════════════════
section("helpers")

do
    local values
    values = pvm3.phase("values", {
        [CTX.Ex.Lit] = function(node)
            return pvm3.once(node.val)
        end,
        [CTX.Ex.Call] = function(node)
            return pvm3.children(values, node.args)
        end,
    })

    local vals = pvm3.drain(values(call_tree))
    check(#vals == 3 and vals[1] == 1 and vals[3] == 3, "children lowers all args")

    local first2 = pvm3.drain(pvm3.children(values, call_tree.args, 2))
    check(#first2 == 2 and first2[1] == 1 and first2[2] == 2, "children respects explicit n")

    local clamped = pvm3.drain(pvm3.children(values, call_tree.args, 10))
    check(#clamped == 3 and clamped[3] == 3, "children clamps oversized n")

    local many = pvm3.drain(pvm3.children(values, { Lit(4), Lit(5), Lit(6), Lit(7), Lit(8) }))
    check(#many == 5 and many[1] == 4 and many[5] == 8, "children fallback lowers >3 args")
end

do
    local seen = ""
    local eg, ep, ec = pvm3.seq({ "a", "b", "c" }, 2)
    pvm3.each(eg, ep, ec, function(v)
        seen = seen .. v
    end)
    check(seen == "ab", "each consumes explicit prefix")

    local fg, fp, fc = pvm3.seq({ 1, 2, 3, 4 }, 3)
    local sum = pvm3.fold(fg, fp, fc, 0, function(acc, v)
        return acc + v
    end)
    check(sum == 6, "fold reduces explicit prefix")
end

do
    local eval = pvm3.lower("eval", function(node)
        return node.val * 10
    end)

    check(eval(Lit(9)) == 90, "lower computes value")
    check(eval(Lit(9)) == 90, "lower cached value")
    check(eval:stats().hits == 1, "lower tracks hits")
    check(eval:cached(Lit(9)) == 90, "lower cached lookup")
    check(eval:warm(Lit(8)) == 80, "lower warm computes value")

    local ok, err = pcall(function()
        return eval(Lit(9), "!")
    end)
    check(not ok, "lower rejects extra args")
    check(type(err) == "string" and err:find("extra args") ~= nil, "lower extra-args error")

    local report = pvm3.report({ eval })
    check(type(report) == "table" and #report == 1, "report returns table")
    check(report[1].name == "eval" and report[1].calls >= 2, "report entry has stats")
    check(report[1].shared == 0 and report[1].reuse_ratio >= report[1].ratio, "report includes shared/reuse stats")

    local report_str = pvm3.report_string({ eval })
    check(type(report_str) == "string" and report_str:find("eval") ~= nil, "report_string mentions phase")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: handler normalization compatibility
-- ══════════════════════════════════════════════════════════════
section("handler normalization")

do
    local exemplar = Lit(0)
    local by_instance = pvm3.phase("by_instance", {
        [exemplar] = function(node)
            return pvm3.once(node.val * 2)
        end,
    })

    local out = pvm3.drain(by_instance(Lit(7)))
    check(#out == 1 and out[1] == 14, "phase normalizes instance keys to class")

    local out2 = pvm3.drain(Lit(8):by_instance())
    check(#out2 == 1 and out2[1] == 16, "normalized handler installs class method")
end

-- ══════════════════════════════════════════════════════════════
--  REPORT
-- ══════════════════════════════════════════════════════════════

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
if fail > 0 then os.exit(1) end
