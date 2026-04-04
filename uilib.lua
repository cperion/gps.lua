-- uilib.lua
--
-- Public entrypoint for the redesigned UI library.
--
-- Architecture:
--   UI.Node   -- authored recursive ASDL tree
--   Facts.*   -- typed pass facts for measurement / constraints / frames
--   View.Cmd  -- flat executable command array
--
-- There is intentionally no recursive Layout.Node layer.
--
-- Implementation lives in:
--   - uilib_asdl.lua
--   - uilib_impl.lua

return require("uilib_impl")
