# ui/

Fresh UI library work lives here.

Modules:
- `ui/asdl.lua` — canonical type/schema layer
- `ui/ds.lua` — theme + surface helpers and DS resolution boundary
- `ui/lower.lua` — `SemUI -> UI` lowering
- `ui/session.lua` — explicit runtime state + messages + reducer wiring
- `ui/measure.lua` — concrete UI measurement reducer
- `ui/hit.lua` — hit-testing reducer
- `ui/draw.lua` — drawing reducer
- `ui/init.lua` — public facade
- `ui/demo/` — Love2D showcase app for the fresh UI stack

Implemented now:
- `ui/asdl.lua`
- `ui/ds.lua`
- `ui/lower.lua`
- `ui/session.lua`
- `ui/measure.lua`
- `ui/hit.lua`
- `ui/draw.lua`
- `ui/init.lua`
- `ui/demo/`

Architecture:
- app/domain semantics stay outside the library
- library owns generic UI semantics only
- DS resolution and semantic lowering are the main `pvm3.lower(...)` boundaries
- runtime execution stays reducer-based
