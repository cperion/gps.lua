-- ══════════════════════════════════════════════════════════════
-- EXPLORATION: deeper patterns for pvm
--
-- Central thesis: Quote + triplet + ASDL = three primitives
-- that are each closed under composition, and they compose
-- WITH EACH OTHER too. The unexploited power is in the cross-
-- product of these three.
-- ══════════════════════════════════════════════════════════════

-- ┌─────────┐     ┌─────────┐     ┌─────────┐
-- │  Quote  │────▶│  ASDL   │────▶│ Triplet │
-- │ codegen │     │  types  │     │  g,p,c  │
-- └────┬────┘     └────┬────┘     └────┬────┘
--      │               │               │
--      └───────────────┼───────────────┘
--                      │
--               all three compose
--               with each other

-- ══════════════════════════════════════════════════════════════
-- PATTERN 1: Code-generate the pipe
-- ══════════════════════════════════════════════════════════════
--
-- pvm.pipe currently loops over stages at runtime:
--
--   for i = 2, n do
--     if iterator_mode then
--       a, b, c = stages[i](a, b, c)
--     else
--       a, b, c = stages[i](a)
--       iterator_mode = type(a) == "function"
--     end
--   end
--
-- That loop is opaque to the JIT. It can't specialize because
-- `stages[i]` is a different function each iteration. But you
-- already have Quote. So:

function pvm_pipe_codegen(name, ...)
    local stages = { ... }
    local q = Quote()
    local stage_refs = {}
    for i = 1, #stages do
        stage_refs[i] = q:val(stages[i], "stage_" .. i)
    end
    local _type = q:val(type, "type")

    q("return function(input, ...)")
    -- first stage always gets raw input
    q("  local a, b, c = %s(input, ...)", stage_refs[1])

    for i = 2, #stages do
        -- at codegen time we don't know if it's iterator mode yet,
        -- but we CAN specialize if the stage declares its mode.
        -- fallback: runtime check, but it's ONE check per stage,
        -- not a loop iteration.
        q("  if %s(a) == 'function' then", _type)
        q("    a, b, c = %s(a, b, c)", stage_refs[i])
        q("  else")
        q("    a, b, c = %s(a)", stage_refs[i])
        q("  end")
    end

    q("  return a, b, c")
    q("end")

    return q:compile("=(pvm.pipe." .. (name or "anon") .. ")")
end

-- But wait — if you KNOW at pipe-construction time which stages
-- are value→value and which are triplet→triplet, you can eliminate
-- ALL runtime checks:

function pvm_pipe_typed(name, ...)
    local stages = { ... }
    local q = Quote()
    local stage_refs = {}
    for i = 1, #stages do
        stage_refs[i] = q:val(stages[i].fn, "stage_" .. i)
    end

    q("return function(input)")
    q("  local a, b, c = input, nil, nil")

    for i = 1, #stages do
        local s = stages[i]
        if s.mode == "value" then
            q("  a = %s(a)", stage_refs[i])
        elseif s.mode == "iter" then
            q("  a, b, c = %s(a, b, c)", stage_refs[i])
        elseif s.mode == "expand" then  -- value → triplet
            q("  a, b, c = %s(a)", stage_refs[i])
        end
    end

    q("  return a, b, c")
    q("end")

    return q:compile("=(pvm.pipe." .. name .. ")")
end

-- The generated code is a straight-line function with no loops,
-- no branches, no table lookups. LuaJIT sees exactly what it
-- needs to trace.


-- ══════════════════════════════════════════════════════════════
-- PATTERN 2: Verb as flatmap — recursive dispatch as iterator
-- ══════════════════════════════════════════════════════════════
--
-- Currently verb dispatches on one node and returns one value.
-- But tree transforms often need to EXPAND — one node becomes
-- zero or more nodes. That's flatmap.
--
-- What if verb returned a triplet?

-- pvm.verb_iter("expand", {
--   [BinOp] = function(node)
--     -- emit left, then op, then right
--     return T.concat(
--       verb_iter(node.lhs),    -- recurse: returns g,p,c
--       T.unit(node.op),
--       verb_iter(node.rhs)
--     )
--   end,
--   [Lit] = function(node)
--     return T.unit(node.val)   -- leaf: single-element iterator
--   end,
-- })
--
-- Now tree traversal IS iteration. A walk over the AST is just
-- for v in verb_iter(root) do ... end
--
-- And since each dispatch returns a triplet, and triplets compose,
-- the entire recursive expansion is lazy and pull-based.


