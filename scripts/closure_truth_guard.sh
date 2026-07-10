#!/usr/bin/env bash
# 防止已闭包方向重新引入死参数或把真实契约降格描述为“占位”。
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

proof_files=(
  src/proofs/actor_proof.mbt
  src/proofs/build_tool_proof.mbt
  src/proofs/codegen_infra_proof.mbt
  src/proofs/dst_proof.mbt
  src/proofs/logging_proof.mbt
  src/proofs/lsp_proof.mbt
  src/proofs/parser_combinator_proof.mbt
  src/proofs/regex_engine_proof.mbt
  src/proofs/serialization_proof.mbt
  src/proofs/direction_proofs_test.mbt
)
if rg -n '证明谓词占位|（占位）|升级路径：任务 .*引入真实' "${proof_files[@]}"; then
  echo "已落地证明契约不得继续声明为占位" >&2
  fail=1
fi

if rg -n '桩当前为占位|接口桩' src/dst/dst_test.mbt; then
  echo "DST 真实执行测试不得继续声明为接口桩" >&2
  fail=1
fi

if (( fail != 0 )); then
  exit 1
fi
echo "closure_truth_guard: passed"
