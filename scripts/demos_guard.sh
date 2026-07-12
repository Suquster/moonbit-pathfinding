#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# demos_guard.sh — 全部 examples/ 端到端 demo 输出快照守卫
# ──────────────────────────────────────────────────────────────────────
# 用途：
#   逐个 `moon run examples/<name>`，校验输出中包含各 demo 的关键证据标记
#   （确定性输出片段）。任何 demo 运行失败或标记缺失即非零退出。
#   同时把结果写入 docs/examples/latest-examples-run.md / .json。
#
# 运行：bash scripts/demos_guard.sh
# ──────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.."

outdir="docs/examples"
mkdir -p "$outdir"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
moon_ver="$(moon version 2>/dev/null | head -n1)"

declare -a names cmds statuses counts
fail=0

check() {
  local name="$1"; shift
  local out rc=0 missing=0 total=$#
  out="$(moon run "examples/$name" 2>&1)" || rc=$?
  local status="pass"
  if [ "$rc" -ne 0 ]; then
    status="run-failed"
  else
    for marker in "$@"; do
      if ! grep -qF -- "$marker" <<<"$out"; then
        status="marker-missing"
        missing=$((missing + 1))
        echo "  [MISS] $name: $marker" >&2
      fi
    done
  fi
  names+=("$name"); cmds+=("moon run examples/$name")
  statuses+=("$status"); counts+=("$total")
  if [ "$status" = "pass" ]; then
    echo "PASS $name ($total markers)"
  else
    echo "FAIL $name ($status)" >&2
    fail=1
  fi
}

check maze_solver \
  "Algorithm: BFS (unweighted shortest path, 4-connected grid)" \
  "'*'=path"
check network_routing \
  "Algorithm : Dijkstra (non-negative weighted shortest path)"
check eight_puzzle \
  "Algorithm: A* with sum-of-Manhattan-distances heuristic"
check mini_compiler_pipeline \
  "principal type : TyInt"
check regex_toolkit \
  "client ip    : 203.0.113.9"
check log_pipeline \
  "traceparent"
check actor_worker_pool \
  "supervised worker pool"
check build_pipeline \
  "dependency graph"
check serialization_studio \
  "valid schema: 2 messages"
check dst_explorer \
  "deterministic replication run"
check config_diff_ops \
  "port: 8080"
check hash_integrity \
  "sha256  : 24d031bdf6e77cbfde675f4a4bf932865b307921b6cd1bfafef58b7420c0d464" \
  "tamper detected (tags differ): true" \
  "equal: true"
check compress_workbench \
  "dict round-trip ok: true" \
  "gzip with flipped CRC byte -> rejected" \
  "inflate(deflate)  == input: true"
check time_scheduler \
  "2h30m       : 150 minutes" \
  "DST: true"
check resilience_gateway \
  "multiplicative decrease"
check cli_devtool \
  "did you mean : --service"
check observability_kit \
  "merged count : 1000"
check text_editor_core \
  "piece table == rope: true"
check parser_playground \
  "streamed 3 chunks '<12'+'34'+'5>' -> 12345"
check pbt_fuzz_lab \
  "shrunk counterexample: 500" \
  "same seed reproduces identical graph: true"

overall="pass"; [ "$fail" -ne 0 ] && overall="fail"

{
  echo "# Examples Guard"
  echo
  echo "- Generated at: $ts"
  echo "- Script: scripts/demos_guard.sh"
  echo "- MoonBit: $moon_ver"
  echo "- Status: $overall"
  echo
  echo "| Example | Command | Status | Checked output markers |"
  echo "|---|---|---|---:|"
  for i in "${!names[@]}"; do
    echo "| ${names[$i]} | \`${cmds[$i]}\` | ${statuses[$i]} | ${counts[$i]} |"
  done
  echo
  echo "Raw JSON: latest-examples-run.json."
} > "$outdir/latest-examples-run.md"

{
  echo "{"
  echo "  \"generated_at\": \"$ts\","
  echo "  \"script\": \"scripts/demos_guard.sh\","
  echo "  \"moon\": \"$moon_ver\","
  echo "  \"status\": \"$overall\","
  echo "  \"examples\": ["
  for i in "${!names[@]}"; do
    sep=","; [ "$i" -eq $(( ${#names[@]} - 1 )) ] && sep=""
    echo "    {\"name\": \"${names[$i]}\", \"command\": \"${cmds[$i]}\", \"status\": \"${statuses[$i]}\", \"markers\": ${counts[$i]}}$sep"
  done
  echo "  ]"
  echo "}"
} > "$outdir/latest-examples-run.json"

echo
echo "demos_guard: $overall (${#names[@]} examples)"
exit "$fail"