-- ══════════════════════════════════════════════════════════════
-- PATTERN 3: Walk — structural recursion as triplet
-- ══════════════════════════════════════════════════════════════
--
-- ASDL knows the fields. It knows which fields are nodes and
-- which are lists of nodes. So it can code-generate a walk
-- iterator FOR each type.

function gen_walk(ctx, type_name)
    -- ctx has __fields metadata for every type
    -- we can generate a DFS iterator that yields each node

    -- The state is a stack of (node, field_index, list_index)
    -- The param carries the ASDL context for type dispatch
    -- gen pulls the next node from the stack

    -- But here's the deep move: the walk itself is a triplet,
    -- so you can map/filter/take over it:

    -- for node in walk(root) do ... end                    -- all nodes
    -- for node in T.filter(is_lit, walk(root)) do ... end  -- just literals
    -- for node in T.take(10, walk(root)) do ... end        -- first 10
    -- for node in T.map(fold_const, walk(root)) do ... end -- transform in-flight

    -- And because ASDL has the type metadata, the walk gen
    -- function can be CODE-GENERATED per type to avoid any
    -- runtime field inspection:

    local q = Quote()
    -- generates a specialized DFS walker that knows exactly
    -- which fields to recurse into for this type hierarchy
    -- ... (implementation would inspect ctx.definitions[type_name])
end


-- ══════════════════════════════════════════════════════════════
-- PATTERN 4: Verb composition — fuse multiple dispatch passes
-- ══════════════════════════════════════════════════════════════
--
-- Two separate verbs:
--   desugar = pvm.verb("desugar", { [IfElse] = ..., [Unless] = ... })
--   typecheck = pvm.verb("typecheck", { [BinOp] = ..., [Call] = ... })
--
-- Composed naively: typecheck(desugar(node))
-- That's two metatable lookups, two dispatch chains.
--
-- But since verb is code-generated, you can FUSE them:

function pvm_verb_fuse(name, verb_a, verb_b)
    -- Generate a single if/elseif chain that:
    -- 1. dispatches to verb_a's handler
    -- 2. takes the result
    -- 3. dispatches to verb_b's handler
    -- All in one generated function, one metatable lookup per verb.
    --
    -- But the real power: if verb_a changes the metatable
    -- (e.g. Unless → IfElse), verb_b's dispatch can be
    -- specialized for the KNOWN OUTPUT TYPES of verb_a.
    --
    -- desugar always turns Unless into IfElse.
    -- So in the fused version, the typecheck dispatch for
    -- the Unless branch can skip the metatable check entirely
    -- and call the IfElse handler directly.
    --
    -- This is whole-pipeline type specialization, driven by
    -- ASDL's sum type metadata, performed at codegen time.
end


-- ══════════════════════════════════════════════════════════════
-- PATTERN 5: The slot IS a triplet
-- ══════════════════════════════════════════════════════════════
--
-- init.lua's slot runs a flat command array:
--
--   for i = 1, cmd_count do
--     local cmd = cmds[i]
--     op.run(cmd, ctx, cmd.res, ...)
--   end
--
-- That's gen/param/state:
--   gen   = function(param, pc) pc=pc+1; return pc, param.ops[param.cmds[pc].op].run(param.cmds[pc], ...) end
--   param = { cmds, ops, ctx }
--   state = 0  (program counter)
--
-- If the slot IS a triplet, then:
--   - You can compose slots with T.concat (run A then B)
--   - You can filter slot output with T.filter
--   - You can zip two slots (run in parallel, interleaved)
--   - You can take(n) from a slot (run first n commands)
--   - You can map over slot output (post-process each command result)
--
-- The slot becomes a composable unit in the same algebra as
-- everything else.

function slot_as_triplet(slot)
    local cmds = slot._cmds
    local n = slot._cmd_count
    local backend = slot._backend
    local ctx = slot._ctx

    local function gen(param, pc)
        pc = pc + 1
        if pc > param.n then return nil end
        local cmd = param.cmds[pc]
        local op = param.ops[cmd.op]
        local result = op.run(cmd, param.ctx, cmd.res)
        return pc, result
    end

    return gen, { cmds = cmds, n = n, ops = backend.ops, ctx = ctx }, 0
end


-- ══════════════════════════════════════════════════════════════
-- PATTERN 6: Quote-aware triplet codegen
-- ══════════════════════════════════════════════════════════════
--
-- The triplet microframework uses state tables:
--   { g = inner_gen, p = inner_param, c = inner_ctrl }
--
-- This is general but opaque to the JIT on first encounter.
-- After the trace warms up, LuaJIT specializes, but we can
-- HELP by generating the fused function at definition time.
--
-- T.map(f, g, p, c) currently returns a closure.
-- T.map_gen(f, g, p, c) could return a GENERATED function:

