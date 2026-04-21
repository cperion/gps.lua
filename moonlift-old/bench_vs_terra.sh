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
echo "║          Moonlift (Cranelift) vs Terra (LLVM) — Head-to-Head               ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Run Terra
TERRA_OUT=$(mktemp)
"$TERRA" examples/bench_terra.lua > "$TERRA_OUT" 2>&1

# Run Moonlift
ML_OUT=$(mktemp)
"$MOONLIFT" run examples/bench_moonlift_vs_terra.lua > "$ML_OUT" 2>&1

# Parse results
declare -A terra_times ml_times terra_results ml_results

while read -r name time result; do
    terra_times["$name"]="$time"
    terra_results["$name"]="$result"
done < "$TERRA_OUT"

while read -r name time result; do
    ml_times["$name"]="$time"
    ml_results["$name"]="$result"
done < "$ML_OUT"

# Compile time comparison
terra_compile="${terra_times[COMPILE_ALL]}"
ml_compile="${ml_times[COMPILE_ALL]}"
ratio=$(awk "BEGIN { printf \"%.1f\", $terra_compile / $ml_compile }")
printf "  COMPILATION (8 functions)\n"
printf "    Terra (LLVM):    %8.2f ms\n" "$(awk "BEGIN { printf \"%.2f\", $terra_compile * 1000 }")"
printf "    Moonlift (CL):   %8.2f ms\n" "$(awk "BEGIN { printf \"%.2f\", $ml_compile * 1000 }")"
printf "    Moonlift compiles %sx faster\n" "$ratio"
echo ""

# Runtime comparison table
printf "  %-16s %10s %10s %7s  %s\n" \
    "BENCHMARK" "TERRA" "MOONLIFT" "RATIO" "RESULT"
printf "  %-16s %10s %10s %7s  %s\n" \
    "────────────────" "──────────" "──────────" "───────" "──────"

benchmarks=(sum_loop collatz mandelbrot poly_grid popcount fib_sum gcd_sum switch_sum)
bench_desc=(
    "int accumulate"
    "branch-heavy"
    "fp + branch"
    "nested fp"
    "bitwise"
    "data-dep"
    "division"
    "if-chain"
)

total_terra=0
total_ml=0
idx=0

for name in "${benchmarks[@]}"; do
    t_time="${terra_times[$name]:-0}"
    m_time="${ml_times[$name]:-0}"
    t_res="${terra_results[$name]:-?}"
    m_res="${ml_results[$name]:-?}"

    t_ms=$(awk "BEGIN { printf \"%.2f\", $t_time * 1000 }")
    m_ms=$(awk "BEGIN { printf \"%.2f\", $m_time * 1000 }")

    if (( $(awk "BEGIN { print ($t_time > 0.000001) }") )); then
        ratio=$(awk "BEGIN { printf \"%.2f\", $m_time / $t_time }")
    else
        ratio="inf"
    fi

    # Check result match
    t_short=$(echo "$t_res" | cut -c1-10)
    m_short=$(echo "$m_res" | cut -c1-10)
    if [ "$t_short" = "$m_short" ]; then
        check="OK"
    else
        check="MISMATCH"
    fi

    # Format with bar indicator
    if (( $(awk "BEGIN { print ($t_time < 0.000001) }") )); then
        indicator=">>"
    elif (( $(awk "BEGIN { print ($m_time <= $t_time * 1.05) }") )); then
        indicator="<="
    elif (( $(awk "BEGIN { print ($m_time <= $t_time * 1.5) }") )); then
        indicator="~"
    else
        indicator=">>"
    fi

    printf "  %-16s %8s ms %8s ms  %5sx %s  %s\n" \
        "$name" "$t_ms" "$m_ms" "$ratio" "$indicator" "$check"

    total_terra=$(awk "BEGIN { printf \"%.6f\", $total_terra + $t_time }")
    total_ml=$(awk "BEGIN { printf \"%.6f\", $total_ml + $m_time }")
    idx=$((idx + 1))
done

echo ""
overall=$(awk "BEGIN { printf \"%.2f\", $total_ml / $total_terra }")
printf "  %-16s %8s ms %8s ms  %5sx\n" \
    "TOTAL" \
    "$(awk "BEGIN { printf \"%.2f\", $total_terra * 1000 }")" \
    "$(awk "BEGIN { printf \"%.2f\", $total_ml * 1000 }")" \
    "$overall"

echo ""
echo "  RATIO = moonlift / terra  (1.00 = same speed, <1 = moonlift faster)"
echo "  <= means within 5%, ~ means within 50%, >> means terra significantly faster"
echo ""

rm -f "$TERRA_OUT" "$ML_OUT"
