-- asdl_context_wj.lua — retired experimental backend
--
-- The direct watjit-backed ASDL runtime experiment was removed.
-- Keep this module path as a compatibility shim so any stale callers
-- transparently use the stable GC-backed ASDL context.

return require("asdl_context")
