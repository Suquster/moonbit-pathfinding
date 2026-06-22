#!/usr/bin/env pwsh
# ──────────────────────────────────────────────────────────────────────
# regression_guard.ps1 — 任务 21.2 · 基准回归门禁（Regression_Guard, R5.5）
# ──────────────────────────────────────────────────────────────────────
# 用途（对应 design.md §「方向 2 · 2.3 Regression_Guard 设计」与
#       requirements.md Requirement 5.5）：
#   读入「已签入基线 JSON」与「当前基准 JSON」，按算法名配对两侧用例的**中位
#   计时**，复用 `@infra_bench.regression_check` 的判定口径给出每个算法的
#   `RegressionVerdict`：当前中位相对基线中位回归超过容差 `tol_pct`（默认 10.0%）
#   即标记 `failed=true`。任一 `failed=true` → 以非零状态退出，使基准门禁失败，
#   并在 MD + JSON 报告中记录「算法名 / 基线中位 / 当前中位 / 回归百分比」。
#
# 判定口径（与 src/infra_bench/regression.mbt::regression_check 逐字一致；本脚本
# 在受 “只新增脚本、不改动 src 包” 约束下，于 PowerShell 侧忠实复刻该纯函数语义，
# regression.mbt 为唯一事实源）：
#   * 配对：仅对「基线与当前都存在」的算法名产出 verdict；遍历以基线用例顺序为准，
#     两侧同名重复用例各取**首次**出现者（确定性）。
#   * 回归百分比：regression_pct = (current_median - baseline_median)
#       / baseline_median * 100；当 baseline_median == 0 时约定 regression_pct = 0.0
#     （避免除零；此时失败判定退化为 current_median > 0）。
#   * 失败判定：**当且仅当** current_median > baseline_median * (1 + tol_pct/100)
#     时 failed=true（严格大于；恰好等于容差上界不算回归）。
#   * 加速比：speedup = baseline_median / current_median（current_median > 0 时），
#     current_median == 0 记为 null（与 RegressionVerdict::speedup 一致）。
#
# 支持的输入 JSON schema（基线 / 当前可任意混用，自动识别）：
#   1. moonbit-pathfinding.benchmark.v1        —— 规范 BenchReport：cases[].algorithm
#      + cases[].stats.median（@infra_bench.BenchReport::to_json 产物）。
#   2. moonbit-pathfinding.benchmark-native.v1 —— scripts/benchmark_native.ps1 的
#      latest-native.json：benchmarks[].algorithm + benchmarks[].summary.median_us。
#   3. 顶层带 report 包装（如 latest-advanced.json）—— 自动下钻 .report 后再识别。
#
# 退出码约定：
#   0  —— 全部配对算法未回归（无 failed），且报告写出成功。
#   1  —— 至少一个算法回归（failed=true · R5.5），或报告写出失败。
#   2  —— 前置条件不满足（缺文件 / JSON 不可解析 / 无法识别 schema / 无可配对算法）。
#
# 兼容性：面向 pwsh（PowerShell 7+），同时兼容 Windows PowerShell 5.1
#   （不使用 null 合并 / 三元等 7+ 专属语法）。
# ──────────────────────────────────────────────────────────────────────

[CmdletBinding()]
param(
    # 已签入基线基准 JSON 路径。
    [string]$BaselinePath = "benches/results/baseline-native.json",
    # 当前基准 JSON 路径（默认取 benchmark_native.ps1 产出的 latest-native.json）。
    [string]$CurrentPath = "benches/results/latest-native.json",
    # 回归容差（百分比）。<0 时回退到 REGRESSION_TOL_PCT 环境变量，仍未提供则取
    # R5.5 规定的默认 10.0。
    [double]$TolPct = -1,
    # 报告产物输出目录。
    [string]$OutDir = "docs/verification",
    # 控制台最多打印多少条回归条目（完整清单始终写入产物）。
    [int]$MaxListed = 100
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 文本产物统一使用「无 BOM」的 UTF-8，确保 JSON 可被严格解析器直接读取。
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# 百分比格式化：固定保留 2 位小数且使用不变文化（点号小数），便于审计阅读。
function Format-Pct {
    param([double]$Value)
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F2}", $Value)
}

