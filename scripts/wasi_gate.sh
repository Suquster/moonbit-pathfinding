#!/bin/bash
# wasi_gate.sh —— WASI 交付门禁（平台轴第六级）。
#
# 验证：`moon build --release --target wasm` 产出的独立 wasm 工件可在
# 标准 WASI 运行时（wasmtime）下直接执行，且逐字节输出与 js 后端
# `moon run --target js` 完全一致（四后端一致性延伸到交付物层面）。
#
# 用法：bash scripts/wasi_gate.sh   （需要 moon 与 wasmtime 在 PATH 上）
set -euo pipefail

artifacts=(
  "src/backend_cli:_build/wasm/release/build/src/backend_cli/backend_cli.wasm"
  "examples/maze_solver:_build/wasm/release/build/examples/maze_solver/maze_solver.wasm"
  "examples/eight_puzzle:_build/wasm/release/build/examples/eight_puzzle/eight_puzzle.wasm"
  "examples/network_routing:_build/wasm/release/build/examples/network_routing/network_routing.wasm"
)

moon build --release --target wasm

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

for entry in "${artifacts[@]}"; do
  pkg="${entry%%:*}"
  wasm="${entry##*:}"
  name="$(basename "$wasm" .wasm)"
  echo "== WASI gate: ${pkg} =="
  wasmtime "$wasm" > "$tmpdir/${name}.wasi.txt"
  moon run "$pkg" --target js --release > "$tmpdir/${name}.js.txt"
  diff "$tmpdir/${name}.wasi.txt" "$tmpdir/${name}.js.txt"
  echo "   OK: wasmtime output identical to js backend"
done

echo "WASI gate: ALL GREEN (${#artifacts[@]} artifacts)"
