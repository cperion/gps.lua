#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE="$ROOT/third_party/wasmtime"

if [ ! -d "$SUBMODULE/.git" ] && [ ! -f "$SUBMODULE/Cargo.toml" ]; then
  echo "missing submodule: $SUBMODULE" >&2
  echo "run: git submodule update --init --recursive third_party/wasmtime" >&2
  exit 1
fi

echo "==> building wasmtime C API from submodule"
cd "$SUBMODULE"
cargo build -p wasmtime-c-api --release

echo
for path in \
  "$SUBMODULE/target/release/libwasmtime.so" \
  "$SUBMODULE/target/release/libwasmtime.dylib" \
  "$SUBMODULE/target/release/wasmtime.dll"
do
  if [ -f "$path" ]; then
    echo "built: $path"
  fi
done

echo
echo "watjit will auto-discover the repo-local build."
echo "override manually with: export WATJIT_WASMTIME_LIB=/absolute/path/to/libwasmtime.so"