# 通用浮点格式化（保留至多 3 位有效小数，去除末尾冗余 0）。
function Format-Num {
    param([double]$Value)
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:0.###}", $Value)
}

# ───────────────────────── 容差解析（兼容 5.1，不用 null 合并） ─────────────────────────

$DefaultTolPct = 10.0
if ($TolPct -lt 0) {
    if ($env:REGRESSION_TOL_PCT) {
        $TolPct = [double]$env:REGRESSION_TOL_PCT
    } else {
        $TolPct = $DefaultTolPct
    }
}

Write-Host "=== Regression Guard (task 21.2 · R5.5) ===" -ForegroundColor Cyan
Write-Host ("Tolerance : 中位回归 > {0}% 即失败（严格大于）" -f (Format-Pct $TolPct))

# ───────────────────────── 路径解析与前置检查 ─────────────────────────

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = if ([IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $root $OutDir }
$baselineFull = if ([IO.Path]::IsPathRooted($BaselinePath)) { $BaselinePath } else { Join-Path $root $BaselinePath }
$currentFull = if ([IO.Path]::IsPathRooted($CurrentPath)) { $CurrentPath } else { Join-Path $root $CurrentPath }

Write-Host ("Baseline  : {0}" -f $baselineFull)
Write-Host ("Current   : {0}" -f $currentFull)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# ───────────────────── JSON 读取与 schema 识别 ─────────────────────

# 读取并解析 JSON 文件；失败抛出说明性异常（由调用方按前置失败 exit 2 处理）。
function Read-JsonFile {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label JSON 文件不存在：$Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "$Label JSON 文件为空：$Path"
    }
    try {
        return $raw | ConvertFrom-Json
    } catch {
        throw "$Label JSON 解析失败（$Path）：$($_.Exception.Message)"
    }
}

# 将单个节点转换为 [{algorithm, median}] 条目数组；无法识别返回 $null。
#   * benchmark.v1 / 规范 BenchReport：cases[].algorithm + cases[].stats.median
#   * benchmark-native.v1：benchmarks[].algorithm + benchmarks[].summary.median_us
function Convert-NodeToEntries {
    param([object]$Node)
    if ($null -eq $Node) { return $null }
    $names = @($Node.PSObject.Properties.Name)

    if (($names -contains 'cases') -and ($null -ne $Node.cases)) {
        $out = New-Object System.Collections.Generic.List[object]
        foreach ($c in @($Node.cases)) {
            if ($null -eq $c.stats) { continue }
            $out.Add([pscustomobject]@{
                    algorithm = [string]$c.algorithm
                    median    = [double]$c.stats.median
                })
        }
        if ($out.Count -gt 0) { return $out.ToArray() }
    }

    if (($names -contains 'benchmarks') -and ($null -ne $Node.benchmarks)) {
        $out = New-Object System.Collections.Generic.List[object]
        foreach ($b in @($Node.benchmarks)) {
            if ($null -eq $b.summary) { continue }
            $out.Add([pscustomobject]@{
                    algorithm = [string]$b.algorithm
                    median    = [double]$b.summary.median_us
                })
        }
        if ($out.Count -gt 0) { return $out.ToArray() }
    }

    return $null
}

# 从报告对象抽取中位条目；顶层无法识别时下钻 .report（advanced 包装）后重试。
function Get-MedianEntries {
    param([object]$Report, [string]$Label)
    $entries = Convert-NodeToEntries -Node $Report
    if ($null -ne $entries) { return $entries }
    $names = @($Report.PSObject.Properties.Name)
    if (($names -contains 'report') -and ($null -ne $Report.report)) {
        $entries = Convert-NodeToEntries -Node $Report.report
        if ($null -ne $entries) { return $entries }
    }
    throw "$Label JSON 无法识别 schema：未找到可用的 cases[].stats.median 或 benchmarks[].summary.median_us 字段。"
}

