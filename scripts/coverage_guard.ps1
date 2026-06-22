#!/usr/bin/env pwsh
# ──────────────────────────────────────────────────────────────────────
# coverage_guard.ps1 — 任务 17.1 · 行覆盖率硬门禁（Coverage_Guard, R18）
# ──────────────────────────────────────────────────────────────────────
# 用途（对应 design.md §5.3 与 requirements.md Requirement 18）：
#   在既有 check_coverage.ps1 的基础上扩展为「R18 行覆盖率门禁」：
#     1. 运行 `moon coverage analyze` 度量行覆盖率；被测源定义为「既非测试
#        也非基准」的 `*.mbt` 文件——默认排除 `*_test.mbt`、`*_wbtest.mbt`
#        以及 `benches/` 目录下的文件（R18.1）。本仓库的 `tests/` 目录同样
#        是测试代码（PBT/模糊测试包），按「既非测试」语义一并排除。
#     2. 在至少一个后端（默认 wasm-gc）上度量并记录 Line_Coverage 数值
#        （百分比保留至少一位小数）及对应后端名称（R18.2）。
#     3. IF Line_Coverage < 阈值（默认 95.0%）：以「文件路径 + 行号」列出
#        全部未覆盖代码位置，并以非零退出状态使门禁失败（R18.3）。
#     4. IF `moon coverage analyze` 执行失败或其输出不可解析：使门禁失败、
#        输出失败原因，且「不判定覆盖率达标」（R18.4）。
#
# 实现说明：
#   `moon coverage analyze` 默认在终端打印 caret 诊断，但会在结束时清理
#   trace 文件，无法事后再生成机器可解析报告。因此本脚本以
#       moon coverage analyze -- -f coveralls -o <tmp.json>
#   一次性「运行 analyze」并直接产出 Coveralls/CodeCov JSON 报告：
#   其 source_files[].coverage 数组逐行给出命中次数（null=非可执行行、
#   0=未覆盖、>0=已覆盖），据此既能聚合百分比（R18.1/18.2），又能精确
#   定位「文件路径 + 行号」级别的未覆盖位置（R18.3）。
#
# 退出码约定：
#   0  —— Line_Coverage ≥ 阈值，且 analyze 成功、报告可解析。
#   1  —— Line_Coverage < 阈值（R18.3），或 analyze 执行失败 / 输出不可
#         解析（R18.4），或报告写出失败。
#   2  —— 前置条件不满足（如 moon 不在 PATH）。
#
# 兼容性：面向 pwsh（PowerShell 7+）编写，同时兼容 Windows PowerShell 5.1
#   （不使用 null 合并 / 三元等 7+ 专属语法）。
# ──────────────────────────────────────────────────────────────────────

[CmdletBinding()]
param(
    # 行覆盖率阈值（百分比）。<0 时回退到 COVERAGE_THRESHOLD 环境变量，
    # 仍未提供则取 R18 规定的 95.0。
    [double]$Threshold = -1,
    # 度量所用后端名称，记入报告（R18.2）。`moon coverage analyze` 默认在
    # wasm-gc 后端执行；此参数仅用于「记录后端名称」，不改变 analyze 行为。
    [string]$Backend = "wasm-gc",
    # 报告产物输出目录。
    [string]$OutDir = "docs/verification",
    # 控制台最多打印多少条未覆盖位置（完整清单始终写入产物）。
    [int]$MaxListed = 100,
    # 被测源排除模式（PowerShell -like 通配）。默认实现 R18.1 的三类排除，
    # 并额外排除测试目录 tests/（其文件为 PBT/模糊测试，属「测试」范畴）。
    [string[]]$ExcludeGlobs = @('*_test.mbt', '*_wbtest.mbt', 'benches/*', 'tests/*')
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 文本产物统一使用「无 BOM」的 UTF-8，确保 JSON 可被严格解析器直接读取。
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# 百分比格式化：固定保留 1 位小数且使用不变文化（点号小数），满足 R18.2
# 「百分比保留至少一位小数」的记录要求（如 84.0 而非 84）。
function Format-Pct {
    param([double]$Value)
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F1}", $Value)
}

