#!/bin/bash
# lsp/bench_luals.sh — Time LuaLS on generated files of various sizes
set -e

LUALS="$HOME/.local/share/nvim/mason/bin/lua-language-server"
cd "$(dirname "$0")/.."

gen_file() {
    local n=$1
    local f="/tmp/bench_lua_${n}.lua"
    {
        echo "---@class TestClass"
        echo "---@field name string"  
        echo "---@field id number"
        echo "local M = {}"
        echo ""
        for i in $(seq 1 $n); do
            echo "local v${i} = ${i}"
        done
        echo ""
        echo "function M.process(x, y)"
        echo "    return x + y"
        echo "end"
        echo ""
        echo "print(v1, v${n})"
        echo "print(undefined_global)"
        echo "return M"
    } > "$f"
    echo "$f"
}

run_luals() {
    local file="$1"
    local uri="file://$(realpath "$file")"
    local text
    text=$(cat "$file")
    
    python3 -c "
import json, sys
def msg(obj):
    body = json.dumps(obj)
    return f'Content-Length: {len(body)}\r\n\r\n{body}'
uri = sys.argv[1]
text = open(sys.argv[2]).read()
msgs = [
    msg({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'processId':1,'rootUri':'file://$(pwd)','capabilities':{'textDocument':{'diagnostic':{'dynamicRegistration':False}}}}}),
    msg({'jsonrpc':'2.0','method':'initialized','params':{}}),
    msg({'jsonrpc':'2.0','method':'textDocument/didOpen','params':{'textDocument':{'uri':uri,'languageId':'lua','version':1,'text':text}}}),
    msg({'jsonrpc':'2.0','id':2,'method':'textDocument/diagnostic','params':{'textDocument':{'uri':uri}}}),
    msg({'jsonrpc':'2.0','id':3,'method':'shutdown'}),
    msg({'jsonrpc':'2.0','method':'exit'}),
]
sys.stdout.buffer.write(''.join(msgs).encode())
" "$uri" "$file" | timeout 30 "$LUALS" --stdio > /tmp/luals_resp.bin 2>/dev/null
    
    grep -c "Content-Length" /tmp/luals_resp.bin 2>/dev/null || echo 0
}

echo "=== lua-language-server $(${LUALS} --version) ==="
echo ""
printf "  %-35s %10s %10s %6s\n" "file" "wall(ms)" "lines" "resps"
echo "  -----------------------------------------------------------"

for n in 50 200 500 1000; do
    f=$(gen_file $n)
    lines=$(wc -l < "$f")
    t0=$(date +%s%N)
    resps=$(run_luals "$f")
    t1=$(date +%s%N)
    ms=$(( ($t1 - $t0) / 1000000 ))
    printf "  %-35s %8d ms %8d %6s\n" "${n} locals" "$ms" "$lines" "$resps"
done

for real in pvm.lua triplet.lua asdl_context.lua lsp/semantics.lua lsp/parser.lua; do
    if [ -f "$real" ]; then
        lines=$(wc -l < "$real")
        t0=$(date +%s%N)
        resps=$(run_luals "$real")
        t1=$(date +%s%N)
        ms=$(( ($t1 - $t0) / 1000000 ))
        printf "  %-35s %8d ms %8d %6s\n" "$real" "$ms" "$lines" "$resps"
    fi
done
