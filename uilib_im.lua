-- uilib_im.lua — removed trial module; kept as compatibility shim.
--
-- The old immediate-mode trial has been folded into canonical `uilib`.
-- Existing `require("uilib_im")` callers now get the same
-- immediate/session-based API surface as `require("uilib")`.

return require("uilib")
