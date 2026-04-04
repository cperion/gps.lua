-- uilib.lua
--
-- Public entrypoint for the UI library.
--
-- Architecture:
--   UI.Node    -- authored recursive ASDL tree
--   Facts.*    -- typed pass facts for measurement / constraints / frames
--   View.Cmd   -- flat static UI command array
--   Paint.*    -- generic custom-drawing tree + runtime paint commands
--   DS / Runtime -- design-system packs and generic runtime refs
--
-- Implementation lives in:
--   - uilib_asdl.lua
--   - uilib_impl.lua

return require("uilib_impl")
