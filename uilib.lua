-- uilib.lua
--
-- Canonical public entrypoint.
--
-- The immediate/session-based implementation now lives in `uilib_iter.lua`.
-- It still reuses the retained-path machinery internally for compatibility APIs
-- such as static compile/fragment/assemble where needed, but the primary runtime
-- model is immediate traversal over the UI param tree.

return require("uilib_iter")
