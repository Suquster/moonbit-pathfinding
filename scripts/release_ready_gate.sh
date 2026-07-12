#!/usr/bin/env bash
# 在 CI 的四后端测试、证明谓词与可执行文档步骤全绿后，将真实通过状态
# 输入 release_aggregate，并核对每个方向的静态发布证据完整性。
set -euo pipefail
cd "$(dirname "$0")/.."

directions=(
  "parser_combinator|parser-combinator|parser_combinator"
  "regex_engine|regex-engine|regex_engine"
  "serialization|serialization|serialization"
  "build_tool|build-tool|build_tool"
  "logging|logging|logging"
  "codegen_infra|codegen-infra|codegen_infra"
  "dst|dst|dst"
  "lsp_server|lsp|lsp"
  "mini_compiler|mini-compiler|mini_compiler"
  "actor|actor|actor"
)

for entry in "${directions[@]}"; do
  IFS='|' read -r package spec proof <<< "$entry"
  for evidence in \
    "src/$package/CHANGELOG.md" \
    "src/$package/README.mbt.md" \
    "src/proofs/${proof}_proof.mbt" \
    ".kiro/specs/$spec/tasks.md"; do
    if [[ ! -f "$evidence" ]]; then
      echo "release-ready evidence missing: $evidence" >&2
      exit 1
    fi
  done
  if grep -nE '^- \[ \]' ".kiro/specs/$spec/tasks.md"; then
    echo "release-ready blocked by open tasks: $spec" >&2
    exit 1
  fi
done

moon run cmd/release_gate --target wasm-gc
