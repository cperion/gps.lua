#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")"

MOONLIFT="./target/release/moonlift"
TERRA="terra"

if ! command -v "$TERRA" &>/dev/null; then
    echo "ERROR: terra not found in PATH" >&2
    exit 1
fi
if [ ! -x "$MOONLIFT" ]; then
    echo "Building moonlift release..."
    cargo build --release 2>&1 | tail -1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║     Moonlift (Cranelift) vs Terra (LLVM) vs raw LuaJIT — Head-to-Head      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

TERRA_OUT=$(mktemp)
ML_OUT=$(mktemp)
LJ_OUT=$(mktemp)
trap 'rm -f "$TERRA_OUT" "$ML_OUT" "$LJ_OUT"' EXIT

"$TERRA" examples/bench_terra.lua > "$TERRA_OUT" 2>&1
"$MOONLIFT" run examples/bench_moonlift_vs_terra.lua > "$ML_OUT" 2>&1
"$MOONLIFT" run examples/bench_luajit_raw.lua > "$LJ_OUT" 2>&1

declare -A terra_times ml_times lj_times
declare -A terra_results ml_results lj_results

while read -r name time result; do
    terra_times["$name"]="$time"
    terra_results["$name"]="$result"
done < "$TERRA_OUT"

while read -r name time result; do
    ml_times["$name"]="$time"
    ml_results["$name"]="$result"
done < "$ML_OUT"

while read -r name time result; do
    lj_times["$name"]="$time"
    lj_results["$name"]="$result"
done < "$LJ_OUT"

printf "  COMPILATION / LOAD\n"
printf "    Terra compile:      %8.2f ms\n" "$(awk "BEGIN { printf \"%.2f\", ${terra_times[COMPILE_ALL]} * 1000 }")"
printf "    Moonlift compile:   %8.2f ms\n" "$(awk "BEGIN { printf \"%.2f\", ${ml_times[COMPILE_ALL]} * 1000 }")"
printf "    raw LuaJIT load:    %8.2f ms\n" "$(awk "BEGIN { printf \"%.2f\", ${lj_times[COMPILE_ALL]} * 1000 }")"
printf "    Moonlift vs Terra:  %8.2fx faster compile\n" "$(awk "BEGIN { printf \"%.2f\", ${terra_times[COMPILE_ALL]} / ${ml_times[COMPILE_ALL]} }")"
echo ""

printf "  %-14s %10s %10s %10s %9s %9s  %s\n" \
    "BENCHMARK" "TERRA" "MOONLIFT" "LUAJIT" "ML/T" "ML/LJ" "RESULT"
printf "  %-14s %10s %10s %10s %9s %9s  %s\n" \
    "──────────────" "──────────" "──────────" "──────────" "─────────" "─────────" "──────"

benchmarks=(sum_loop collatz mandelbrot poly_grid popcount fib_sum gcd_sum switch_sum)
for name in "${benchmarks[@]}"; do
    t_time="${terra_times[$name]:-0}"
    m_time="${ml_times[$name]:-0}"
    l_time="${lj_times[$name]:-0}"
    t_res="${terra_results[$name]:-?}"
    m_res="${ml_results[$name]:-?}"
    l_res="${lj_results[$name]:-?}"

    t_ms=$(awk "BEGIN { printf \"%.2f\", $t_time * 1000 }")
    m_ms=$(awk "BEGIN { printf \"%.2f\", $m_time * 1000 }")
    l_ms=$(awk "BEGIN { printf \"%.2f\", $l_time * 1000 }")

    if (( $(awk "BEGIN { print ($t_time > 0.000001) }") )); then
        ml_t=$(awk "BEGIN { printf \"%.2f\", $m_time / $t_time }")
    else
        ml_t="inf"
    fi
    if (( $(awk "BEGIN { print ($l_time > 0.000001) }") )); then
        ml_lj=$(awk "BEGIN { printf \"%.2f\", $m_time / $l_time }")
    else
        ml_lj="inf"
    fi

    t_short=$(echo "$t_res" | cut -c1-14)
    m_short=$(echo "$m_res" | cut -c1-14)
    l_short=$(echo "$l_res" | cut -c1-14)
    if [ "$t_short" = "$m_short" ] && [ "$m_short" = "$l_short" ]; then
        check="OK"
    else
        check="CHECK"
    fi

    printf "  %-14s %8s ms %8s ms %8s ms %7sx %7sx  %s\n" \
        "$name" "$t_ms" "$m_ms" "$l_ms" "$ml_t" "$ml_lj" "$check"
done

echo ""
echo "  ML/T  = Moonlift / Terra  (<1 means Moonlift faster)"
echo "  ML/LJ = Moonlift / raw LuaJIT  (<1 means Moonlift faster)"
echo "  sum_loop is not a fair Terra runtime benchmark because LLVM folds it heavily"
echo "  raw LuaJIT fib_sum uses FFI int64 to preserve wrapped i64 semantics"
