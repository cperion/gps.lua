# ui/

Fresh UI library work lives here.

Planned modules:
- `ui/asdl.lua` — canonical type/schema layer
- `ui/ds.lua` — theme + surface helpers and DS resolution boundary
- `ui/lower.lua` — `SemUI -> UI` lowering
- `ui/session.lua` — explicit runtime state + messages
- `ui/measure.lua` — concrete UI measurement reducer
- `ui/hit.lua` — hit-testing reducer
- `ui/draw.lua` — drawing reducer
- `ui/init.lua` — public facade

Architecture:
- app/domain semantics stay outside the library
- library owns generic UI semantics only
- DS resolution and semantic lowering are the main `pvm3.lower(...)` boundaries
- runtime execution stays reducer-based
