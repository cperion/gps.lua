# Moonlift Grammar Reference

Status: parser-oriented grammar and precedence reference for the Moonlift source frontend.

This document complements:

- `moonlift/MOONLIFT_SPEC.md`
- `moonlift/MOONLIFT_NAMING.md`

It is intentionally focused on the frontend grammar rather than the full semantic rules.

---

## 1. Parsing model

Moonlift parsing happens at several fragment kinds.

Canonical host entry points:

- `ml.code[[ ... ]]` — exactly one top-level item
- `ml.module[[ ... ]]` — zero or more top-level items
- `ml.expr[[ ... ]]` — one expression
- `ml.type[[ ... ]]` — one type
- `ml.extern[[ ... ]]` — one or more extern declarations
- `ml.quote.func[[ ... ]]`, `ml.quote.expr[[ ... ]]`, etc. — typed quote fragments

The grammar below is written in a relaxed EBNF style.

Conventions:

- `[...]` = optional
- `{...}` = zero or more
- `|` = alternatives
- terminals are quoted
- names like `ident` and `expr` are grammar symbols

---

## 2. Lexical grammar

### 2.1 Whitespace

Whitespace separates tokens and is otherwise insignificant except inside strings/comments/splices.

```text
ws              ::= { " " | "\t" | "\r" | "\n" }
newline         ::= "\n" | "\r\n"
```

### 2.2 Comments

```text
line_comment    ::= "--" { any_char_except_newline }
block_comment   ::= "--[[" { any_char } "]]"
comment         ::= line_comment | block_comment
```

### 2.3 Identifiers

```text
ident_start     ::= "A".."Z" | "a".."z" | "_"
ident_rest      ::= ident_start | "0".."9"
ident           ::= ident_start { ident_rest }
```

### 2.4 Numeric literals

```text
dec_int         ::= digit { digit }
hex_int         ::= "0x" hex_digit { hex_digit }
float_lit       ::= dec_int "." dec_int [ exponent ]
                  | dec_int exponent
exponent        ::= ("e" | "E") ["+" | "-"] dec_int
int_lit         ::= dec_int | hex_int
number_lit      ::= float_lit | int_lit
```

### 2.5 Keywords

```text
keyword         ::= "func" | "extern" | "struct" | "union" | "tagged"
                  | "enum" | "slice" | "opaque" | "type" | "impl"
                  | "const" | "let" | "var" | "if" | "then"
                  | "elseif" | "else" | "while" | "do" | "for"
                  | "in" | "break" | "continue" | "return"
                  | "switch" | "case" | "default" | "end"
                  | "true" | "false" | "nil" | "pub" | "as"
                  | "cast" | "trunc" | "zext" | "sext" | "bitcast"
                  | "sizeof" | "alignof" | "offsetof"
                  | "load" | "store" | "memcpy" | "memmove"
                  | "memset" | "memcmp"
```

### 2.6 Punctuation and operators

```text
punct           ::= "(" | ")" | "[" | "]" | "{" | "}"
                  | "," | ":" | ";" | "." | "?" | "@"
                  | "->" | "="

operator        ::= "+" | "-" | "*" | "/" | "%"
                  | "==" | "~=" | "<" | "<=" | ">" | ">="
                  | "and" | "or" | "not"
                  | "&" | "|" | "~"
                  | "<<" | ">>" | ">>>"
```

---

## 3. Top-level fragment grammars

### 3.1 Code fragment

`ml.code[[...]]` parses exactly one top-level item.

```text
code_fragment   ::= ws item ws eof
```

### 3.2 Module fragment

```text
module_fragment ::= ws { item ws } eof
```

### 3.3 Expression fragment

```text
expr_fragment   ::= ws expr ws eof
```

### 3.4 Type fragment

```text
type_fragment   ::= ws type_expr ws eof
```

### 3.5 Extern fragment

```text
extern_fragment ::= ws extern_item { ws extern_item } ws eof
extern_item     ::= visibility? attributes? extern_func_decl
```

---

## 4. Items

