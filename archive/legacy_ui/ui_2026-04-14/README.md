# ui/

Fresh UI library work lives here.

Modules:
- `ui/asdl.lua` — canonical type/schema layer
- `ui/ds.lua` — theme + surface helpers and DS resolution boundary
- `ui/lower.lua` — `SemUI -> UI` lowering
- `ui/session.lua` — explicit runtime state + messages + reducer wiring, including keyboard focus traversal and activation
- `ui/measure.lua` — concrete UI measurement reducer
- `ui/hit.lua` — hit-testing reducer
- `ui/draw.lua` — drawing reducer
- `ui/_flex.lua` — private shared flex kernel used by `ui/draw.lua`, `ui/hit.lua`, and `ui/measure.lua`
- `ui/init.lua` — public facade (`require("ui")` also works via root shim)
- `ui/demo/` — Love2D showcase app for the fresh UI stack, with DAW project ASDL, demo widget/view ASDL, `ui/demo/lower.lua`, and custom audio-oriented draw surfaces

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
- DS resolution and semantic lowering are the main scalar boundaries (`pvm.phase(name, fn)` + `pvm.one`, with `pvm.lower(...)` compatibility)
- runtime execution stays reducer-based
- flex layout is library-defined and CSS-inspired, but not a claim of full browser-flexbox parity
- `ui/draw.lua`, `ui/hit.lua`, and `ui/measure.lua` intentionally share one internal flex kernel for basis resolution, line collection, and main-size solving so reducers stay consistent

Focused flex regressions currently live in:
- `ui/test_flex.lua`
