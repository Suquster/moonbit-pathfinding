#!/bin/bash
# component_gate.sh —— wasm 组件模型交付门禁（平台轴第七级）。
#
# 验证：`moon build --release --target wasm` 产出的核心模块可经
# wasi_snapshot_preview1 命令适配器组件化（wasm-tools component new），
# 产物为合法的组件模型（component model）二进制，并可在 wasmtime 下
# 直接执行，逐字节输出与 js 后端 `moon run --target js` 完全一致
# ——把「四后端 + WASI 一致性」进一步延伸到组件模型交付物层面。
#
# 用法：bash scripts/component_gate.sh
# 依赖：moon、wasmtime、wasm-tools 在 PATH 上；适配器 wasm 通过环境变量
#       WASI_ADAPTER 指定，缺省自动从 wasmtime 发布页下载到临时目录。
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

adapter="${WASI_ADAPTER:-}"
if [[ -z "$adapter" ]]; then
  adapter="$tmpdir/wasi_snapshot_preview1.command.wasm"
  wasmtime_version="$(wasmtime --version | awk '{print $2}')"
  curl -sL -o "$adapter" \
    "https://github.com/bytecodealliance/wasmtime/releases/download/v${wasmtime_version}/wasi_snapshot_preview1.command.wasm"
fi

for entry in "${artifacts[@]}"; do
  pkg="${entry%%:*}"
  wasm="${entry##*:}"
  name="$(basename "$wasm" .wasm)"
  echo "== component gate: ${pkg} =="
  component="$tmpdir/${name}.component.wasm"
  wasm-tools component new "$wasm" \
    --adapt "wasi_snapshot_preview1=$adapter" -o "$component"
  wasm-tools validate "$component" --features component-model
  echo "   OK: componentized + validated ($(stat -c%s "$component") bytes)"
  wasmtime run "$component" > "$tmpdir/${name}.component.txt"
  moon run "$pkg" --target js --release > "$tmpdir/${name}.js.txt"
  diff "$tmpdir/${name}.component.txt" "$tmpdir/${name}.js.txt"
  echo "   OK: component output identical to js backend"
done

echo "component gate: ALL GREEN (${#artifacts[@]} artifacts)"
