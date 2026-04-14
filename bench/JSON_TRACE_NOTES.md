# JSON trace/profile notes

Repeatable profiling entrypoints:

- `luajit bench/json_parse_profile.lua`
- `luajit bench/json_parse_trace.lua`
- `luajit bench/json_vs_cjson.lua`

Current observed bottlenecks for `json.parse_string(...)` on large objects:

1. `json/parse.lua`
   - `skip_ws()` byte scanning
   - `parse_string_raw()` string scan / closing-quote path
   - `parse_number_node()` digit scan loops
   - object recursion via `parse_value()`

2. `asdl_context.lua`
   - constructor normalization (`normalize_field` path)
   - list checking/interning for `Member*` and `Value*`
   - repeated list walks in `make_list_check(...)`

Key architectural conclusion:

- cold parse is not only a scanner problem
- a major part of parse cost comes from exact ASDL constructor validation + list interning
- to approach `cjson`, we likely need parser-trusted construction paths that preserve exact ASDL/interning semantics while bypassing redundant re-validation

This matches the compiler-pattern emphasis: optimization begins with structure and boundary design, not isolated micro-ops.