# ───────────────────────── 阈值解析（兼容 5.1，不用 null 合并） ─────────────────────────

if ($Threshold -lt 0) {
    if ($env:COVERAGE_THRESHOLD) {
        $Threshold = [double]$env:COVERAGE_THRESHOLD
    } else {
        $Threshold = 95.0
    }
}

Write-Host "=== Coverage Gate (task 17.1 · R18) ===" -ForegroundColor Cyan
Write-Host ("Threshold : line coverage >= {0}% (被测源，排除 {1})" -f (Format-Pct $Threshold), ($ExcludeGlobs -join ', '))
Write-Host ("Backend   : {0}" -f $Backend)

# ───────────────────────── 路径解析与前置检查 ─────────────────────────

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = if ([IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $root $OutDir }

$moonCmd = Get-Command moon -ErrorAction SilentlyContinue
if ($null -eq $moonCmd) {
    Write-Host "::error::'moon' 不在 PATH 中，无法运行覆盖率门禁。" -ForegroundColor Red
    exit 2
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# 临时 coveralls JSON 报告路径。
$covJson = Join-Path ([IO.Path]::GetTempPath()) ("moonbit-coverage-{0}.json" -f $timestamp)

# ───────────────────── 失败收尾：写出诊断产物并以指定码退出 ─────────────────────
# 即便门禁失败（R18.3/R18.4），也尽量写出报告产物，便于审计与排查。

function Write-CoverageArtifacts {
    param(
        [object]$Artifact,
        [string[]]$MarkdownLines
    )
    try {
        New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
        $json = $Artifact | ConvertTo-Json -Depth 12
        $jsonPath = Join-Path $outRoot ("coverage-guard-$timestamp.json")
        $latestJson = Join-Path $outRoot "latest-coverage-guard.json"
        $mdPath = Join-Path $outRoot "latest-coverage-guard.md"
        [IO.File]::WriteAllText($jsonPath, $json + "`n", $Utf8NoBom)
        [IO.File]::WriteAllText($latestJson, $json + "`n", $Utf8NoBom)
        [IO.File]::WriteAllText($mdPath, ($MarkdownLines -join "`n") + "`n", $Utf8NoBom)
        Write-Host "=== COVERAGE GUARD ARTIFACTS ===" -ForegroundColor Cyan
        Write-Host $jsonPath
        Write-Host $latestJson
        Write-Host $mdPath
        return $true
    } catch {
        Write-Host "::error::覆盖率报告写出失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ───────────────────── 1. 运行 moon coverage analyze（产出 coveralls JSON） ─────────────────────

Write-Host ""
Write-Host "--- 运行 moon coverage analyze（-- -f coveralls） ---" -ForegroundColor Cyan

if (Test-Path -LiteralPath $covJson) { Remove-Item -LiteralPath $covJson -Force }

$analyzeOutput = New-Object System.Collections.Generic.List[string]
& moon coverage analyze -- -f coveralls -o $covJson 2>&1 | ForEach-Object {
    $line = [string]$_
    $analyzeOutput.Add($line)
}
$analyzeExit = $LASTEXITCODE

# R18.4：执行失败（进程非零退出 或 未产出报告文件）→ 门禁失败，不判定达标。
$produced = Test-Path -LiteralPath $covJson
if ($analyzeExit -ne 0 -or -not $produced) {
    $reason = if (-not $produced) {
        "moon coverage analyze 未产出覆盖率报告文件（$covJson 不存在）。"
    } else {
        "moon coverage analyze 以非零状态退出（exit=$analyzeExit）。"
    }
    Write-Host "::error::覆盖率门禁失败（R18.4）：$reason" -ForegroundColor Red
    $tailCount = [Math]::Min(40, $analyzeOutput.Count)
    if ($tailCount -gt 0) {
        Write-Host "--- analyze 输出末尾 $tailCount 行 ---" -ForegroundColor Yellow
        $analyzeOutput[($analyzeOutput.Count - $tailCount)..($analyzeOutput.Count - 1)] | ForEach-Object { Write-Host "  $_" }
    }
    $artifact = [ordered]@{
        schema       = "moonbit-pathfinding.coverage-guard.v1"
        generated_at = $generatedAt
        generated_by = "scripts/coverage_guard.ps1"
        backend      = $Backend
        threshold    = $Threshold
        status       = "error"
        parse_ok     = $false
        reason       = $reason
        analyze_exit = $analyzeExit
    }
    $md = @(
        "# Coverage Guard Report",
        "",
        "- Generated at: $generatedAt",
        "- Backend: $Backend",
        "- Threshold: $(Format-Pct $Threshold)%",
        "- Status: ERROR（R18.4）",
        "- Reason: $reason",
        ""
    )
    [void](Write-CoverageArtifacts -Artifact $artifact -MarkdownLines $md)
    exit 1
}

# ───────────────────── 2. 解析 coveralls JSON（不可解析 → R18.4） ─────────────────────

$report = $null
try {
    $raw = Get-Content -LiteralPath $covJson -Raw -Encoding UTF8
    $report = $raw | ConvertFrom-Json
} catch {
    Write-Host "::error::覆盖率门禁失败（R18.4）：coveralls 报告 JSON 解析失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($null -eq $report -or $null -eq $report.source_files) {
    Write-Host "::error::覆盖率门禁失败（R18.4）：报告缺少 source_files 字段，输出不可解析。" -ForegroundColor Red
    exit 1
}

# ───────────────────── 3. 过滤被测源并逐行聚合（R18.1 / R18.3） ─────────────────────

function Test-Excluded {
    param([string]$Path, [string[]]$Globs)
    foreach ($g in $Globs) {
        if ($Path -like $g) { return $true }
    }
    return $false
}

$covered = 0
$total = 0
$uncovered = New-Object System.Collections.Generic.List[string]   # "path:line"
$perFile = New-Object System.Collections.Generic.List[object]
$includedFiles = 0

foreach ($sf in $report.source_files) {
    $name = [string]$sf.name
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $norm = $name -replace '\\', '/'
    if (Test-Excluded -Path $norm -Globs $ExcludeGlobs) { continue }

    $includedFiles += 1
    $fileCovered = 0
    $fileTotal = 0
    $cov = $sf.coverage
    if ($null -ne $cov) {
        for ($i = 0; $i -lt $cov.Count; $i++) {
            $hit = $cov[$i]
            if ($null -eq $hit) { continue }   # 非可执行行
            $fileTotal += 1
            if ([int]$hit -gt 0) {
                $fileCovered += 1
            } else {
                # coverage[i] 对应源代码第 (i+1) 行。
                $uncovered.Add(("{0}:{1}" -f $norm, ($i + 1)))
            }
        }
    }
    $covered += $fileCovered
    $total += $fileTotal
    if ($fileTotal -gt 0) {
        $filePct = [math]::Round($fileCovered * 100.0 / $fileTotal, 1)
        $perFile.Add([pscustomobject]@{
                path    = $norm
                covered = $fileCovered
                total   = $fileTotal
                percent = $filePct
            })
    }
}

# R18.4：无任何可执行行 → 无法判定覆盖率，门禁失败。
if ($total -eq 0) {
    Write-Host "::error::覆盖率门禁失败（R18.4）：过滤后无任何被测源可执行行，无法判定覆盖率。" -ForegroundColor Red
    Write-Host ("  匹配文件数={0}，排除模式={1}" -f $includedFiles, ($ExcludeGlobs -join ', ')) -ForegroundColor Yellow
    exit 1
}

# R18.2：记录 Line_Coverage 数值（保留至少一位小数）与后端名称。
$overall = [math]::Round($covered * 100.0 / $total, 1)
$overallPct = Format-Pct $overall
$thresholdPct = Format-Pct $Threshold
$passed = $overall -ge $Threshold

# ───────────────────── 4. 组装产物（MD + JSON） ─────────────────────

# 覆盖率最低的文件优先（便于定位冷模块）。
$coldFiles = $perFile | Sort-Object percent | Select-Object -First 15

$status = if ($passed) { "passed" } else { "failed" }
$artifact = [ordered]@{
    schema          = "moonbit-pathfinding.coverage-guard.v1"
    generated_at    = $generatedAt
    generated_by    = "scripts/coverage_guard.ps1"
    backend         = $Backend
    threshold       = $Threshold
    line_coverage   = $overall
    line_coverage_pct = $overallPct
    covered_lines   = $covered
    total_lines     = $total
    included_files  = $includedFiles
    exclude_globs   = $ExcludeGlobs
    status          = $status
    parse_ok        = $true
    uncovered_count = $uncovered.Count
    uncovered       = $uncovered.ToArray()
    coldest_files   = $coldFiles
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Coverage Guard Report")
$md.Add("")
$md.Add("- Generated at: $generatedAt")
$md.Add("- Script: scripts/coverage_guard.ps1")
$md.Add("- Backend: $Backend")
$md.Add(("- Line coverage: {0}% （covered {1} / total {2}）" -f $overallPct, $covered, $total))
$md.Add("- Threshold: $thresholdPct%")
$md.Add("- Status: $($status.ToUpper())")
$md.Add("- Included source files: $includedFiles")
$md.Add("- Exclude globs: " + ($ExcludeGlobs -join ', '))
$md.Add("- Uncovered lines: $($uncovered.Count)")
$md.Add("")
$md.Add("## 覆盖率最低的文件（Top 15）")
$md.Add("")
$md.Add("| 文件 | 已覆盖 | 可执行 | 覆盖率 |")
$md.Add("| --- | ---: | ---: | ---: |")
foreach ($f in $coldFiles) {
    $md.Add(("| {0} | {1} | {2} | {3}% |" -f $f.path, $f.covered, $f.total, (Format-Pct $f.percent)))
}
$md.Add("")
$md.Add("## 未覆盖代码位置（文件路径 + 行号 · R18.3）")
$md.Add("")
if ($uncovered.Count -eq 0) {
    $md.Add("（无未覆盖位置）")
} else {
    foreach ($u in $uncovered) { $md.Add("- $u") }
}
$md.Add("")

$wrote = Write-CoverageArtifacts -Artifact $artifact -MarkdownLines $md.ToArray()
if (-not $wrote) {
    # 报告写出失败按门禁失败处理。
    exit 1
}

# ───────────────────── 5. 控制台摘要与门禁退出语义 ─────────────────────

Write-Host ""
Write-Host "--- Aggregate（被测源） ---" -ForegroundColor Cyan
Write-Host ("Line coverage: {0}/{1} = {2}% on backend '{3}'" -f $covered, $total, $overallPct, $Backend)
Write-Host ("Included source files: {0}" -f $includedFiles)

if (-not $passed) {
    # R18.3：以「文件路径 + 行号」列出未覆盖位置并非零退出。
    Write-Host ("::error::Coverage gate FAILED: {0}% < {1}% threshold（backend={2}）" -f $overallPct, $thresholdPct, $Backend) -ForegroundColor Red
    Write-Host ("--- 未覆盖代码位置（共 {0} 处，文件路径+行号） ---" -f $uncovered.Count) -ForegroundColor Yellow
    $shown = [Math]::Min($MaxListed, $uncovered.Count)
    for ($i = 0; $i -lt $shown; $i++) {
        Write-Host ("  {0}" -f $uncovered[$i])
    }
    if ($uncovered.Count -gt $shown) {
        Write-Host ("  … 其余 {0} 处见报告产物 latest-coverage-guard.md" -f ($uncovered.Count - $shown)) -ForegroundColor Yellow
    }
    exit 1
}

Write-Host ("::notice::Coverage gate PASSED: {0}% >= {1}% threshold（backend={2}）" -f $overallPct, $thresholdPct, $Backend) -ForegroundColor Green
exit 0
