#!/usr/bin/env bash
# 大赛验收门禁（deny-warn 语义，跨 moon 工具链版本兼容）
#
# 验收要求包含 `moon fmt --deny-warn` 与 `moon info --deny-warn` 两个过程。
# 新版工具链（>= 0.1.2026xx）已从 `moon fmt` / `moon info` 移除 `--deny-warn`
# 参数（该 flag 保留在 `moon check` / `moon test` 上）。本脚本先探测当前
# 工具链是否支持该参数：支持则原样执行；不支持则以等价语义执行——
#   * fmt:  `moon fmt --check`（存在未格式化文件即非零退出）
#   * info: `moon info` 后校验 `*.mbti` 接口快照无漂移（git diff --exit-code）
# 无论哪条路径，任何告警/漂移都会使脚本非零退出（deny-warn 语义）。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 关卡 1: moon fmt（deny-warn 语义）=="
if moon fmt --help 2>/dev/null | grep -q -- '--deny-warn'; then
  moon fmt --deny-warn
else
  moon fmt --check
fi

echo "== 关卡 2: moon info（deny-warn 语义 + 接口无漂移）=="
if moon info --help 2>/dev/null | grep -q -- '--deny-warn'; then
  moon info --deny-warn
else
  moon info
  git diff --exit-code -- ':(glob)**/*.mbti'
fi

echo "== 关卡 3: moon check --deny-warn（全部告警视为错误）=="
moon check --deny-warn

echo "全部验收门禁通过（deny-warn 语义）"
