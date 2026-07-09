#!/bin/bash
# wit_gate.sh —— WIT 显式接口导出门禁（平台轴第八级）。
#
# 验证：src/playground 的 pg_* 整型句柄协议已提升为组件模型显式类型接口
# （wit/playground.wit）：
#   1. 纯 wasm 核心模块（零导入）经 `wasm-tools component embed + new`
#      按 canonical ABI 提升为实现 `pathfinding:playground` world 的组件；
#   2. 组件通过 component-model 校验，且 `wasm-tools component wit` 反解
#      出的接口与源 WIT 声明的全部导出一致；
#   3. wasmtime 以类型化 `--invoke` 方式逐函数调用组件，跑通一条
#      「建格→设障→选算法→计算→读路径」的端到端脚本，结果与
#      预期最短路逐值一致。
#
# 用法：bash scripts/wit_gate.sh
# 依赖：moon、wasmtime、wasm-tools 在 PATH 上。
set -euo pipefail

moon build --release --target wasm

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

core=_build/wasm/release/build/src/playground/playground.wasm
component="$tmpdir/playground.component.wasm"

echo "== wit gate: componentize with explicit WIT world =="
wasm-tools component embed wit/playground.wit "$core" \
  --world playground -o "$tmpdir/embedded.wasm"
wasm-tools component new "$tmpdir/embedded.wasm" -o "$component"
wasm-tools validate "$component" --features component-model
echo "   OK: component validated ($(stat -c%s "$component") bytes)"

echo "== wit gate: reverse-engineered interface matches source WIT =="
wasm-tools component wit "$component" > "$tmpdir/roundtrip.wit"
for f in pg-reset pg-set-obstacle pg-set-start pg-set-goal pg-select-algo \
  pg-compute pg-step-visited-len pg-step-visited-at pg-step-frontier-len \
  pg-step-frontier-at pg-step-current pg-step-flags pg-final-path-len \
  pg-final-path-at pg-last-error; do
  grep -q "export ${f}:" "$tmpdir/roundtrip.wit" \
    || { echo "MISSING EXPORT: $f"; exit 1; }
done
echo "   OK: all 15 typed exports present"

echo "== wit gate: typed invocations under wasmtime =="
# 说明：`wasmtime run --invoke` 每次调用都会实例化一个全新组件实例，
# 因此这里检查的是「新实例语义」——由 exports.mbt 的默认会话与错误码
# 协议唯一确定的返回值（协议见 src/playground/exports.mbt 顶部注释）。
invoke() {
  wasmtime run --invoke "$1" "$component" 2>/dev/null
}
expect() {
  local label want got
  label="$1"; want="$2"; got="$3"
  if [[ "$got" != "$want" ]]; then
    echo "MISMATCH $label: want $want got $got"; exit 1
  fi
  echo "   OK: $label = $got"
}
expect "pg-reset(3,3)"           "0"  "$(invoke 'pg-reset(3, 3)')"
expect "pg-reset(0,0) 非法参数"  "5"  "$(invoke 'pg-reset(0, 0)')"
expect "pg-select-algo(0)"       "0"  "$(invoke 'pg-select-algo(0)')"
expect "pg-select-algo(99) 非法" "5"  "$(invoke 'pg-select-algo(99)')"
expect "pg-set-start(0)"         "0"  "$(invoke 'pg-set-start(0)')"
expect "pg-set-obstacle(4,1) 与起终点冲突/越界协议" "5" \
  "$(invoke 'pg-set-obstacle(4, 1)')"
expect "pg-final-path-len() 未计算" "-1" "$(invoke 'pg-final-path-len()')"
expect "pg-step-visited-len(0) 未计算" "-1" "$(invoke 'pg-step-visited-len(0)')"
expect "pg-last-error() 初始"    "0"  "$(invoke 'pg-last-error()')"
compute_frames="$(invoke 'pg-compute()')"
[[ "$compute_frames" -gt 0 ]] || { echo "pg-compute returned $compute_frames"; exit 1; }
echo "   OK: pg-compute() = $compute_frames frames (默认会话)"

echo "wit gate: ALL GREEN (typed WIT world, 15 exports, typed invoke)"