### 4.1 Generic item form

```text
item            ::= visibility? attributes? item_core
visibility      ::= "pub"
attributes      ::= { attribute }
attribute       ::= "@" ident [ "(" [ attr_arg_list ] ")" ]
attr_arg_list   ::= attr_arg { "," attr_arg }
attr_arg        ::= number_lit | string_lit | ident
```

### 4.2 Item core

```text
item_core       ::= const_decl
                  | type_alias_decl
                  | struct_decl
                  | union_decl
                  | tagged_union_decl
                  | enum_decl
                  | opaque_decl
                  | slice_decl
                  | func_decl
                  | extern_func_decl
                  | impl_decl
```

### 4.3 Constants

```text
const_decl      ::= "const" ident [ ":" type_expr ] "=" expr
```

### 4.4 Type aliases

```text
type_alias_decl ::= "type" ident "=" type_expr
```

### 4.5 Structs

```text
struct_decl     ::= "struct" ident newline
                    { field_decl newline }
                    "end"

field_decl      ::= ident ":" type_expr
```

### 4.6 Unions

```text
union_decl      ::= "union" ident newline
                    { field_decl newline }
                    "end"
```

### 4.7 Tagged unions

```text
tagged_union_decl ::= "tagged" "union" ident [ ":" type_expr ] newline
                      { tagged_variant_decl newline }
                      "end"

tagged_variant_decl ::= ident newline
                        { field_decl newline }
                        "end"
```

### 4.8 Enums

```text
enum_decl       ::= "enum" ident [ ":" type_expr ] newline
                    { enum_member_decl newline }
                    "end"

enum_member_decl ::= ident [ "=" expr ]
```

### 4.9 Opaque types

```text
opaque_decl     ::= "opaque" ident
```

### 4.10 Slice declarations

Optional named slice sugar:

```text
slice_decl      ::= "slice" ident "=" type_expr
```

This is optional parser sugar over a named alias to `[]T`.

### 4.11 Functions

```text
func_decl       ::= "func" func_head block_end
func_head       ::= func_name "(" [ param_list ] ")" [ "->" type_expr ]
func_name       ::= ident | method_name | anon_func_name
method_name     ::= type_name ":" ident
anon_func_name  ::= "(" [ param_list ] ")" [ "->" type_expr ]
```

Parser note: in practice it is often simpler to split named and anonymous functions rather than use `func_head` exactly as written.

Recommended split:

```text
named_func_decl ::= "func" ident "(" [ param_list ] ")" [ "->" type_expr ] block_end
anon_func_decl  ::= "func" "(" [ param_list ] ")" [ "->" type_expr ] block_end
method_decl     ::= "func" type_name ":" ident "(" [ param_list ] ")" [ "->" type_expr ] block_end
```

### 4.12 Extern functions

```text
extern_func_decl ::= "extern" "func" ident "(" [ param_list ] ")" [ "->" type_expr ]
```

### 4.13 Impl blocks

```text
impl_decl       ::= "impl" type_name newline
                    { impl_item newline }
                    "end"

impl_item       ::= attributes? impl_func_decl
impl_func_decl  ::= "func" ident "(" [ param_list ] ")" [ "->" type_expr ] block_end
```

Semantic note: `impl` methods typically receive an explicit `self` parameter.

---

## 5. Type grammar

### 5.1 Type expression entry

```text
type_expr       ::= func_type
```

Function type is lowest-precedence in the type grammar.

### 5.2 Function types

```text
func_type       ::= pointer_type [ "->" type_expr ]
                  | "func" "(" [ type_list ] ")" [ "->" type_expr ]

type_list       ::= type_expr { "," type_expr }
```

Implementation note: a parser may choose to parse `func(...) -> T` as a dedicated type form before general type-expression fallback.

### 5.3 Pointer, array, slice, named, scalar

```text
pointer_type    ::= "&" pointer_type
                  | array_type

array_type      ::= "[" expr "]" type_expr
                  | "[]" type_expr
                  | primary_type

primary_type    ::= scalar_type
                  | qualified_type_name
                  | "(" type_expr ")"

qualified_type_name ::= ident { "." ident }
```

