#!/usr/bin/env pwsh
# ──────────────────────────────────────────────────────────────────────
# proof_pipeline.ps1 — 任务 13.3 · 可审计证明报告管线门禁（Proof_Pipeline）
# ──────────────────────────────────────────────────────────────────────
# 用途（对应 design.md §3.3 与 requirements.md Requirement 11）：
#   在既有 proof_evidence.ps1 的基础上扩展为「门禁脚本」：
#     1. 聚合 `src/proofs` 下「全部运行时证明谓词测试」在 wasm-gc / js / native
#        三后端的运行结果（R11.2/R11.3）。
#     2. 生成「逐项语义一致」的 Markdown + JSON 双格式 Proof_Report（R11.1）：
#        - JSON 走 `@proofs.ProofReport` 同一 schema（moonbit-pathfinding.proof.v1），
#          可被 `@proofs.ProofReport::from_json` 解析回结构，保证可审计与可校验。
#        - Markdown 渲染同一条目集合，与 JSON 一一对应。
#     3. 任一谓词测试失败 → 以非零退出状态使门禁失败，并在报告中标记失败的
#        算法与性质（R11.4）。
#     4. 报告「生成或写出」失败 → 以非零退出状态失败并输出诊断信息（R11.5）。
#     5. 官方 `moon prove` 静态验证在本机不可用时，记录该环境限制，但仍输出
#        运行时谓词验证结果且不因此使门禁失败（R11.6）。
#
# 退出码约定：
#   0  —— 全部后端谓词测试通过，报告生成/写出成功（moon prove 可用与否不影响）。
#   1  —— 至少一个谓词失败，或报告生成/写出失败（R11.4 / R11.5）。
#   2  —— 前置条件不满足（如 moon 不在 PATH）。
#
# 兼容性：面向 pwsh（PowerShell 7+）编写，同时兼容 Windows PowerShell 5.1
#   （不使用 null 合并 / 三元等 7+ 专属语法）。
# ──────────────────────────────────────────────────────────────────────

