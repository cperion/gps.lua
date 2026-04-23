# Moonlift Typed Loop Signature Proposal

Status: **frozen typed loop-header/signature design note; implemented as the canonical authored loop syntax in the current parser/front-end**.

This document describes the typed loop-header spellings now accepted by the reboot parser/front-end.
The older canonical unparenthesized loop spelling has been removed from the parser:

- `moonlift/REBOOT_SOURCE_SPEC.md`
- `moonlift/REBOOT_SOURCE_GRAMMAR.md`

This document freezes the typed loop-header/signature spelling so that:

- loop result type is visible at the header
- loop headers read more like function signatures
- grepability/locality improves for valued loops
- later implementation does not have to reopen the design question from scratch

Companion docs:

- `moonlift/CLOSED_LANGUAGE_SEMANTIC_DECISIONS.md`
- `moonlift/REBOOT_SOURCE_SPEC.md`
- `moonlift/REBOOT_SOURCE_GRAMMAR.md`
- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`
- `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md`

---

# 1. Purpose

Moonlift loops are already typed local state-transition forms.
This proposal makes that explicit in the source header.

The core idea is:

- carries/indexes stay explicit
- expr loops declare their **result type** in the header
- natural completion still uses an explicit trailing projection
- early completion still uses `break expr`

So this proposal improves authored syntax locality without changing the core semantic model.

---

# 2. Non-goals

This proposal does **not** mean:

- a loop result becomes an implicit magical output port
- one carry is secretly "the result variable"
- `next` can update undeclared ambient state
- loops become closed-over mini-functions that cannot read outer bindings
- loops lose the explicit trailing `end -> expr` natural-completion projection

This proposal also does **not** solve every grepability concern.
It moves the **result type** to the header, not the final projection expression itself.
A later separate sugar could move common simple result bindings into the header, but that is **not** frozen here.

---

# 3. Proposed canonical syntax

## 3.1 While expr loop

```moonlift
loop (i: i32 = 0, acc: i32 = 0) -> i32 while i < n
next
    i = i + 1
    acc = acc + x
end -> acc
```

This reads as:

- loop state ports: `i`, `acc`
- loop result type: `i32`
- loop driver: `while i < n`
- explicit recurrence: `next ...`
- natural completion projection: `end -> acc`

## 3.2 Over expr loop

```moonlift
loop (i: index over range(n), acc: i32 = 0) -> i32
next
    acc = acc + xs[i]
end -> acc
```

This keeps the traversal/index port visible in the same signature-shaped header.

## 3.3 While stmt loop

```moonlift
loop (i: i32 = 0) while i < n
next
    i = i + 1
end
```

Stmt loops have **no** header result type and **no** trailing result projection.

## 3.4 Over stmt loop

```moonlift
loop (i: index over range(n), acc: i32 = 0)
next
    acc = acc + xs[i]
end
```

Again, no result type and no trailing projection.

---

# 4. Proposed grammar

## 4.1 Shared pieces

```text
loop_carry_init   ::= ident ":" type_expr "=" expr
loop_carry_list   ::= loop_carry_init { "," loop_carry_init }
loop_index_port   ::= ident ":" "index" "over" loop_domain
loop_header_item  ::= loop_index_port | loop_carry_init
loop_header_items ::= loop_header_item { "," loop_header_item }
loop_next_assign  ::= ident "=" expr
loop_next_block   ::= loop_next_assign { nl loop_next_assign }
```

## 4.2 Expr loops

```text
loop_expr              ::= loop_while_expr_typed
                         | loop_over_expr_typed

loop_while_expr_typed  ::= "loop" "(" [ loop_carry_list ] ")" "->" type_expr
                           "while" expr nl
                           stmt_block
                           "next" nl
                           loop_next_block
                           "end" "->" expr

loop_over_expr_typed   ::= "loop" "(" loop_index_port [ "," loop_carry_list ] ")"
                           "->" type_expr nl
                           stmt_block
                           "next" nl
                           loop_next_block
                           "end" "->" expr
