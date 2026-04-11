-- ui/demo/view.lua
-- Compatibility shim.
--
-- The demo widget/view layer is now modeled in ASDL inside `ui/demo/asdl.lua`
-- as `DemoView`. This module just exposes that namespace.

local schema = require("ui.demo.asdl")

return {
    T = schema.T.DemoView,
    schema = schema,
}