[CmdletBinding()]
param(
    # 谓词测试所在包路径。
    [string]$PackagePath = "src/proofs",
    # 报告产物输出目录。
    [string]$OutDir = "docs/verification",
    # 参与聚合的后端，逗号分隔；取自 wasm-gc / js / native 子集（R11.3）。
    [string]$Backends = "wasm-gc,js,native"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ───────────────────────── 路径解析与前置检查 ─────────────────────────

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = if ([IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $root $OutDir }

$moonCmd = Get-Command moon -ErrorAction SilentlyContinue
if ($null -eq $moonCmd) {
    Write-Host "::error::'moon' 不在 PATH 中，无法运行证明管线。" -ForegroundColor Red
    exit 2
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
# ISO 8601 UTC 生成时间戳（R11.3）。
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$backendList = @()
foreach ($b in ($Backends -split ',')) {
    $t = $b.Trim()
    if ($t.Length -gt 0) { $backendList += $t }
}
if ($backendList.Count -eq 0) {
    Write-Host "::error::未指定任何后端（-Backends 为空）。" -ForegroundColor Red
    exit 2
}

# ───────────────────────── 通用命令捕获 ─────────────────────────

function Invoke-Captured {
    param([string[]]$Command)

    $output = New-Object System.Collections.Generic.List[string]
    & $Command[0] @($Command[1..($Command.Length - 1)]) 2>&1 | ForEach-Object {
        $line = [string]$_
        $output.Add($line)
        Write-Host $line
    }
    [ordered]@{
        command   = $Command
        exit_code = $LASTEXITCODE
        output    = $output.ToArray()
    }
}

# 从 moon test 输出聚合 "Total tests: N, passed: P, failed: F." 统计（可能多行）。
function Get-TestTotals {
    param([string[]]$Lines)
    $total = 0; $passed = 0; $failed = 0; $matched = $false
    foreach ($line in $Lines) {
        if ($line -match 'Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)') {
            $total += [int]$Matches[1]
            $passed += [int]$Matches[2]
            $failed += [int]$Matches[3]
            $matched = $true
        }
    }
    [ordered]@{
        parsed = $matched
        total  = $total
        passed = $passed
        failed = $failed
    }
}

# 从失败的 moon test 输出抽取失败测试的标识行（best-effort，用于失败归因 R11.4）。
function Get-FailingTestLines {
    param([string[]]$Lines)
    $failing = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        # moon 失败行通常形如:  test xxx::"<name>" failed / FAILED 等。
        if ($line -match '(?i)\bfailed\b' -and $line -notmatch 'Total tests:') {
            $failing.Add($line.Trim())
        }
    }
    $failing.ToArray()
}

# ───────────────────── 证明清单（算法 → 性质 → 证据） ─────────────────────
# 覆盖 @proofs 运行时谓词所验证的全部公开寻路与图算法（R11.2）。
# evidence 指向产生该结果的谓词函数 / 测试用例标识；keywords 用于在测试失败时
# 将失败行归因到具体算法/性质（best-effort，R11.4）。

$manifest = @(
    # ── 最短路族（A + B + C 谓词） ──
    [ordered]@{ algorithm = "BFS";                    property = "无权最短路后置条件（合法性/可达/最小性）"; evidence = "src/proofs/bfs_proof.mbt::bfs_post";                          keywords = @("bfs_post", "bfs_proof") },
    [ordered]@{ algorithm = "BFS-All";                property = "多源/全分量 BFS 后置条件";                  evidence = "src/proofs/unweighted_family_proof.mbt::bfs_all_post";       keywords = @("bfs_all_post") },
    [ordered]@{ algorithm = "DFS";                    property = "DFS 路径合法性与可达一致";                  evidence = "src/proofs/unweighted_family_proof.mbt::dfs_post";           keywords = @("dfs_post") },
    [ordered]@{ algorithm = "Bidirectional-BFS";      property = "双向 BFS 与单向 BFS 等价";                  evidence = "src/proofs/unweighted_family_proof.mbt::bidirectional_bfs_post"; keywords = @("bidirectional_bfs_post") },
    [ordered]@{ algorithm = "Dijkstra";               property = "非负权最短路后置条件（合法/代价一致/非负）"; evidence = "src/proofs/dijkstra_proof.mbt::dijkstra_post";              keywords = @("dijkstra_post", "dijkstra_proof") },
    [ordered]@{ algorithm = "A-Star";                 property = "A* 最短路后置条件";                          evidence = "src/proofs/shortest_path_family_proof.mbt::astar_post";     keywords = @("astar_post") },
    [ordered]@{ algorithm = "Bellman-Ford";           property = "含负权最短路后置条件";                       evidence = "src/proofs/shortest_path_family_proof.mbt::bellman_ford_post"; keywords = @("bellman_ford_post") },
    [ordered]@{ algorithm = "DAG-SP";                 property = "DAG 最短路后置条件";                         evidence = "src/proofs/shortest_path_family_proof.mbt::dag_sp_post";    keywords = @("dag_sp_post") },
    [ordered]@{ algorithm = "Bidirectional-Dijkstra"; property = "双向 Dijkstra 与单向等价";                  evidence = "src/proofs/shortest_path_family_proof.mbt::bidirectional_dijkstra_post"; keywords = @("bidirectional_dijkstra_post") },
    [ordered]@{ algorithm = "IDA-Star";               property = "IDA* 最短路后置条件";                        evidence = "src/proofs/shortest_path_family_proof.mbt::ida_star_post";  keywords = @("ida_star_post") },
    [ordered]@{ algorithm = "Yen";                    property = "K 最短路逐条合法且非降序";                   evidence = "src/proofs/shortest_path_family_proof.mbt::yen_post";       keywords = @("yen_post") },
    [ordered]@{ algorithm = "Johnson";                property = "全对最短路（Johnson）后置条件";              evidence = "src/proofs/shortest_path_family_proof.mbt::johnson_post";   keywords = @("johnson_post") },
    [ordered]@{ algorithm = "Floyd-Warshall";         property = "全对最短路矩阵后置条件";                     evidence = "src/proofs/shortest_path_family_proof.mbt::floyd_warshall_post"; keywords = @("floyd_warshall_post", "all_pairs_post") },
    # ── 生成树与连通性族 ──
    [ordered]@{ algorithm = "Kruskal";                property = "最小生成树不变量与最小性";                   evidence = "src/proofs/spanning_connectivity_proof.mbt::mst_post";      keywords = @("mst_post", "mst_weight_le_post") },
    [ordered]@{ algorithm = "Prim";                   property = "最小生成树不变量";                           evidence = "src/proofs/spanning_connectivity_proof.mbt::mst_post";      keywords = @("mst_post") },
    [ordered]@{ algorithm = "Connected-Components";   property = "连通分量等价类划分正确";                     evidence = "src/proofs/spanning_connectivity_proof.mbt::components_partition_post"; keywords = @("components_partition_post") },
    [ordered]@{ algorithm = "Tarjan-SCC";             property = "强连通分量划分正确";                         evidence = "src/proofs/spanning_connectivity_proof.mbt::scc_partition_post"; keywords = @("scc_partition_post") },
    [ordered]@{ algorithm = "Bridges";                property = "报告的每条桥确为桥（删后两端不连通）";        evidence = "src/proofs/spanning_connectivity_proof.mbt::bridges_post";  keywords = @("bridges_post", "edge_is_bridge") },
    [ordered]@{ algorithm = "Condensation";           property = "缩点后必为 DAG";                             evidence = "src/proofs/spanning_connectivity_proof.mbt::condensation_is_dag"; keywords = @("condensation_is_dag") },
    # ── 流 / 匹配 / 拓扑 / 欧拉族 ──
    [ordered]@{ algorithm = "Edmonds-Karp";           property = "最大流合法（守恒/容量约束）";                evidence = "src/proofs/flow_matching_proof.mbt::max_flow_valid";        keywords = @("max_flow_valid") },
    [ordered]@{ algorithm = "Dinic";                  property = "最大流合法（守恒/容量约束）";                evidence = "src/proofs/flow_matching_proof.mbt::max_flow_valid";        keywords = @("max_flow_valid") },
    [ordered]@{ algorithm = "Min-Cut";                property = "最大流 = 最小割";                            evidence = "src/proofs/flow_matching_proof.mbt::max_flow_equals_min_cut"; keywords = @("max_flow_equals_min_cut") },
    [ordered]@{ algorithm = "Min-Cost-Flow";          property = "最小费用流合法且费用一致";                   evidence = "src/proofs/flow_matching_proof.mbt::min_cost_flow_valid";   keywords = @("min_cost_flow_valid") },
    [ordered]@{ algorithm = "Hopcroft-Karp";          property = "匹配合法（无公共端点）";                     evidence = "src/proofs/flow_matching_proof.mbt::matching_valid";        keywords = @("matching_valid") },
    [ordered]@{ algorithm = "Kuhn-Munkres";           property = "完美匹配权重一致";                           evidence = "src/proofs/flow_matching_proof.mbt::perfect_matching_weight"; keywords = @("perfect_matching_weight") },
    [ordered]@{ algorithm = "Eulerian";               property = "欧拉迹合法（逐边消耗、含重边）";              evidence = "src/proofs/flow_matching_proof.mbt::eulerian_trail_valid";  keywords = @("eulerian_trail_valid") },
    [ordered]@{ algorithm = "Topo-Sort";              property = "拓扑序合法（无重复、边方向一致）";            evidence = "src/proofs/flow_matching_proof.mbt::topo_order_post";       keywords = @("topo_order_post") },
    # ── 循环不变式（运行时断言谓词） ──
    [ordered]@{ algorithm = "Dijkstra-Loop";          property = "弹出键单调不减不变式";                       evidence = "src/proofs/loop_invariants.mbt::dijkstra_pop_monotonic";    keywords = @("dijkstra_pop_monotonic") },
    [ordered]@{ algorithm = "BFS-Loop";               property = "层级单调（相邻层差 ≤ 1）不变式";              evidence = "src/proofs/loop_invariants.mbt::bfs_level_invariant";       keywords = @("bfs_level_invariant", "pairwise_diff_within") }
)

# ───────────────────── 1. 跨后端运行谓词测试 ─────────────────────

Write-Host "=== PROOF PIPELINE: 运行时谓词测试（多后端聚合） ===" -ForegroundColor Cyan
$backendRuns = New-Object System.Collections.Generic.List[object]
$allFailingLines = New-Object System.Collections.Generic.List[string]
$predicateGateFailed = $false

foreach ($backend in $backendList) {
    Write-Host "--- backend: $backend ---" -ForegroundColor Cyan
    $run = Invoke-Captured -Command @("moon", "test", $PackagePath, "--target", $backend)
    $totals = Get-TestTotals -Lines $run.output
    $failingLines = Get-FailingTestLines -Lines $run.output
    if ($run.exit_code -ne 0 -or $totals.failed -gt 0) {
        $predicateGateFailed = $true
        foreach ($fl in $failingLines) { $allFailingLines.Add($fl) }
    }
    $backendRuns.Add([ordered]@{
            backend    = $backend
            exit_code  = $run.exit_code
            totals     = $totals
            failing    = $failingLines
            status     = if ($run.exit_code -eq 0 -and $totals.failed -eq 0) { "passed" } else { "failed" }
            command    = $run.command
            output     = $run.output
        })
}

# ───────────────────── 2. moon prove 可用性（R11.6） ─────────────────────

Write-Host "=== PROOF PIPELINE: moon prove 静态验证可用性探测 ===" -ForegroundColor Cyan
$proveHelp = Invoke-Captured -Command @("moon", "prove", "--help")
$why3 = Get-Command why3 -ErrorAction SilentlyContinue
$why3Available = $null -ne $why3
$why3Version = ""
if ($why3Available) {
    $why3Version = ((& why3 --version 2>&1 | ForEach-Object { [string]$_ }) -join " ")
}

$prove = $null
$proveStatus = "not-run"
$proveEnvLimited = $false
if ($proveHelp.exit_code -ne 0) {
    $proveStatus = "moon-prove-unavailable"
    $proveEnvLimited = $true
} elseif (-not $why3Available) {
    Write-Host "Why3 不在 PATH；记录环境限制并仍输出运行时谓词结果（R11.6）。" -ForegroundColor Yellow
    $prove = Invoke-Captured -Command @("moon", "prove", $PackagePath)
    $proveStatus = "blocked-missing-why3"
    $proveEnvLimited = $true
} else {
    $prove = Invoke-Captured -Command @("moon", "prove", $PackagePath)
    $proveStatus = if ($prove.exit_code -eq 0) { "passed" } else { "failed" }
}

# ───────────────────── 3. 构建证明条目（失败归因） ─────────────────────

function Test-EntryFailed {
    param([string[]]$Keywords, [string[]]$FailingLines)
    foreach ($line in $FailingLines) {
        foreach ($kw in $Keywords) {
            if ($line -match [regex]::Escape($kw)) { return $true }
        }
    }
    return $false
}

$entries = New-Object System.Collections.Generic.List[object]
$backendLabel = ($backendList -join "/")

foreach ($item in $manifest) {
    $entryFailed = $false
    if ($predicateGateFailed) {
        $entryFailed = Test-EntryFailed -Keywords $item.keywords -FailingLines $allFailingLines.ToArray()
    }
    $passed = -not $entryFailed
    $evidenceText = if ($passed) {
        "$($item.evidence) · moon test $PackagePath ($backendLabel) 通过"
    } else {
        "$($item.evidence) · moon test $PackagePath ($backendLabel) 失败"
    }
    $entries.Add([ordered]@{
            algorithm = $item.algorithm
            property  = $item.property
            passed    = $passed
            evidence  = $evidenceText
        })
}

# 若存在无法归因到任何清单条目的失败行（如新增/重命名测试），保守追加一条失败
# 条目以保证非零退出且不静默吞掉失败（R11.4）。
$unattributed = New-Object System.Collections.Generic.List[string]
if ($predicateGateFailed) {
    foreach ($line in $allFailingLines) {
        $matchedAny = $false
        foreach ($item in $manifest) {
            foreach ($kw in $item.keywords) {
                if ($line -match [regex]::Escape($kw)) { $matchedAny = $true; break }
            }
            if ($matchedAny) { break }
        }
        if (-not $matchedAny) { $unattributed.Add($line) }
    }
    if ($unattributed.Count -gt 0) {
        $entries.Add([ordered]@{
                algorithm = "(unattributed)"
                property  = "存在未能归因到具体算法的谓词测试失败"
                passed    = $false
                evidence  = ($unattributed.ToArray() -join " ; ")
            })
    }
}

$moonVersion = ((& moon version 2>&1 | ForEach-Object { [string]$_ }) -join " ")

# any_failed 聚合（R11.4）：等价于 @proofs.ProofReport::any_failed。
$anyFailed = $false
foreach ($e in $entries) { if (-not $e.passed) { $anyFailed = $true } }

# ───────────────────── 4. 组装 Proof_Report（@proofs 同 schema） ─────────────────────
# 该对象与 @proofs.ProofReport::to_json 的 schema 一致，可被 from_json 解析回结构。

$proofReport = [ordered]@{
    schema       = "moonbit-pathfinding.proof.v1"
    backends     = $backendList
    moon_version = $moonVersion
    generated_at = $generatedAt
    entries      = $entries.ToArray()
}

# 环境限制说明（R11.6）。
$envLimitations = New-Object System.Collections.Generic.List[string]
if ($proveEnvLimited) {
    if ($proveStatus -eq "moon-prove-unavailable") {
        $envLimitations.Add("官方 moon prove 在本机不可用（moon prove --help 非零退出）；仅输出运行时谓词结果。")
    } elseif ($proveStatus -eq "blocked-missing-why3") {
        $envLimitations.Add("moon prove 存在但 Why3 不在 PATH，静态证明无法在本机执行；仅输出运行时谓词结果。")
    }
}

$interpretation = if ($anyFailed) {
    "至少一条运行时证明谓词失败：证明门禁失败（非零退出）。详见失败条目与各后端原始输出。"
} elseif ($proveEnvLimited) {
    "全部运行时证明谓词在所选后端通过；官方 moon prove 静态验证受本机环境限制无法执行（已记录环境限制，不影响门禁）。"
} else {
    "全部运行时证明谓词在所选后端通过，且官方 moon prove 在本机可用。"
}

$pipelineArtifact = [ordered]@{
    schema             = "moonbit-pathfinding.proof-pipeline.v1"
    generated_at       = $generatedAt
    generated_by       = "scripts/proof_pipeline.ps1"
    moon_version       = $moonVersion
    package_path       = $PackagePath
    backends           = $backendList
    proof_report       = $proofReport
    any_failed         = $anyFailed
    backend_runs       = $backendRuns.ToArray()
    moon_prove_help    = $proveHelp
    moon_prove_status  = $proveStatus
    moon_prove         = $prove
    why3_available     = $why3Available
    why3_version       = $why3Version
    env_limitations    = $envLimitations.ToArray()
    interpretation     = $interpretation
}

# ───────────────────── 5. 写出 MD + JSON（写失败即门禁失败 R11.5） ─────────────────────

# 渲染与 JSON 逐项一致的 Markdown（R11.1）。
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Proof Report")
$md.Add("")
$md.Add("- Generated at: $generatedAt")
$md.Add("- Script: scripts/proof_pipeline.ps1")
$md.Add("- Package: $PackagePath")
$md.Add("- MoonBit: $moonVersion")
$md.Add("- Backends: $backendLabel")
$md.Add("- moon prove status: $proveStatus")
$md.Add("- Why3 available: $why3Available")
$md.Add("- any_failed: $($anyFailed.ToString().ToLower())")
$md.Add("")
$md.Add("## 各后端谓词测试汇总")
$md.Add("")
$md.Add("| 后端 | 退出码 | 总数 | 通过 | 失败 | 状态 |")
$md.Add("| --- | ---: | ---: | ---: | ---: | --- |")
foreach ($brun in $backendRuns) {
    $md.Add("| $($brun.backend) | $($brun.exit_code) | $($brun.totals.total) | $($brun.totals.passed) | $($brun.totals.failed) | $($brun.status) |")
}
$md.Add("")
$md.Add("## 证明条目（算法 / 性质 / 结果 / 证据）")
$md.Add("")
$md.Add("| 算法 | 性质 | 结果 | 证据 |")
$md.Add("| --- | --- | --- | --- |")
foreach ($e in $entries) {
    $res = if ($e.passed) { "通过" } else { "失败" }
    $md.Add("| $($e.algorithm) | $($e.property) | $res | $($e.evidence) |")
}
if ($envLimitations.Count -gt 0) {
    $md.Add("")
    $md.Add("## 环境限制（R11.6）")
    $md.Add("")
    foreach ($lim in $envLimitations) { $md.Add("- $lim") }
}
$md.Add("")
$md.Add("## Interpretation")
$md.Add("")
$md.Add($interpretation)
$md.Add("")

# 写出（任一写出失败 → 非零退出 R11.5）。
try {
    New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

    $pipelineJson = $pipelineArtifact | ConvertTo-Json -Depth 24
    $reportJson = $proofReport | ConvertTo-Json -Depth 24

    $pipelineJsonPath = Join-Path $outRoot ("proof-pipeline-$timestamp.json")
    $latestPipelinePath = Join-Path $outRoot "latest-proof-pipeline.json"
    $latestReportJsonPath = Join-Path $outRoot "latest-proof-report.json"
    $mdPath = Join-Path $outRoot "latest-proof-report.md"

    [IO.File]::WriteAllText($pipelineJsonPath, $pipelineJson + "`n", [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($latestPipelinePath, $pipelineJson + "`n", [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($latestReportJsonPath, $reportJson + "`n", [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", [Text.Encoding]::UTF8)

    Write-Host "=== PROOF PIPELINE ARTIFACTS ===" -ForegroundColor Cyan
    Write-Host $pipelineJsonPath
    Write-Host $latestPipelinePath
    Write-Host $latestReportJsonPath
    Write-Host $mdPath
} catch {
    Write-Host "::error::Proof_Report 生成或写出失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ───────────────────── 6. 门禁退出语义 ─────────────────────

if ($anyFailed) {
    Write-Host "::error::证明门禁失败：存在未通过的证明谓词。" -ForegroundColor Red
    foreach ($e in $entries) {
        if (-not $e.passed) {
            Write-Host ("  - FAILED: {0} / {1}" -f $e.algorithm, $e.property) -ForegroundColor Red
        }
    }
    exit 1
}

if ($proveStatus -eq "failed") {
    Write-Host "::error::moon prove 静态验证失败。" -ForegroundColor Red
    exit 1
}

if ($proveEnvLimited) {
    Write-Host "::notice::证明门禁通过（运行时谓词全部通过）；moon prove 受环境限制已记录。" -ForegroundColor Green
} else {
    Write-Host "::notice::证明门禁通过：运行时谓词与 moon prove 均通过。" -ForegroundColor Green
}
exit 0
