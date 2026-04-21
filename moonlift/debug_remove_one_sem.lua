package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path
local pvm = require('pvm')

local defs = dofile('moonlift/debug_bisect_sem.lua')