# 取报告的 schema 标识（用于审计），缺失返回 "(unknown)"。
function Get-SchemaLabel {
    param([object]$Report)
    if (($Report.PSObject.Properties.Name -contains 'schema') -and $Report.schema) {
        return [string]$Report.schema
    }
    if (($Report.PSObject.Properties.Name -contains 'report') -and $Report.report -and
        ($Report.report.PSObject.Properties.Name -contains 'schema') -and $Report.report.schema) {
        return [string]$Report.report.schema
    }
    return "(unknown)"
}

# ───────────────────── 前置失败收尾：写出诊断产物并 exit 2 ─────────────────────

function Write-RegressionArtifacts {
    param(
        [object]$Artifact,
        [string[]]$MarkdownLines
    )
    try {
        New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
        $json = $Artifact | ConvertTo-Json -Depth 12
        $jsonPath = Join-Path $outRoot ("regression-guard-$timestamp.json")
        $latestJson = Join-Path $outRoot "latest-regression-guard.json"
        $mdPath = Join-Path $outRoot "latest-regression-guard.md"
        [IO.File]::WriteAllText($jsonPath, $json + "`n", $Utf8NoBom)
        [IO.File]::WriteAllText($latestJson, $json + "`n", $Utf8NoBom)
        [IO.File]::WriteAllText($mdPath, ($MarkdownLines -join "`n") + "`n", $Utf8NoBom)
        Write-Host "=== REGRESSION GUARD ARTIFACTS ===" -ForegroundColor Cyan
        Write-Host $jsonPath
        Write-Host $latestJson
        Write-Host $mdPath
        return $true
    } catch {
        Write-Host "::error::回归门禁报告写出失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Exit-Precondition {
    param([string]$Reason)
    Write-Host "::error::回归门禁前置条件不满足：$Reason" -ForegroundColor Red
    $artifact = [ordered]@{
        schema       = "moonbit-pathfinding.regression-guard.v1"
        generated_at = $generatedAt
        generated_by = "scripts/regression_guard.ps1"
        baseline     = $baselineFull
        current      = $currentFull
        tol_pct      = $TolPct
        status       = "error"
        reason       = $Reason
    }
    $md = @(
        "# Regression Guard Report",
        "",
        "- Generated at: $generatedAt",
        "- Script: scripts/regression_guard.ps1",
        "- Tolerance: $(Format-Pct $TolPct)%",
        "- Status: ERROR（前置条件不满足）",
        "- Reason: $Reason",
        ""
    )
    [void](Write-RegressionArtifacts -Artifact $artifact -MarkdownLines $md)
    exit 2
}

# ───────────────────── 1. 读取并抽取两侧中位条目 ─────────────────────

$baselineReport = $null
$currentReport = $null
try {
    $baselineReport = Read-JsonFile -Path $baselineFull -Label "基线"
    $currentReport = Read-JsonFile -Path $currentFull -Label "当前"
} catch {
    Exit-Precondition -Reason $_.Exception.Message
}

$baselineSchema = Get-SchemaLabel -Report $baselineReport
$currentSchema = Get-SchemaLabel -Report $currentReport

$baselineEntries = $null
$currentEntries = $null
try {
    $baselineEntries = Get-MedianEntries -Report $baselineReport -Label "基线"
    $currentEntries = Get-MedianEntries -Report $currentReport -Label "当前"
} catch {
    Exit-Precondition -Reason $_.Exception.Message
}

Write-Host ""
Write-Host ("Baseline schema : {0}（{1} 个算法用例）" -f $baselineSchema, $baselineEntries.Count)
Write-Host ("Current  schema : {0}（{1} 个算法用例）" -f $currentSchema, $currentEntries.Count)

# ───────────────────── 2. 复刻 regression_check 配对与判定 ─────────────────────
# 与 src/infra_bench/regression.mbt::regression_check 同口径（见文件头注释）。

$TolBase = 100.0

# 当前侧：算法名 → 首次出现的中位（确定性，与 find_median_by_algorithm 一致）。
$currentFirst = @{}
foreach ($ce in $currentEntries) {
    if (-not $currentFirst.ContainsKey($ce.algorithm)) {
        $currentFirst[$ce.algorithm] = [double]$ce.median
    }
}

# 基线侧：算法名 → 首次出现的中位（用于报告未配对项的诊断信息）。
$baselineFirst = @{}
foreach ($be in $baselineEntries) {
    if (-not $baselineFirst.ContainsKey($be.algorithm)) {
        $baselineFirst[$be.algorithm] = [double]$be.median
    }
}

$verdicts = New-Object System.Collections.Generic.List[object]
$seen = New-Object System.Collections.Generic.HashSet[string]
$unpairedBaseline = New-Object System.Collections.Generic.List[string]

foreach ($be in $baselineEntries) {
    $alg = $be.algorithm
    if ($seen.Contains($alg)) { continue }            # 取基线首次出现者
    if (-not $currentFirst.ContainsKey($alg)) {
        if (-not ($unpairedBaseline -contains $alg)) { $unpairedBaseline.Add($alg) }
        continue                                       # 仅当前缺失：跳过（不产出 verdict）
    }
    [void]$seen.Add($alg)

    $bm = [double]$be.median
    $cm = [double]$currentFirst[$alg]

    if ($bm -eq 0.0) {
        # baseline_median == 0：回归百分比无定义，约定 0.0；失败判定退化为 current > 0。
        $pct = 0.0
    } else {
        $pct = ($cm - $bm) / $bm * $TolBase
    }
    $threshold = $bm * (1.0 + $TolPct / $TolBase)
    $failed = $cm -gt $threshold

    $speedup = $null
    if ($cm -ne 0.0) { $speedup = $bm / $cm }

    $verdicts.Add([pscustomobject]@{
            algorithm       = $alg
            baseline_median = $bm
            current_median  = $cm
            regression_pct  = [math]::Round($pct, 4)
            speedup         = if ($null -eq $speedup) { $null } else { [math]::Round($speedup, 4) }
            failed          = $failed
        })
}

# 当前侧存在、基线侧缺失的算法（信息性，不参与判定）。
$unpairedCurrent = New-Object System.Collections.Generic.List[string]
foreach ($alg in $currentFirst.Keys) {
    if (-not $baselineFirst.ContainsKey($alg)) { $unpairedCurrent.Add($alg) }
}

# 无任何可配对算法 → 输入很可能不对应，作为前置失败避免「静默通过」。
if ($verdicts.Count -eq 0) {
    Exit-Precondition -Reason ("基线与当前 JSON 没有任何同名算法用例可配对（baseline 算法: [{0}]；current 算法: [{1}]）。" -f (($baselineFirst.Keys) -join ', '), (($currentFirst.Keys) -join ', '))
}

# ───────────────────── 3. 聚合失败并组装产物 ─────────────────────

$failedVerdicts = @($verdicts | Where-Object { $_.failed })
$anyFailed = $failedVerdicts.Count -gt 0
$status = if ($anyFailed) { "failed" } else { "passed" }

$artifact = [ordered]@{
    schema            = "moonbit-pathfinding.regression-guard.v1"
    generated_at      = $generatedAt
    generated_by      = "scripts/regression_guard.ps1"
    baseline          = $baselineFull
    current           = $currentFull
    baseline_schema   = $baselineSchema
    current_schema    = $currentSchema
    tol_pct           = $TolPct
    status            = $status
    compared_count    = $verdicts.Count
    failed_count      = $failedVerdicts.Count
    verdicts          = $verdicts.ToArray()
    unpaired_baseline = $unpairedBaseline.ToArray()
    unpaired_current  = $unpairedCurrent.ToArray()
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Regression Guard Report")
$md.Add("")
$md.Add("- Generated at: $generatedAt")
$md.Add("- Script: scripts/regression_guard.ps1")
$md.Add("- Baseline: ``$baselineFull`` （schema: ``$baselineSchema``）")
$md.Add("- Current: ``$currentFull`` （schema: ``$currentSchema``）")
$md.Add("- Tolerance: $(Format-Pct $TolPct)% （中位回归严格大于即失败）")
$md.Add("- Status: $($status.ToUpper())")
$md.Add("- Compared algorithms: $($verdicts.Count)")
$md.Add("- Regressed algorithms: $($failedVerdicts.Count)")
$md.Add("")
$md.Add("## 逐算法回归判定（算法 / 基线中位 / 当前中位 / 回归百分比）")
$md.Add("")
$md.Add("| 算法 | 基线中位 | 当前中位 | 回归百分比 | 中位加速比 | 判定 |")
$md.Add("| --- | ---: | ---: | ---: | ---: | :--: |")
foreach ($v in $verdicts) {
    $verdictLabel = if ($v.failed) { "回归 ❌" } else { "通过 ✅" }
    $speedupText = if ($null -eq $v.speedup) { "n/a" } else { Format-Num $v.speedup }
    $md.Add(("| {0} | {1} | {2} | {3}% | {4}x | {5} |" -f `
                $v.algorithm, (Format-Num $v.baseline_median), (Format-Num $v.current_median), `
            (Format-Pct $v.regression_pct), $speedupText, $verdictLabel))
}
$md.Add("")
if ($unpairedBaseline.Count -gt 0) {
    $md.Add("## 仅基线存在（当前缺失，未参与判定）")
    $md.Add("")
    foreach ($a in $unpairedBaseline) { $md.Add("- $a") }
    $md.Add("")
}
if ($unpairedCurrent.Count -gt 0) {
    $md.Add("## 仅当前存在（基线缺失，未参与判定）")
    $md.Add("")
    foreach ($a in $unpairedCurrent) { $md.Add("- $a") }
    $md.Add("")
}
if ($anyFailed) {
    $md.Add("## 回归详情（R5.5 · 门禁失败）")
    $md.Add("")
    foreach ($v in $failedVerdicts) {
        $md.Add(("- **{0}**：基线中位 {1} → 当前中位 {2}，回归 {3}%（容差 {4}%）" -f `
                    $v.algorithm, (Format-Num $v.baseline_median), (Format-Num $v.current_median), `
                (Format-Pct $v.regression_pct), (Format-Pct $TolPct)))
    }
    $md.Add("")
}

$wrote = Write-RegressionArtifacts -Artifact $artifact -MarkdownLines $md.ToArray()
if (-not $wrote) {
    # 报告写出失败按门禁失败处理（非零退出）。
    exit 1
}

# ───────────────────── 4. 控制台摘要与门禁退出语义 ─────────────────────

Write-Host ""
Write-Host "--- 逐算法回归判定 ---" -ForegroundColor Cyan
$shown = [Math]::Min($MaxListed, $verdicts.Count)
for ($i = 0; $i -lt $shown; $i++) {
    $v = $verdicts[$i]
    $line = ("  {0}: baseline_median={1}, current_median={2}, regression={3}%" -f `
            $v.algorithm, (Format-Num $v.baseline_median), (Format-Num $v.current_median), (Format-Pct $v.regression_pct))
    if ($v.failed) {
        Write-Host ($line + "  [回归]") -ForegroundColor Red
    } else {
        Write-Host $line -ForegroundColor Green
    }
}
if ($verdicts.Count -gt $shown) {
    Write-Host ("  … 其余 {0} 条见报告产物 latest-regression-guard.md" -f ($verdicts.Count - $shown)) -ForegroundColor Yellow
}

if ($anyFailed) {
    Write-Host ("::error::Regression gate FAILED: {0}/{1} 个算法中位计时回归超过 {2}% 容差。" -f `
            $failedVerdicts.Count, $verdicts.Count, (Format-Pct $TolPct)) -ForegroundColor Red
    foreach ($v in $failedVerdicts) {
        Write-Host ("  - FAILED: {0} · 基线中位={1} · 当前中位={2} · 回归={3}%" -f `
                $v.algorithm, (Format-Num $v.baseline_median), (Format-Num $v.current_median), (Format-Pct $v.regression_pct)) -ForegroundColor Red
    }
    exit 1
}

Write-Host ("::notice::Regression gate PASSED: {0} 个算法均未超过 {1}% 容差。" -f `
        $verdicts.Count, (Format-Pct $TolPct)) -ForegroundColor Green
exit 0