### 5.4 Scalars

```text
scalar_type     ::= "void" | "bool"
                  | "i8" | "i16" | "i32" | "i64"
                  | "u8" | "u16" | "u32" | "u64"
                  | "isize" | "usize"
                  | "f32" | "f64"
                  | "byte"
```

---

## 6. Parameter grammar

```text
param_list      ::= param { "," param }
param           ::= ident ":" type_expr
```

Optional future extensions such as default values, passing attributes, and ABI modifiers should not be added to the core grammar until semantics are settled.

---

## 7. Block grammar

Moonlift uses explicit `end`-terminated blocks.

```text
block_end       ::= newline { stmt_sep stmt } [ stmt_sep ] "end"
stmt_sep        ::= newline | ";"
```

Implementation note: a real parser usually needs a more precise “block item until keyword set” rule instead of the simplified grammar above.

---

## 8. Statement grammar

```text
stmt            ::= let_stmt
                  | var_stmt
                  | assign_stmt
                  | if_stmt
                  | while_stmt
                  | for_stmt
                  | switch_stmt
                  | break_stmt
                  | continue_stmt
                  | return_stmt
                  | memory_stmt
                  | expr_stmt
```

### 8.1 Local bindings

```text
let_stmt        ::= "let" ident [ ":" type_expr ] "=" expr
var_stmt        ::= "var" ident [ ":" type_expr ] "=" expr
```

### 8.2 Assignment

```text
assign_stmt     ::= lvalue "=" expr
```

### 8.3 If statement

```text
if_stmt         ::= "if" expr "then" block_body
                    { "elseif" expr "then" block_body }
                    [ "else" block_body ]
                    "end"

block_body      ::= newline { stmt_sep stmt }
```

### 8.4 While loop

```text
while_stmt      ::= "while" expr "do" block_body "end"
```

### 8.5 For loop

Numeric form:

```text
for_stmt        ::= "for" ident "=" expr "," expr [ "," expr ] "do" block_body "end"
```

Future iterator forms should use a different grammar arm.

### 8.6 Switch statement

```text
switch_stmt     ::= "switch" expr "do"
                    { switch_case }
                    [ switch_default ]
                    "end"

switch_case     ::= "case" expr "then" block_body
switch_default  ::= "default" "then" block_body
```

### 8.7 Break / continue / return

```text
break_stmt      ::= "break"
continue_stmt   ::= "continue"
return_stmt     ::= "return" [ expr ]
```

### 8.8 Memory statements

```text
memory_stmt     ::= "memcpy"  "(" expr "," expr "," expr ")"
                  | "memmove" "(" expr "," expr "," expr ")"
                  | "memset"  "(" expr "," expr "," expr ")"
                  | "store"   "<" type_expr ">" "(" expr "," expr ")"
```

### 8.9 Expression statement

```text
expr_stmt       ::= expr
```

---

## 9. Expression grammar overview

Expressions are parsed with precedence.

High-level shape:

```text
expr            ::= if_expr
                  | switch_expr
                  | assignment_expr
```

If `switch` is expression-valued in the current context, it uses `switch_expr`; otherwise the statement form applies.

A Pratt parser or precedence-climbing parser is the recommended implementation strategy.

---

## 10. Expression precedence table

From lowest to highest:

1. `if ... then ... else ... end`
2. `switch ... do ... end`
3. `or`
4. `and`
5. comparisons: `== ~= < <= > >=`
6. bitwise or: `|`
7. bitwise xor: `~`
8. bitwise and: `&`
9. shifts: `<< >> >>>`
10. additive: `+ -`
11. multiplicative: `* / %`
12. unary: `- not ~ & *`
13. postfix: call, method call, indexing, field access
14. primary

Postfix forms are left-associative.
Unary operators associate right-to-left.
Binary operators are left-associative except where future semantic reasons require otherwise.

---

## 11. Expression grammar by precedence

