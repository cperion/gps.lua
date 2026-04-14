# LSP Bug Tracker

Updated: 2026-04-12

## Resolved

### [fixed] Completion prefix extraction broken on non-first lines
- **Area:** `lsp/server.lua` (`Core:completion`)
- **Symptom:** completions on line > 0 were effectively unfiltered (prefix became empty).
- **Root cause:** line splitting used `gmatch("[^\n]*")`, which inserts empty matches between lines.
- **Fix:** compute prefix from exact line bounds + UTF-16→byte conversion.
- **Regression test:** `lsp/test_features.lua` (`Test 5b`).

### [fixed] JSON `\uXXXX` surrogate pairs decoded as invalid UTF-8
- **Area:** `lsp/jsonrpc.lua` (`json_decode` / `parse_string`)
- **Symptom:** `"\uD83D\uDE00"` decoded to CESU-8 bytes instead of a single UTF-8 code point.
- **Fix:** combine high+low surrogate pairs; map unpaired surrogates to U+FFFD.
- **Regression test:** `lsp/test_jsonrpc.lua`.

### [fixed] Initialize result missed standard `positionEncoding`
- **Area:** `lsp/jsonrpc.lua` (`capabilities_to_lua`)
- **Symptom:** only `offsetEncoding` was advertised.
- **Fix:** add `positionEncoding = "utf-16"` (keep `offsetEncoding` for compatibility).
- **Regression test:** `lsp/test_jsonrpc.lua`.

### [fixed] JSON-RPC error responses with `id: null` omitted the `id` key
- **Area:** `lsp/jsonrpc.lua` (`rpc_id_to_lua`)
- **Symptom:** `RpcIdNull` serialized as missing `id` instead of `"id": null`.
- **Fix:** map `RpcIdNull` to `JsonRpc.JSON_NULL` using singleton-safe tag extraction.
- **Regression test:** `lsp/test_jsonrpc.lua`.

## Open

### [fixed] JSON `null` fields are preserved on decode
- **Area:** `lsp/jsonrpc.lua` (`json_decode`)
- **Symptom:** object fields with `null` were dropped (`{"x":null}` => `x == nil`).
- **Fix:** decode `null` as `JsonRpc.JSON_NULL` sentinel; normalize request params to `{}` when needed.
- **Extra:** invalid non-string `method` now returns JSON-RPC `-32600` (`Invalid Request`) instead of internal error.
- **Extra:** client response objects (no `method`) are now ignored cleanly.
- **Regression test:** `lsp/test_jsonrpc.lua`.

### [open] `codeAction/resolve` input loses multi-file edits
- **Area:** `lsp/server.lua` (`code_action_from_lua`)
- **Symptom:** only one `edit.changes[uri]` entry is representable; others are ignored.
- **Impact:** medium for multi-file code actions.
- **Constraint:** current ASDL `LspWorkspaceEdit` models only one URI + edits list.
- **Current mitigation:** selection is now deterministic (sorted URI) instead of `pairs()` order; `documentChanges` fallback is accepted (first text-document edit set).
- **Suggested fix:** extend ASDL to represent full `changes` map (or `documentChanges`).
