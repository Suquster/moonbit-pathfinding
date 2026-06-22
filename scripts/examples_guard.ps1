#!/usr/bin/env pwsh
# ──────────────────────────────────────────────────────────────────────
# examples_guard.ps1 — 任务 29.5 · 文档即测试校验门禁（Examples_Guard）
# ──────────────────────────────────────────────────────────────────────
# 用途（对应 design.md §6.2/§6.3 与 requirements.md Requirement 20/21）：
#   以「文档即测试」方式守护 README.mbt.md 中的全部可执行示例与 Cookbook：
#     1. 运行 `moon test README.mbt.md`，将示例 1~6 的 6 段 ASCII 可视化/算法
#        示例与 Cookbook 22 个用例（共 28 个 ` ```mbt check ` 可执行测试）作为
#        测试编译与运行校验（R20.4）。可选地在 wasm-gc / js / native 三后端循环。
#     2. 解析 `Total tests: N, passed: P, failed: F.` 统计行，聚合每个后端的
#        总数 / 通过数 / 失败数。
#     3. IF 某文档示例编译失败或运行结果与预期（inspect 快照 / assert）不符：
#        使门禁失败（非零退出），并输出「定位到该示例」的诊断信息（失败测试名、
#        README.mbt.md 行号、最小化差异片段）（R20.5）。
#     4. Cookbook 用例实际输出与预期不符即「可重现性校验失败」，按差异位置
#        （失败用例 + README.mbt.md 行号）报告（R21.6）。
#
# 退出码约定：
#   0  —— 全部后端文档测试编译并运行通过（且达到期望测试数，如启用）。
#   1  —— 至少一个后端存在编译失败 / 结果不符 / 期望测试数不符，或输出不可
#         解析（无法判定通过），或报告写出失败（R20.5 / R21.6）。
#   2  —— 前置条件不满足（如 moon 不在 PATH，或文档文件缺失）。
#
# 兼容性：面向 pwsh（PowerShell 7+）编写，同时兼容 Windows PowerShell 5.1
#   （不使用 null 合并 / 三元等 7+ 专属语法），跨平台（Windows/Linux/macOS）。
# ──────────────────────────────────────────────────────────────────────

