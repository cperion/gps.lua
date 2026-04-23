# Moonlift Reboot Source Grammar

Status: parser-oriented grammar for the **current rebooted closed source language**.

This grammar is intentionally derived from the current reboot ASDL in:

- `moonlift/lua/moonlift/asdl.lua`

It is not a verbatim copy of `moonlift-old/`.
It is the grammar we should use for the reboot parser unless and until the reboot ASDL changes.

Companion docs:

- `moonlift/REBOOT_SOURCE_SPEC.md`
- `moonlift/TYPED_LOOP_SIGNATURE_PROPOSAL.md` — frozen future source-syntax proposal, not the current implemented grammar

---

## 1. Lexical layer

### 1.1 Whitespace

Whitespace separates tokens.
Newlines matter where block-oriented syntax requires statement/item separation.

```text
nl ::= one or more newline tokens
```

### 1.2 Comments

Line comment:

```text
-- comment
```

Block comment:

```text
--[[
comment
]]
```

### 1.3 Identifiers

Identifiers follow Lua-like rules:

```text
ident ::= [A-Za-z_][A-Za-z0-9_]*
```

### 1.4 Paths

```text
path ::= ident { "." ident }
```

### 1.5 Literals

```text
int_lit   ::= decimal_int | hex_int
float_lit ::= decimal_float [ exponent ]
bool_lit  ::= "true" | "false"
nil_lit   ::= "nil"
```

Important parser rule:

- integer and float tokens preserve raw source spelling into `SurfInt(raw)` / `SurfFloat(raw)`

### 1.6 Core reserved words

Current reboot closed-language keywords:

- `func`
- `extern`
- `const`
- `static`
- `import`
- `type`
- `struct`
- `view`
- `let`
- `var`
- `if`
- `then`
- `elseif`
- `else`
- `switch`
- `case`
- `default`
- `return`
- `break`
- `continue`
- `loop`
- `next`
- `while`
- `over`
- `do`
- `end`
- `true`
- `false`
- `nil`
- `and`
- `or`
- `not`
- `cast`
- `trunc`
- `zext`
- `sext`
- `bitcast`
- `satcast`
- `func` (type form as well)
- scalar type names such as `i32`, `f64`, `index`, etc.

Intrinsic names are also reserved in expression-call position:

- `popcount`
- `clz`
- `ctz`
- `rotl`
- `rotr`
- `bswap`
- `fma`
- `sqrt`
- `abs`
- `floor`
- `ceil`
- `trunc_float`
- `round`
- `trap`
- `assume`

---

## 2. Modules and items

```text
module      ::= { item }

item        ::= func_decl
              | extern_func_decl
              | const_decl
              | static_decl
              | import_decl
              | type_decl
```

### 2.1 Constants, statics, imports, and authored struct types

```text
const_decl  ::= "const" ident ":" type "=" expr
static_decl ::= "static" ident ":" type "=" expr
import_decl ::= "import" path
type_decl   ::= "type" ident "=" "struct" "{" [ type_field_list ] "}"
type_field_list ::= type_field { "," type_field } [ "," ]
type_field  ::= ident ":" type
```

These map to:

- `SurfConst`
- `SurfStatic`
- `SurfImport`
- `SurfStruct`

Current reboot note:

- module names are currently supplied by the host/package API rather than an authored `module ...` declaration
- `import Demo` makes the qualified namespace `Demo.*` available; it does not introduce unqualified names

### 2.2 Functions

```text
func_decl         ::= "func" ident "(" [ param_list ] ")" [ "->" type ] nl stmt_block "end"
extern_func_decl  ::= "extern" "func" ident "(" [ param_list ] ")" [ "->" type ]

param_list        ::= param { "," param }
param             ::= ident ":" type
```

Parser rule:

- missing result type defaults to `void`
- the parser emits `SurfTVoid` explicitly in `Surface`

---

## 3. Types

The current reboot grammar freezes these type spellings:

