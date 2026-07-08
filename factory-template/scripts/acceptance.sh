#!/usr/bin/env bash
# acceptance.sh —— 一键 acceptance 门禁（工厂模板版）。
# 顺序：格式 → 零警告检查 → 三后端测试 → 接口更新检查。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/4] moon fmt --check"
moon fmt --check

echo "[2/4] moon check --deny-warn"
moon check --deny-warn

echo "[3/4] moon test (native / wasm-gc / js)"
for target in native wasm-gc js; do
  moon test --target "$target"
done

echo "[4/4] moon info (.mbti drift must be committed)"
moon info
if ! git diff --quiet -- '*.mbti'; then
  echo "ERROR: .mbti drift detected; review and commit interface changes." >&2
  git diff --stat -- '*.mbti' >&2
  exit 1
fi

echo "acceptance: ALL GREEN"