function triplet_map_gen(f, g, p, c)
    local q = Quote()
    local _f = q:val(f, "f")
    local _g = q:val(g, "g")
    local _p = q:val(p, "p")

    -- Instead of a state table, bake the inner iterator
    -- directly into the closure environment:
    q("local _c = %s", q:val(c, "init_c"))
    q("return function(_, _)")  -- ignore param and ctrl
    q("  local nc, v = %s(%s, _c)", _g, _p)
    q("  if nc == nil then return nil end")
    q("  _c = nc")
    q("  return true, %s(v)", _f)
    q("end, nil, true")

    -- The generated function has NO table lookups.
    -- g, p are upvalues (direct references).
    -- _c is a local upvalue (one pointer, not a table field).
    -- LuaJIT compiles this to a couple of register operations.

    return q:compile("=(triplet.map)")
end

-- But the REAL move: generate the entire pipeline at once.
-- Don't generate each layer separately — generate ONE function
-- that does all the layers:

function triplet_pipeline_gen(source_g, source_p, source_c, transforms)
    local q = Quote()
    local _g = q:val(source_g, "g")
    local _p = q:val(source_p, "p")
    local transform_refs = {}
    for i = 1, #transforms do
        transform_refs[i] = q:val(transforms[i], "t" .. i)
    end

    q("local _c = %s", q:val(source_c, "init_c"))
    q("return function(_, _)")
    q("  local nc, v = %s(%s, _c)", _g, _p)
    q("  if nc == nil then return nil end")
    q("  _c = nc")
    for i = 1, #transforms do
        q("  v = %s(v)", transform_refs[i])
    end
    q("  return true, v")
    q("end, nil, true")

    return q:compile("=(triplet.pipeline)")
end

-- The entire N-layer pipeline compiles to a SINGLE function.
-- No state tables. No nested calls. One function that reads
-- from the source, runs every transform in sequence, and yields.
-- LuaJIT traces this as one straight-line block.


-- ══════════════════════════════════════════════════════════════
-- PATTERN 7: ASDL-driven verb as generated iterator
-- ══════════════════════════════════════════════════════════════
--
-- This is the synthesis of all the patterns.
--
-- Given an ASDL type hierarchy and a verb (handler table),
-- generate a recursive iterator that:
--   1. walks the tree (Pattern 3)
--   2. dispatches by type (Pattern 4/verb)
--   3. yields results as a triplet (Pattern 2)
--   4. fuses with downstream transforms (Pattern 6)
--   5. all in one generated function (Quote)

function gen_tree_transform(ctx, verb_handlers, transforms)
    local q = Quote()

    -- For each ASDL type in the handlers, we know:
    --   - its fields (from ctx.__fields)
    --   - which fields are recursive (ASDL node types)
    --   - which fields are lists of nodes
    --   - the handler function for this type
    --
    -- So we can generate a specialized recursive walker+transformer
    -- that never does metatable dispatch at runtime, because the
    -- recursion structure is known at codegen time.
    --
    -- Example generated code for:
    --   Expr = BinOp(string op, Expr lhs, Expr rhs)
    --        | Lit(number val) unique
    --        | Call(string name, Expr* args)
    --
    --   verb: { BinOp = f1, Lit = f2, Call = f3 }
    --   transforms: { optimize, typecheck }
    --
    -- Generated:
    --
    --   local function process(node)
    --     local mt = getmetatable(node)
    --     local v
    --     if mt == BinOp then
    --       local lhs = process(node.lhs)   -- recurse (known field)
    --       local rhs = process(node.rhs)   -- recurse (known field)
    --       v = f1(node, lhs, rhs)           -- handler gets pre-processed children
    --     elseif mt == Lit then
    --       v = f2(node)                     -- leaf, no recursion needed
    --     elseif mt == Call then
    --       local args = {}                  -- list field
    --       for i = 1, #node.args do
    --         args[i] = process(node.args[i])
    --       end
    --       v = f3(node, args)
    --     end
    --     v = optimize(v)                    -- fused downstream transforms
    --     v = typecheck(v)
    --     return v
    --   end
    --
    -- The recursion is structural (guided by ASDL metadata).
    -- The dispatch is a flat if/elseif (generated by Quote).
    -- The transforms are inlined (no pipeline overhead).
    -- Everything is in one function that LuaJIT can trace
    -- through the hot paths.

    -- To make this an ITERATOR (lazy, pull-based), the generated
    -- code uses the coroutine-free trick: the walk is driven by
    -- a stack in the state, and each call to gen pops one node,
    -- processes it, and pushes its children. The stack IS the
    -- continuation.

    -- state = { stack, stack_top }
    -- gen(param, state):
    --   pop node from stack
    --   dispatch by metatable (generated chain)
    --   push children in reverse order (so left-to-right DFS)
    --   apply transforms
    --   return result