```

## 4.3 Stmt loops

```text
loop_stmt              ::= loop_while_stmt_typed_header
                         | loop_over_stmt_typed_header

loop_while_stmt_typed_header ::= "loop" "(" [ loop_carry_list ] ")"
                                 "while" expr nl
                                 stmt_block
                                 "next" nl
                                 loop_next_block
                                 "end"

loop_over_stmt_typed_header  ::= "loop" "(" loop_index_port [ "," loop_carry_list ] ")" nl
                                 stmt_block
                                 "next" nl
                                 loop_next_block
                                 "end"
```

---

# 5. Static rules

## 5.1 Expr loops require a header result type

Expr loops must declare:

```text
-> ResultType
```

and must also end with:

```text
end -> result_expr
```

## 5.2 Stmt loops must not declare a header result type

Stmt loops remain control-only.
They do not carry a result type and do not use `end -> expr`.

## 5.3 Final projection must match the header result type

In:

```moonlift
loop (...) -> T while ...
...
end -> expr
```

`expr` must elaborate to `T`.

## 5.4 `break expr` must match the header result type

In expr loops, every `break expr` must also elaborate to the declared header result type.

## 5.5 Bare `break` stays stmt-loop control

Expr loops:

- allow `break expr`
- reject bare `break`

Stmt loops:

- allow bare `break`
- reject `break expr`

## 5.6 `over` loops require exactly one index port

The index port is part of the explicit traversal contract.
It must have type `index`.

## 5.7 `while` loops do not declare an `over` index port

A loop is either:

- a `while` loop
- or an `over` loop

not both.

## 5.8 `next` updates carries, not the `over` index port

The `over` domain drives the index port.
`next` remains the recurrence relation for carries/state only.

---

# 6. Semantic meaning

This proposal is a **Surface** change, not a new loop semantic model.

The existing meaning remains:

```text
initial state
-> body
-> next state
-> final projection
```

For expr loops there are still exactly two result paths:

- natural completion: the trailing `end -> expr`
- early completion: `break expr`

The header `-> ResultType` is a **typed contract** for those result paths.
It is not itself a result value.

---

# 7. Lexical environment and mutation rules

The loop header declares the loop's **recurrence interface**, not every visible binding.

So this proposal preserves the existing intended split:

- the loop body may still read outer values
- the loop body may still mutate outer mutable places
- only declared carries/index ports participate in the loop's explicit local recurrence contract

This means the following remains valid in principle:

- reading params and outer `let` bindings from inside the loop
- mutating outer `var` cells, statics, pointers, and other real places from inside the loop body
- reusing the loop result after the loop finishes

What stays explicit is only the loop-controlled evolving state.

---

# 8. Lowering story

If adopted, this proposal should lower to the **existing** core loop meaning.

Conceptually:

```moonlift
loop (i: i32 = 0, acc: i32 = 0) -> i32 while i < n
next
    i = i + 1
    acc = acc + x
end -> acc
```

lowers to the same semantic structure as today's loop expr:

- carries: `i`, `acc`
- condition/domain
- body
- next updates
- result expr: `acc`
- loop expr type: `i32`

So this proposal should primarily affect:

- parser / `Surface`
- `Surface -> Elab` loop lowering and loop result checking

It should **not** force a new `Sem` or `Back` loop model by itself.

---

# 9. Why freeze this proposal now

This proposal is worth freezing before implementation because it captures a real authored-language pressure:

- typed loops really do have a signature-like contract
- `return loop ... end -> expr` spreads the loop's type/result story apart
- having the result type in the header improves locality and grepability
- the proposal stays consistent with the already-frozen loop semantics in `CLOSED_LANGUAGE_SEMANTIC_DECISIONS.md`

Short version:

> loops are typed local state machines, and the source syntax should make that visible at the header.

---

# 10. Implementation status

Current status:

- implemented as the canonical authored loop syntax in the reboot parser
- implemented in current `Surface -> Elab` lowering
- lowered to the existing loop semantics without changing `Sem`/`Back` loop structure

The current parser/source docs remain authoritative for the exact accepted spellings.
