# ui/

The previous `ui/` implementation was archived to:

- `archive/legacy_ui/ui_2026-04-14/`

This directory is now intentionally reset for a fresh UI restart.

Current fresh-start files:
- `ui/asdl.lua` — v1 schema draft for authored UI, style tokens/specs, theme, layout, resolved style, view, interaction, and solve env
- `ui/tw.lua` — typed Tailwind-style utility surface over `Style.Token`
- `ui/build.lua` — immediate-mode builders for `Auth.Box`, `Auth.Text`, and `Auth.Fragment`
- `ui/normalize.lua` — canonical style normalization boundary (`Style.TokenList × Env.Class → Style.Spec`)
- `ui/resolve.lua` — theme resolution boundary (`Style.Spec × Theme.T → Resolve.Style`)
- `ui/lower.lua` — lowering boundary from authored nodes to concrete layout nodes (`Auth.Node × Theme.T × Env.Class → Layout.Node`)
- `ui/measure.lua` — measurement boundary for lowered layout nodes (`Layout.Node × Layout.Constraint → Layout.Size`) plus cached text layout approximation
- `ui/solve.lua` — solve/place boundary from layout nodes to flat `View.Frame` output (`Layout.Node × Solve.Env → View.Frame`)
- `ui/init.lua` — minimal facade exposing `ui.asdl`, `ui.T`, `ui.tw`, `ui.build`, `ui.normalize`, `ui.resolve`, `ui.lower`, `ui.measure`, and `ui.solve`

Near-term next steps:
- tighten flex and grid measurement / placement semantics toward full correctness
- replace the temporary text layout approximation with real backend text shaping/measurement
- add a rendering backend and demo loop on top of `View.Frame`
- port code back selectively from the archived snapshot if needed