```text
type              ::= scalar_type
                    | named_type
                    | ptr_type
                    | array_type
                    | slice_type
                    | view_type
                    | func_type

scalar_type       ::= "void"
                    | "bool"
                    | "i8" | "i16" | "i32" | "i64"
                    | "u8" | "u16" | "u32" | "u64"
                    | "f32" | "f64"
                    | "index"

named_type        ::= path
ptr_type          ::= "&" type
array_type        ::= "[" count_expr "]" type
slice_type        ::= "[]" type
view_type         ::= "view" "(" type ")"
func_type         ::= "func" "(" [ type_list ] ")" "->" type

type_list         ::= type { "," type }
```

### 3.1 Count expressions for array types

Current count expressions are intentionally narrower than general expressions in later lowering,
but the parser may accept the full expression grammar and emit normal `SurfExpr` structure.

Practically useful count forms today include:

- integer literal
- named const
- qualified const path
- `+`
- `-`
- `*`

---

## 4. Statements

```text
stmt              ::= let_stmt
                    | var_stmt
                    | set_stmt
                    | if_stmt
                    | switch_stmt
                    | return_stmt
                    | break_stmt
                    | continue_stmt
                    | loop_stmt
                    | expr_stmt
```

### 4.1 Let / var

```text
let_stmt          ::= "let" ident ":" type "=" expr
var_stmt          ::= "var" ident ":" type "=" expr
```

Current reboot rule:

- local bindings are explicitly typed in the source grammar

### 4.2 Set / assignment

```text
set_stmt          ::= place "=" expr
```

### 4.3 If statement

```text
if_stmt           ::= "if" expr "then" nl stmt_block elseif_chain else_clause? "end"
elseif_chain      ::= { "elseif" expr "then" nl stmt_block }
else_clause       ::= "else" nl stmt_block
```

Parser lowering rule:

- `elseif` chains lower to nested `SurfIf` in the else branch

### 4.4 Switch statement

```text
switch_stmt       ::= "switch" expr "do" nl switch_stmt_arm+ default_stmt_arm "end"
switch_stmt_arm   ::= "case" expr "then" nl stmt_block
default_stmt_arm  ::= "default" "then" nl stmt_block
```

### 4.5 Return / break / continue

```text
return_stmt       ::= "return" [ expr ]
break_stmt        ::= "break" [ expr ]
continue_stmt     ::= "continue"
```

Parser lowering:

- bare `break` -> `SurfBreak`
- `break expr` -> `SurfBreakValue(expr)`

### 4.6 Loop statement

```text
loop_stmt         ::= loop_while_stmt
                    | loop_over_stmt
```

### 4.7 Expression statement

```text
expr_stmt         ::= expr
```

---

## 5. Places / lvalues

Assignable syntax lowers to `SurfPlace`.

```text
place             ::= place_atom { place_suffix }
place_atom        ::= ident
                    | path
                    | "*" expr

place_suffix      ::= "." ident
                    | "[" expr "]"
```

Current bootstrap parser rule:

- authored dotted place syntax parses first as `SurfPlaceDot`
- later lowering resolves that dot-chain either as qualified binding lookup or field-place projection
- if the head of the dotted chain resolves as a local/runtime value binding, that local head wins and the chain is treated as a field-place chain

This supports shapes such as:

```text
x
Demo.K
*p
p.x
p[i]
(*p).x
```

Parser note:

- assignment parsing should produce `SurfPlace*` directly
- address-of `&place` should also go through place parsing, not ordinary expr parsing

---

## 6. Expressions

The reboot expression grammar is best read as:

- structured special forms first
- then normal precedence-based expressions

```text
expr              ::= if_expr
                    | switch_expr
                    | loop_expr
                    | block_expr
                    | select_expr
                    | binary_expr
```

---

## 7. Special expression forms

### 7.1 If expression

```text
if_expr           ::= "if" expr "then" expr "else" expr "end"
```

If branch-local statements are needed, use block expressions inside the branches.