### 11.1 If expression

```text
if_expr         ::= "if" expr "then" expr_block
                    { "elseif" expr "then" expr_block }
                    "else" expr_block
                    "end"
                  | switch_expr

expr_block      ::= block_expr | expr
```

### 11.2 Switch expression

```text
switch_expr     ::= "switch" expr "do"
                    { switch_expr_case }
                    switch_expr_default
                    "end"
                  | or_expr

switch_expr_case    ::= "case" expr "then" expr_block
switch_expr_default ::= "default" "then" expr_block
```

### 11.3 Logical expressions

```text
or_expr         ::= and_expr { "or" and_expr }
and_expr        ::= compare_expr { "and" compare_expr }
```

### 11.4 Comparison expressions

```text
compare_expr    ::= bit_or_expr { compare_op bit_or_expr }
compare_op      ::= "==" | "~=" | "<" | "<=" | ">" | ">="
```

### 11.5 Bitwise expressions

```text
bit_or_expr     ::= bit_xor_expr { "|" bit_xor_expr }
bit_xor_expr    ::= bit_and_expr { "~" bit_and_expr }
bit_and_expr    ::= shift_expr   { "&" shift_expr }
```

### 11.6 Shift expressions

```text
shift_expr      ::= add_expr { shift_op add_expr }
shift_op        ::= "<<" | ">>" | ">>>"
```

### 11.7 Arithmetic expressions

```text
add_expr        ::= mul_expr { add_op mul_expr }
add_op          ::= "+" | "-"

mul_expr        ::= unary_expr { mul_op unary_expr }
mul_op          ::= "*" | "/" | "%"
```

### 11.8 Unary expressions

```text
unary_expr      ::= unary_op unary_expr
                  | postfix_expr

unary_op        ::= "-" | "not" | "~" | "&" | "*"
```

### 11.9 Postfix expressions

```text
postfix_expr    ::= primary_expr { postfix_suffix }

postfix_suffix  ::= field_suffix
                  | index_suffix
                  | call_suffix
                  | method_call_suffix

field_suffix        ::= "." ident
index_suffix        ::= "[" expr "]"
call_suffix         ::= "(" [ arg_list ] ")"
method_call_suffix  ::= ":" ident "(" [ arg_list ] ")"
arg_list            ::= expr { "," expr }
```

### 11.10 Primary expressions

```text
primary_expr    ::= literal
                  | qualified_name
                  | aggregate_literal
                  | cast_expr
                  | intrinsic_expr
                  | block_expr
                  | "(" expr ")"
                  | splice_expr
                  | hole_expr
                  | anon_func_expr
```

### 11.11 Qualified names

```text
qualified_name  ::= ident { "." ident }
```

### 11.12 Literals

```text
literal         ::= number_lit
                  | "true"
                  | "false"
                  | "nil"
                  | string_lit
```

String literals are grammar-level tokens even if the semantic layer restricts where they may appear.

### 11.13 Aggregate literals

```text
aggregate_literal ::= type_ctor "{" [ aggregate_fields ] "}"

type_ctor          ::= qualified_name
                     | array_type_ctor

array_type_ctor    ::= "[" expr "]" type_expr

aggregate_fields   ::= aggregate_field { "," aggregate_field } [ "," ]
aggregate_field    ::= ident "=" expr
                     | expr
```

The semantic layer determines whether positional aggregate fields are allowed for a given type.

### 11.14 Cast expressions

```text
cast_expr       ::= cast_head "<" type_expr ">" "(" expr ")"
cast_head       ::= "cast" | "trunc" | "zext" | "sext" | "bitcast"
```

### 11.15 Intrinsic expressions

```text
intrinsic_expr  ::= "sizeof"  "(" type_expr ")"
                  | "alignof" "(" type_expr ")"
                  | "offsetof" "(" type_expr "," ident ")"
                  | "load" "<" type_expr ">" "(" expr ")"
                  | "memcmp" "(" expr "," expr "," expr ")"
```

### 11.16 Block expressions

