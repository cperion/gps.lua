#!/usr/bin/env luajit
-- lsp/bench_paper.lua
--
-- Wrapper for the comparable stdio benchmark.
-- Uses a Python client so both servers are measured through the same JSON-RPC path.

package.path = "./?.lua;./?/init.lua;" .. package.path

local cmd = "python3 lsp/bench_compare.py"
os.exit(os.execute(cmd) or 1)