### 7.1a Select expression

```text
select_expr       ::= "select" "(" expr "," expr "," expr ")"
```

This lowers to `SurfSelectExpr`.

### 7.2 Switch expression

```text
switch_expr       ::= "switch" expr "do" nl switch_expr_arm+ default_expr_arm "end"
switch_expr_arm   ::= "case" expr "then" nl expr_block
default_expr_arm  ::= "default" "then" nl expr_block
```

An `expr_block` is:

- zero or more statements
- followed by one required result expression

This maps directly to `SurfSwitchExprArm(key, body, result)`.

### 7.3 Block expression

```text
block_expr        ::= "do" nl expr_block "end"
expr_block        ::= { stmt } expr
```

This maps directly to:

- `SurfBlockExpr(stmts, result)`

### 7.4 Loop expression

```text
loop_expr         ::= loop_while_expr
                    | loop_over_expr
```

---

## 8. Canonical loops

The reboot source grammar centers loops on the current `Surface` loop families.

There is currently **no separate plain `while` or `for` AST family** in `MoonliftSurface`.
So the grammar is centered on canonical `loop` forms.

Important current note:

- this grammar describes the implemented reboot parser today
- typed loop-header spellings from `moonlift/TYPED_LOOP_SIGNATURE_PROPOSAL.md` are now the only accepted authored loop syntax

### 8.1 Loop carries

```text
loop_carry_init   ::= ident ":" type "=" expr
loop_carry_list   ::= loop_carry_init { "," loop_carry_init }
loop_index_port   ::= ident ":" "index" "over" domain
loop_next_assign  ::= ident "=" expr
loop_next_block   ::= loop_next_assign { nl loop_next_assign }
```

### 8.2 `loop ... while ...`

Statement form:

```text
loop_while_stmt   ::= "loop" "(" [ loop_carry_list ] ")" "while" expr nl stmt_block "next" nl loop_next_block "end"
```

Expression form:

```text
loop_while_expr   ::= "loop" "(" [ loop_carry_list ] ")" "->" type "while" expr nl stmt_block "next" nl loop_next_block "end" "->" expr
```

These map to:

- `SurfLoopWhileStmt`
- `SurfLoopWhileExprTyped`

### 8.3 `loop ... over ...`

Statement form:

```text
loop_over_stmt    ::= "loop" "(" loop_index_port [ "," loop_carry_list ] ")" nl stmt_block "next" nl loop_next_block "end"
```

Expression form:

```text
loop_over_expr    ::= "loop" "(" loop_index_port [ "," loop_carry_list ] ")" "->" type nl stmt_block "next" nl loop_next_block "end" "->" expr
```

These map to:

- `SurfLoopOverStmt`
- `SurfLoopOverExprTyped`

### 8.4 Domains

```text
domain            ::= range_domain
                    | zip_eq_domain
                    | domain_value

range_domain      ::= "range" "(" expr ")"
                    | "range" "(" expr "," expr ")"

zip_eq_domain     ::= "zip_eq" "(" expr { "," expr } ")"
domain_value      ::= expr
```

Parser lowering:

- `range(stop)` -> `SurfDomainRange(stop)`
- `range(start, stop)` -> `SurfDomainRange2(start, stop)`
- `zip_eq(...)` -> `SurfDomainZipEq(values)`
- anything else in `over` position -> `SurfDomainValue(value)`

---

## 9. Ordinary precedence grammar

After special forms are handled, the ordinary expression parser uses standard precedence.

A Pratt parser or precedence-climbing parser is recommended.

### 9.1 Precedence table

From lowest to highest:

1. `or`
2. `and`
3. comparisons: `== ~= < <= > >=`
4. bitwise or: `|`
5. bitwise xor: `~`
6. bitwise and: `&`
7. shifts: `<< >> >>>`
8. additive: `+ -`
9. multiplicative: `* / %`
10. prefix unary: `- not ~ & *`
11. postfix: call, field, index

### 9.2 Prefix layer