```text
block_expr      ::= "do" block_body "end"
```

### 11.17 Anonymous function expressions

```text
anon_func_expr  ::= "func" "(" [ param_list ] ")" [ "->" type_expr ] block_end
```

### 11.18 Splices

```text
splice_expr     ::= "@" "{" host_source "}"
```

The parser typically treats the body of a splice as host-language text captured lexically rather than recursively parsed as Moonlift grammar.

### 11.19 Typed holes

```text
hole_expr       ::= "?" ident ":" type_expr
```

---

## 12. Lvalue grammar

The parser can parse assignable syntax without proving assignability; semantic validation happens later.

```text
lvalue          ::= postfix_expr
```

Semantic analysis later restricts valid assignment targets to:

- mutable locals
- field projections of assignable values
- index projections of assignable values
- dereference-compatible forms

---

## 13. Strings

If string literals are admitted lexically, recommended grammar is:

```text
string_lit      ::= short_string | long_string
short_string    ::= '"' { short_char } '"'
                  | "'" { short_char } "'"
long_string     ::= "[[" { any_char } "]]"
```

Implementations may choose Lua-like long-string support or restrict source strings to short quoted strings for simplicity.

---

## 14. Ambiguity notes

### 14.1 `&` as unary and binary
`&` is both:

- unary address-of
- binary bitwise-and

Pratt parsing cleanly handles this with prefix and infix parselets.

### 14.2 `*` as unary and binary
`*` is both:

- unary dereference
- binary multiply

Again, prefix + infix parselets are recommended.

### 14.3 Method declarations vs method calls
These are distinct:

```text
func Pair:sum() -> i32
```

vs.

```text
p:sum()
```

The former appears only in item position.
The latter appears only in expression postfix position.

### 14.4 Anonymous `func` vs parenthesized expressions
At primary-expression position:

- `func (...) ... end` starts an anonymous function expression
- `(expr)` is a grouped expression

### 14.5 Aggregate literal vs block/statement start
Because aggregates use `TypeName { ... }`, the parser needs type/name resolution hints or a syntactic rule that only certain primaries may introduce aggregate literals.

Recommended parser strategy:

- parse `qualified_name` first
- if immediately followed by `{`, parse aggregate literal
- defer exact type validity to semantic analysis

---

## 15. Recommended parser architecture

### 15.1 Frontend structure
Recommended Rust frontend split:

- `src/lexer.rs`
- `src/parser.rs`
- `src/ast.rs`
- `src/source.rs`
- `src/diag.rs`

### 15.2 Parser strategy
Recommended strategy:

- recursive descent for items/statements/types
- Pratt parser or precedence-climbing parser for expressions
- explicit span tracking on all tokens and AST nodes

### 15.3 Recovery
Recommended minimal recovery:

- synchronize at `end`
- synchronize at top-level item starts
- preserve spans for broken nodes
- report one primary parse error and continue when practical

---

## 16. Canonical examples by fragment kind

### 16.1 `ml.code`

```lua
local add = ml.code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]]
```

### 16.2 `ml.module`

```lua
local mod = ml.module[[
struct Pair
    a: i32
    b: i32
end

func pair_sum(p: &Pair) -> i32
    return p.a + p.b
end
]]
```

### 16.3 `ml.expr`

```lua
local e = ml.expr[[
cast<i64>(x + 1)
]]
```

### 16.4 `ml.type`

```lua
local t = ml.type[[
func(&u8, usize) -> void
]]
```

### 16.5 `ml.quote.func`

```lua
local q = ml.quote.func[[
func (x: i32) -> i32
    return x + 1
end
]]
```

---

## 17. Summary

Canonical Moonlift grammar choices are:

- host entrypoint: `ml.code`
- function keyword: `func`
- function-type spelling: `func(...) -> T`
- explicit `end`-terminated blocks
- Pratt-style expression precedence
- typed holes: `?name: Type`
- host splices: `@{ ... }`

This document is the parser-focused reference; the semantic source of truth remains `moonlift/MOONLIFT_SPEC.md`.
