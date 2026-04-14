# archive/

This folder holds legacy code while the new UI library is restarted fresh under `ui/`.

Current layout:
- `archive/legacy_ui/` — prior `uilib*` attempts, tests, docs, example UIs, and archived `ui/` snapshots such as `ui_2026-04-14/` and `ui_2026-04-14_attempt1/`
- `archive/legacy_vm/` — prior `pvm*`, `uvm*`, `gps.lua` / `ugps.lua`, plus related benches/tests/traces

Legacy root files have been moved out of the active tree into these archive folders.
The fresh canonical UI work should go only into `ui/`.

The active root `pvm.lua` is now the fused canonical pvm (recording-boundary model + ASDL foundation), and root `pvm3.lua` is only a compatibility shim.