[CmdletBinding()]
param(
    # 文档即测试入口文件（相对仓库根或绝对路径）。
    [string]$DocFile = "README.mbt.md",
    # 参与校验的后端，逗号分隔；取自 wasm-gc / js / native 子集。默认仅 wasm-gc，
    # 传 "wasm-gc,js,native" 可做三后端一致性校验（R21.2）。
    [string]$Backends = "wasm-gc",
    # 期望的可执行测试总数（示例 1~6 共 6 段 + Cookbook 22 例 = 28）。
    # >0 时作为硬门禁：实际总数与之不符则失败（守护示例被静默删改）；
    # 置 0 可关闭该校验。
    [int]$ExpectedTotal = 28,
    # 报告产物输出目录。
    [string]$OutDir = "docs/verification",
    # 控制台最多打印多少条诊断定位行（完整清单始终写入产物）。
    [int]$MaxListed = 80
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 文本产物统一使用「无 BOM」UTF-8，确保 JSON 可被严格解析器直接读取。
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Write-Host "=== Examples Guard (task 29.5 · R20.4/R20.5/R21.6) ===" -ForegroundColor Cyan
Write-Host ("Doc file  : {0}" -f $DocFile)
Write-Host ("Backends  : {0}" -f $Backends)
if ($ExpectedTotal -gt 0) {
    Write-Host ("Expected  : Total tests == {0}（示例 6 段 + Cookbook 22 例）" -f $ExpectedTotal)
}

# ───────────────────────── 路径解析与前置检查 ─────────────────────────

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = if ([IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $root $OutDir }

$moonCmd = Get-Command moon -ErrorAction SilentlyContinue
if ($null -eq $moonCmd) {
    Write-Host "::error::'moon' 不在 PATH 中，无法运行文档即测试门禁。" -ForegroundColor Red
    exit 2
}

$docPath = if ([IO.Path]::IsPathRooted($DocFile)) { $DocFile } else { Join-Path $root $DocFile }
if (-not (Test-Path -LiteralPath $docPath)) {
    Write-Host ("::error::文档文件不存在: {0}" -f $docPath) -ForegroundColor Red
    exit 2
}

$backendList = @()
foreach ($b in ($Backends -split ',')) {
    $t = $b.Trim()
    if ($t.Length -gt 0) { $backendList += $t }
}
if ($backendList.Count -eq 0) {
    Write-Host "::error::未指定任何后端（-Backends 为空）。" -ForegroundColor Red
    exit 2
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# ───────────────────────── 命令捕获（合并 stdout+stderr） ─────────────────────────
# moon 的统计行走 stdout，编译诊断 / inspect 差异多走 stderr；两者都要捕获以便
# 既能解析 Total，也能在失败时定位到具体示例（R20.5）。本进程内清空 RUST_LOG，
# 避免 tracing 的 INFO 噪声污染诊断输出（保证「定位信息」清晰可读）。

function Invoke-MoonTest {
    param([string]$DocArg, [string]$Backend)

    $output = New-Object System.Collections.Generic.List[string]
    $prevRustLog = $env:RUST_LOG
    $env:RUST_LOG = ""
    try {
        & moon test $DocArg --target $Backend 2>&1 | ForEach-Object {
            $line = [string]$_
            $output.Add($line)
        }
        $code = $LASTEXITCODE
    } finally {
        $env:RUST_LOG = $prevRustLog
    }
    [ordered]@{
        backend   = $Backend
        exit_code = $code
        output    = $output.ToArray()
    }
}

# 聚合 "Total tests: N, passed: P, failed: F." 统计（可能多行）。
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

# 从输出中抽取「定位到示例」的诊断行（R20.5 / R21.6）：
#   - 失败测试名行（含 failed，且非统计行）
#   - 文档文件行号定位（README.mbt.md:NN[:CC]）
#   - 编译错误 / 类型错误（Error / error[: ]）
#   - inspect 最小化差异（Diff / expect / 以 + 或 - 开头的差异行 / caret ^）
function Get-DiagnosticLines {
    param([string[]]$Lines, [string]$DocLeaf)

    $diag = New-Object System.Collections.Generic.List[string]
    $docLeafEsc = [regex]::Escape($DocLeaf)
    foreach ($raw in $Lines) {
        $line = [string]$raw
        $trim = $line.Trim()
        if ($trim.Length -eq 0) { continue }
        $isStat = $trim -match 'Total tests:'
        $hit = $false
        if (-not $isStat -and $trim -match '(?i)\bfailed\b') { $hit = $true }
        if ($line -match ($docLeafEsc + ':\d+')) { $hit = $true }
        if ($trim -match '(?i)^error(\[|:|\b)') { $hit = $true }
        if ($trim -match '(?i)\b(Diff|expect(ed)?|mismatch|panic|abort)\b') { $hit = $true }
        if ($trim -match '^[+\-]\s' -or $trim -match '^\s*\^+\s*$') { $hit = $true }
        if ($hit) { $diag.Add($trim) }
    }
    # 去重并保持顺序。
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $uniq = New-Object System.Collections.Generic.List[string]
    foreach ($d in $diag) {
        if ($seen.Add($d)) { $uniq.Add($d) }
    }
    $uniq.ToArray()
}

# ───────────────────── 1. 跨后端运行文档即测试 ─────────────────────

$docLeaf = Split-Path -Leaf $docPath
$moonVersion = ((& moon version 2>&1 | ForEach-Object { [string]$_ }) -join " ")

$backendRuns = New-Object System.Collections.Generic.List[object]
$gateFailed = $false
$allFailures = New-Object System.Collections.Generic.List[string]

foreach ($backend in $backendList) {
    Write-Host ""
    Write-Host ("--- 运行 moon test {0} --target {1} ---" -f $DocFile, $backend) -ForegroundColor Cyan
    $run = Invoke-MoonTest -DocArg $DocFile -Backend $backend
    $totals = Get-TestTotals -Lines $run.output
    $diag = Get-DiagnosticLines -Lines $run.output -DocLeaf $docLeaf

    # 判定该后端是否通过：
    #   - 进程退出码必须为 0；
    #   - 统计行必须可解析（否则视为编译失败 / 不可判定 → R20.5）；
    #   - failed 必须为 0；
    #   - 若启用期望总数校验，total 必须等于期望值。
    $reasons = New-Object System.Collections.Generic.List[string]
    if ($run.exit_code -ne 0) {
        $reasons.Add(("进程以非零状态退出（exit={0}）：示例编译失败或结果不符" -f $run.exit_code))
    }
    if (-not $totals.parsed) {
        $reasons.Add("未解析到 'Total tests:' 统计行：文档示例可能编译失败，无法判定通过（R20.5）")
    } elseif ($totals.failed -gt 0) {
        $reasons.Add(("{0} 个文档示例运行结果与预期不符（R20.5/R21.6）" -f $totals.failed))
    }
    if ($ExpectedTotal -gt 0 -and $totals.parsed -and $totals.total -ne $ExpectedTotal) {
        $reasons.Add(("可执行测试总数 {0} 与期望 {1} 不符：示例/Cookbook 用例可能被增删" -f $totals.total, $ExpectedTotal))
    }

    $backendStatus = if ($reasons.Count -eq 0) { "passed" } else { "failed" }
    if ($backendStatus -ne "passed") {
        $gateFailed = $true
        foreach ($r in $reasons) { $allFailures.Add(("[{0}] {1}" -f $backend, $r)) }
    }

    # 控制台摘要。
    if ($totals.parsed) {
        Write-Host ("  Total tests: {0}, passed: {1}, failed: {2}" -f $totals.total, $totals.passed, $totals.failed)
    } else {
        Write-Host "  （未解析到统计行）" -ForegroundColor Yellow
    }
    if ($backendStatus -eq "passed") {
        Write-Host ("::notice::[{0}] 文档即测试通过：{1}/{2} 个示例全部通过。" -f $backend, $totals.passed, $totals.total) -ForegroundColor Green
    } else {
        Write-Host ("::error::[{0}] 文档即测试失败：" -f $backend) -ForegroundColor Red
        foreach ($r in $reasons) { Write-Host ("    - {0}" -f $r) -ForegroundColor Red }
        if ($diag.Length -gt 0) {
            Write-Host ("  --- 定位诊断（共 {0} 条，文件 {1}） ---" -f $diag.Length, $docLeaf) -ForegroundColor Yellow
            $shown = [Math]::Min($MaxListed, $diag.Length)
            for ($i = 0; $i -lt $shown; $i++) {
                Write-Host ("    {0}" -f $diag[$i])
            }
            if ($diag.Length -gt $shown) {
                Write-Host ("    … 其余 {0} 条见报告产物 latest-examples-guard.md" -f ($diag.Length - $shown)) -ForegroundColor Yellow
            }
        }
    }

    $backendRuns.Add([ordered]@{
            backend          = $backend
            exit_code        = $run.exit_code
            totals           = $totals
            status           = $backendStatus
            reasons          = $reasons.ToArray()
            diagnostics      = $diag
            command          = @("moon", "test", $DocFile, "--target", $backend)
            output           = $run.output
        })
}

# ───────────────────── 2. 组装报告产物（MD + JSON） ─────────────────────

$overallStatus = if ($gateFailed) { "failed" } else { "passed" }
$backendLabel = ($backendList -join "/")

$artifact = [ordered]@{
    schema         = "moonbit-pathfinding.examples-guard.v1"
    generated_at   = $generatedAt
    generated_by   = "scripts/examples_guard.ps1"
    moon_version   = $moonVersion
    doc_file       = $DocFile
    backends       = $backendList
    expected_total = $ExpectedTotal
    status         = $overallStatus
    failures       = $allFailures.ToArray()
    backend_runs   = $backendRuns.ToArray()
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Examples Guard Report")
$md.Add("")
$md.Add("- Generated at: $generatedAt")
$md.Add("- Script: scripts/examples_guard.ps1")
$md.Add("- Doc file: $DocFile（文档即测试 · R20.4/R20.5/R21.6）")
$md.Add("- MoonBit: $moonVersion")
$md.Add("- Backends: $backendLabel")
if ($ExpectedTotal -gt 0) {
    $md.Add("- Expected total tests: $ExpectedTotal（示例 6 段 + Cookbook 22 例）")
}
$md.Add("- Status: $($overallStatus.ToUpper())")
$md.Add("")
$md.Add("## 各后端文档测试汇总")
$md.Add("")
$md.Add("| 后端 | 退出码 | 总数 | 通过 | 失败 | 状态 |")
$md.Add("| --- | ---: | ---: | ---: | ---: | --- |")
foreach ($brun in $backendRuns) {
    $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} |" -f `
                $brun.backend, $brun.exit_code, $brun.totals.total, $brun.totals.passed, $brun.totals.failed, $brun.status))
}
if ($allFailures.Count -gt 0) {
    $md.Add("")
    $md.Add("## 失败原因")
    $md.Add("")
    foreach ($f in $allFailures) { $md.Add("- $f") }
}
# 逐后端定位诊断（R20.5 / R21.6：报告差异位置）。
foreach ($brun in $backendRuns) {
    if ($brun.status -ne "passed" -and $brun.diagnostics.Length -gt 0) {
        $md.Add("")
        $md.Add(("## 定位诊断 · 后端 {0}（文件路径 + 行号 / 最小化差异）" -f $brun.backend))
        $md.Add("")
        foreach ($d in $brun.diagnostics) { $md.Add("- $d") }
    }
}
$md.Add("")
$md.Add("## 覆盖范围说明")
$md.Add("")
$md.Add("- 示例 1~6：BFS / Dijkstra / A* / Kruskal / proof predicates / 复杂度表，含 ASCII 可视化（R20.1/R20.4）。")
$md.Add("- Cookbook 22 例：网格寻路 / 网络路由 / 任务调度 / 最大流 / 匹配 五类，每例含可执行命令与 inspect 预期输出（R21.1/R21.5）。")
$md.Add("- 任一示例编译失败或结果不符 → 门禁失败并定位（R20.5）；Cookbook 输出与预期不符 → 可重现性校验失败（R21.6）。")
$md.Add("")

# ───────────────────── 3. 写出产物（写失败即门禁失败） ─────────────────────

try {
    New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
    $json = $artifact | ConvertTo-Json -Depth 24
    $jsonPath = Join-Path $outRoot ("examples-guard-$timestamp.json")
    $latestJson = Join-Path $outRoot "latest-examples-guard.json"
    $mdPath = Join-Path $outRoot "latest-examples-guard.md"
    [IO.File]::WriteAllText($jsonPath, $json + "`n", $Utf8NoBom)
    [IO.File]::WriteAllText($latestJson, $json + "`n", $Utf8NoBom)
    [IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", $Utf8NoBom)
    Write-Host ""
    Write-Host "=== EXAMPLES GUARD ARTIFACTS ===" -ForegroundColor Cyan
    Write-Host $jsonPath
    Write-Host $latestJson
    Write-Host $mdPath
} catch {
    Write-Host "::error::Examples_Guard 报告写出失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ───────────────────── 4. 门禁退出语义 ─────────────────────

Write-Host ""
if ($gateFailed) {
    Write-Host "::error::文档即测试门禁失败：存在编译失败 / 结果不符 / 期望总数不符。详见上方定位诊断与报告产物。" -ForegroundColor Red
    exit 1
}

$passedSummary = New-Object System.Collections.Generic.List[string]
foreach ($brun in $backendRuns) {
    $passedSummary.Add(("{0}={1}/{2}" -f $brun.backend, $brun.totals.passed, $brun.totals.total))
}
Write-Host ("::notice::文档即测试门禁通过：{0}（backends={1}）" -f ($passedSummary -join ", "), $backendLabel) -ForegroundColor Green
exit 0