```text
prefix_expr       ::= literal
                    | name_expr
                    | path_expr
                    | cast_expr
                    | intrinsic_expr
                    | select_expr
                    | "(" expr ")"
                    | unary_expr
```

### 9.3 Name / path / dotted value syntax

```text
name_expr         ::= ident
path_expr         ::= path   ; available as explicit already-disambiguated builder form
```

Current bootstrap parser rule:

- authored dotted expression syntax parses first as nested `SurfExprDot`
- later lowering resolves that dot-chain either as qualified binding lookup or field projection
- if the head of the dotted chain resolves as a local/runtime value binding, that local head wins and the chain is treated as a field chain

### 9.4 Cast family

```text
cast_expr         ::= "cast" "<" type ">" "(" expr ")"
                    | "trunc" "<" type ">" "(" expr ")"
                    | "zext" "<" type ">" "(" expr ")"
                    | "sext" "<" type ">" "(" expr ")"
                    | "bitcast" "<" type ">" "(" expr ")"
                    | "satcast" "<" type ">" "(" expr ")"
```

### 9.5 Intrinsics

```text
intrinsic_expr    ::= intrinsic_name "(" [ expr_list ] ")"
expr_list         ::= expr { "," expr }
```

### 9.6 Unary

```text
unary_expr        ::= "-" expr
                    | "not" expr
                    | "~" expr
                    | "&" place
                    | "*" expr
```

### 9.7 Postfix chains

```text
postfix_expr      ::= prefix_expr { postfix_suffix }
postfix_suffix    ::= call_suffix
                    | field_suffix
                    | index_suffix

call_suffix       ::= "(" [ expr_list ] ")"
field_suffix      ::= "." ident
index_suffix      ::= "[" expr "]"
```

These lower to:

- `SurfCall`
- `SurfExprDot`
- `SurfIndex`

### 9.8 Aggregate literals

The reboot freezes field-based aggregate literal syntax:

```text
agg_expr          ::= type_like "{" field_init_list "}"
field_init_list   ::= field_init { "," field_init } [ "," ]
field_init        ::= ident "=" expr
```

This lowers to:

- `SurfAgg(ty, fields)`

Important note:

- the parser should only treat this as aggregate syntax when the prefix is being parsed in a type-like position
- otherwise `{` has no general expression meaning in the reboot grammar

### 9.9 Array literals

The current bootstrap reboot grammar freezes:

```text
array_lit_expr    ::= "[" "]" type "{" [ expr_list ] "}"
```

Examples:

```text
[]i32 { 1, 2, 3 }
[]f64 { x, y, z }
```

This lowers to:

- `SurfArrayLit(elem_ty, elems)`

Important note:

- the current `Surface` literal records element type and elements only
- extent is inferred from element count downstream

---

## 10. Statement and expression blocks

### 10.1 Statement block

```text
stmt_block        ::= { stmt }
```

### 10.2 Expression block

```text
expr_block        ::= { stmt } expr
```

This distinction is important because the current `Surface` already distinguishes:

- statement lists
- expression blocks with a final required result expression

---

## 11. Error-shaping requirements for the parser

The reboot parser should diagnose at least:

- unexpected token
- unexpected end of input
- malformed type
- malformed item
- malformed place/lvalue
- missing `end`
- missing `next` in canonical loop forms
- malformed `switch` arm
- malformed aggregate field list

And should preserve enough source-position information to support later diagnostics.

Current bootstrap parser diagnostics should at least expose:

- `kind`
- `line`
- `col`
- `message`
- source offsets when available

---

## 12. Fast-parser implementation notes

Recommended implementation strategy:

- single-pass recursive descent + Pratt parser in Lua
- direct construction of `MoonliftSurface` ASDL nodes
- avoid generic table AST staging
- keep only parser state + temporary arrays
- preserve token line/column and byte offsets for diagnostics
- preserve literal raw strings exactly

This grammar is deliberately compatible with that implementation style.
