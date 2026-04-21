package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path
local pvm = require('pvm')
local Sem = require('moonlift.schemas.sem')
local T = pvm.context()
Sem.Define(T)
print('sem ok')