end


-- ══════════════════════════════════════════════════════════════
-- PATTERN 8: Resource reconciliation as diff iterator
-- ══════════════════════════════════════════════════════════════
--
-- init.lua's reconcile_resources does a full pass to diff old
-- and new resources. This is essentially a specialized zip:
--
--   for old_cmd, new_cmd in zip(old_cmds, new_cmds) do
--     if same_key(old_cmd, new_cmd) then reuse
--     else release old, alloc new
--     end
--   end
--
-- If command arrays were triplets, reconciliation is just
-- zip_with(reconcile_one, old_triplet, new_triplet)
--
-- And since the result is itself a triplet, you can chain
-- further processing: zip → filter(changed_only) → map(apply)


-- ══════════════════════════════════════════════════════════════
-- PATTERN 9: Quote splicing as triplet composition
-- ══════════════════════════════════════════════════════════════
--
-- Quote already has emit() to splice one quote into another.
-- This is composition of code fragments. What if Quote itself
-- was iterable?
--
--   local q = Quote()
--   q("line 1")
--   q("line 2")
--
--   -- q is an iterator of lines:
--   for _, line in q:lines() do print(line) end
--
-- Then code generation is just:
--   local final = T.pipeline(
--     q1:lines(),          -- header
--     q2:lines(),          -- body
--     q3:lines(),          -- footer
--   )
--   T.join("\n", T.concat(final))
--
-- But more powerfully: transform code fragments with the same
-- combinators you use for data:
--
--   local indented = T.map(function(line) return "  " .. line end, q:lines())
--   local numbered = T.mapi(function(i, line) return i .. ": " .. line end, q:lines())
--
-- Code generation becomes stream processing over source lines,
-- using the same algebra as everything else.


-- ══════════════════════════════════════════════════════════════
-- PATTERN 10: Self-bootstrapping
-- ══════════════════════════════════════════════════════════════
--
-- The ASDL lexer is already a triplet.
-- The ASDL parser fuses with it manually.
--
-- With the patterns above, you could:
--   1. Define the ASDL grammar IN ASDL
--   2. Use verb to generate the parser from the grammar
--   3. Use Quote to codegen the fused lexer+parser
--   4. The generated parser is itself a triplet
--   5. Feed it ASDL text → get definitions → codegen types
--
-- The system defines itself.
--
-- ASDL text → triplet(lexer) → triplet(parser) → definitions
--     → Quote(codegen constructors) → live types
--     → Quote(codegen verb) → dispatchers
--     → Quote(codegen pipeline) → fused triplet
--
-- Every arrow is a triplet. Every codegen step uses Quote.
-- Every type is ASDL. One system, three primitives.


-- ══════════════════════════════════════════════════════════════
-- CONCRETE SYNTHESIS: what to build next
-- ══════════════════════════════════════════════════════════════
--
-- Priority order (most impact first):
--
-- 1. CODEGEN PIPE (Pattern 1)
--    Easy win. Replace the runtime loop in pvm.pipe with Quote.
--    Drop-in replacement. Immediate perf gain on hot pipelines.
--    Maybe 30 lines of code.
--
-- 2. SLOT AS TRIPLET (Pattern 5)
--    Make slot:iter() return (g, p, c). Lets you compose slots
--    with the iterator algebra. Opens up slot-level composition
--    that currently requires manual wiring.
--
-- 3. CODEGEN PIPELINE FUSION (Pattern 6)
--    The big one. T.pipeline but Quote-generated. One function
--    for the whole chain. This is where the triplet algebra
--    meets Quote and the result is faster than hand-written code.
--
-- 4. WALK ITERATOR (Pattern 3)
--    ASDL-driven. Makes tree transforms composable with the
--    iterator algebra. Unlocks filter/map/take over AST nodes.
--
-- 5. VERB AS ITERATOR (Pattern 2)
--    Needs walk first. Then verb returns triplets, and tree
--    transforms are just iterator composition. The most
--    algebraically satisfying but needs the other pieces.
--
-- The thesis: you've already built the three primitives
-- (Quote, ASDL, triplet). The unexploited power is in making
-- them COMPOSE WITH EACH OTHER, not just within themselves.
-- Quote generates triplet code. ASDL drives Quote's codegen.
-- Triplets carry ASDL nodes. The triangle closes.
