#!/usr/bin/env pwsh
# ──────────────────────────────────────────────────────────────────────
# check_coverage.ps1 — Task 28.2 覆盖率硬门禁
# ──────────────────────────────────────────────────────────────────────
# 用途:
#   解析 `moon coverage report -f summary` 的输出, 仅对 `src/` 核心库
#   聚合 line-coverage, 低于阈值则 exit 1, 供 CI 卡点使用。
#
# 设计要点 (对应 tasks.md 28.2):
#   1. 只统计 `src/**` 核心库, 排除 cmd/main、examples/**、tests/**
#      —— cmd/main 只是 CLI 入口, examples 是演示程序, tests/pbt/gen
#         是属性测试生成器, 它们都不构成交付库的"正向逻辑覆盖率"。
#   2. 阈值来自 `-Threshold` 参数或 `COVERAGE_THRESHOLD` 环境变量,
#      默认 85 (对应 R6.1 / R10.2)。
#   3. 若 `moon coverage report -f summary` 未能生成 (未先跑
#      `moon test --enable-coverage`), 脚本会提示并 exit 2。
#   4. 输出采用 CI 友好的 `::error::` / `::notice::` 前缀,
#      方便 GitHub Actions 在 PR check 里直接高亮。
# ──────────────────────────────────────────────────────────────────────

[CmdletBinding()]
param(
    [double]$Threshold = -1
)

$ErrorActionPreference = 'Stop'

# 解析默认阈值 (兼容 PowerShell 5.1, 不用 null 合并运算符)
if ($Threshold -lt 0) {
    if ($env:COVERAGE_THRESHOLD) {
        $Threshold = [double]$env:COVERAGE_THRESHOLD
    } else {
        $Threshold = 85.0
    }
}

Write-Host "=== Coverage Gate (task 28.2) ===" -ForegroundColor Cyan
Write-Host "Threshold: line coverage >= $Threshold% on src/ (core library)"

# 1. 采集 summary 输出。允许脚本自动驱动 test + analyze, 以便本地也能
#    一键跑; CI 里由 workflow 单独执行这些步骤, 此处只拿最新结果。
$summary = & moon coverage report -f summary 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "::error::moon coverage report failed (exit $LASTEXITCODE). Did you run 'moon test --enable-coverage' first?" -ForegroundColor Red
    $summary | ForEach-Object { Write-Host $_ }
    exit 2
}

# 2. 解析 "path: covered/total" 行, 仅保留 src/ 前缀 (兼容 / 和 \)。
$covered = 0
$total   = 0
$rows    = @()
foreach ($line in $summary) {
    if ($line -match '^(?<path>[^:]+):\s*(?<cov>\d+)\s*/\s*(?<tot>\d+)\s*$') {
        $p = $Matches['path']
        $c = [int]$Matches['cov']
        $t = [int]$Matches['tot']
        # 统一路径分隔符
        $norm = $p -replace '\\', '/'
        if ($norm -match '^src/') {
            $covered += $c
            $total   += $t
            $pct = if ($t -gt 0) { [math]::Round($c * 100.0 / $t, 2) } else { 100.0 }
            $rows += [pscustomobject]@{
                Path     = $norm
                Covered  = $c
                Total    = $t
                Percent  = $pct
            }
        }
    }
}

if ($total -eq 0) {
    Write-Host "::error::No src/ entries found in coverage summary. Output was:" -ForegroundColor Red
    $summary | ForEach-Object { Write-Host "  $_" }
    exit 2
}

# 3. 按覆盖率升序打印, 方便一眼看到冷模块。
Write-Host ""
Write-Host "--- Per-file coverage (src/ core library) ---" -ForegroundColor Cyan
$rows | Sort-Object Percent | Format-Table -AutoSize Path, Covered, Total, @{Name='Percent'; Expression={"{0,6:N2}%" -f $_.Percent}} | Out-String | Write-Host

$overall = [math]::Round($covered * 100.0 / $total, 2)
Write-Host ("--- Aggregate ---") -ForegroundColor Cyan
Write-Host ("src/ core library: {0}/{1} = {2}%" -f $covered, $total, $overall)

# 4. 硬门禁判定。
if ($overall -lt $Threshold) {
    Write-Host ("::error::Coverage gate FAILED: {0}% < {1}% threshold" -f $overall, $Threshold) -ForegroundColor Red
    exit 1
}

Write-Host ("::notice::Coverage gate PASSED: {0}% >= {1}% threshold" -f $overall, $Threshold) -ForegroundColor Green
exit 0
