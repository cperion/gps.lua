# json

pvm-native JSON stack.

## Modules

- `json/asdl.lua` — exact `Json.Value` language + public constructors
- `json/build.lua` — tiny parser-private exact-tree builder
- `json/parse.lua` — strict fused parser: text -> `Json.Value`
- `json/emit.lua` — compact emitter phase: `Json.Value` -> chunk stream
- `json/format_asdl.lua` — flat formatting command vocabulary for pretty output
- `json/pretty.lua` — pretty lowering: `Json.Value` -> `JsonFmt.Cmd*`
- `json/encode.lua` — convenience wrappers: compact/pretty strings and chunk drains
- `json/decode.lua` — exact-tree helpers (`as_string`, `get`, etc.)
- `json/project.lua` — secondary Lua -> `Json.Value` bridge
- `json/policy_asdl.lua` — minimal semantic policy ASDL
- `json/policy.lua` — policy constructors/helpers
- `json/policy_decode.lua` — policy-guided decode boundary
- `json/typed.lua` — helper for building typed decoders
- `json/init.lua` — public facade

## Architecture

This stack follows the compiler pattern used throughout the repo:

- exact JSON is the source language
- parsing is a fused frontend, not a phase tower
- the parser scans bytes directly and delegates exact-tree construction to a tiny builder layer
- semantic decoding is a boundary
- emission is a boundary
- pretty printing lowers into a flat formatting command stream
- performance comes first from modeling, reuse, and fusion

## Parse/build split

The JSON implementation now has a deliberate three-part split:

- `json/asdl.lua` defines the exact public semantic model
- `json/build.lua` is a tiny parser-private exact-tree builder
- `json/parse.lua` is the fused frontend

In particular, object parsing now collects `keys[]` and `vals[]` in the parser
and finalizes them once through `build.obj_pairs(keys, vals, n)`. This keeps
parser logic focused on syntax while keeping exact-tree construction local and
simple.

## Typical flows

### Exact roundtrip

```lua
local json = require("json")
local value = json.parse_string('{"a":1,"b":[true,null]}')
print(json.compact(value))
print(json.pretty_string(value))
```

### Policy-guided decode

```lua
local json = require("json")
local policy = require("json.policy")

local spec = policy.object({
    policy.field("name", policy.Str),
    policy.field("enabled", policy.Bool, policy.default_bool(true)),
})

local value = json.parse_string('{"name":"demo"}')
local obj = json.policy_decode.decode(spec, value)
```

### Typed decoder

```lua
local typed = require("json.typed")
local decode_config = typed.decoder("decode_config", spec, function(obj)
    return Config(obj.name, obj.enabled)
end)
```

See `examples/` and `bench/` for runnable demos.
