#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

print("bench/pvm_ffi_pod_bench.lua")
print("legacy benchmark name retained for compatibility")
print("pvm is now handle-only; forwarding to handle benchmark")
print()

dofile("./bench/pvm_handle_storage_bench.lua")
