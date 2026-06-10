param(
    [string]$BaselinePath = "benches\results\latest-native.json",
    [string]$Target = "wasm-gc",
    [int]$Repeats = 3,
    [int]$Warmup = 1,
    [double]$MaxRegressionPercent = 25.0,
    [switch]$NoRelease,
    [string]$ReportDir = "benches\results"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if ($MaxRegressionPercent -lt 0.0) {
    throw "MaxRegressionPercent must be non-negative."
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$baselineFullPath = if ([IO.Path]::IsPathRooted($BaselinePath)) {
    $BaselinePath
} else {
    Join-Path $root $BaselinePath
}
if (-not (Test-Path -LiteralPath $baselineFullPath)) {
    throw "Native benchmark baseline not found: $baselineFullPath"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToString("o")
$tempOutDir = Join-Path "_build\native-benchmark-guard" $timestamp
$tempOutFullPath = Join-Path $root $tempOutDir
New-Item -ItemType Directory -Force -Path $tempOutFullPath | Out-Null

$benchScript = Join-Path $PSScriptRoot "benchmark_native.ps1"
$benchArgs = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $benchScript,
    "-Target",
    $Target,
    "-Repeats",
    $Repeats,
    "-Warmup",
    $Warmup,
    "-OutDir",
    $tempOutDir
)
if ($NoRelease.IsPresent) {
    $benchArgs += "-NoRelease"
}

Write-Host "=== NATIVE BENCHMARK GUARD RUN ==="
Write-Host "Baseline: $baselineFullPath"
Write-Host "Temp output: $tempOutFullPath"
Write-Host "Regression threshold: $MaxRegressionPercent%"

$benchOutput = New-Object System.Collections.Generic.List[string]
& pwsh @benchArgs 2>&1 | ForEach-Object {
    $line = [string]$_
    $benchOutput.Add($line)
    Write-Host $line
}
$benchExit = $LASTEXITCODE
if ($benchExit -ne 0) {
    throw "benchmark_native.ps1 failed with exit code $benchExit"
}

$currentPath = Join-Path $tempOutFullPath "latest-native.json"
if (-not (Test-Path -LiteralPath $currentPath)) {
    throw "Current native benchmark artifact was not generated: $currentPath"
}

$baseline = Get-Content -LiteralPath $baselineFullPath -Encoding UTF8 | ConvertFrom-Json
$current = Get-Content -LiteralPath $currentPath -Encoding UTF8 | ConvertFrom-Json

if ($baseline.schema -ne "moonbit-pathfinding.benchmark-native.v1") {
    throw "Unsupported baseline schema: $($baseline.schema)"
}
if ($current.schema -ne "moonbit-pathfinding.benchmark-native.v1") {
    throw "Unsupported current schema: $($current.schema)"
}
if ($baseline.target -ne $current.target) {
    throw "Target mismatch: baseline=$($baseline.target), current=$($current.target)"
}
if ([bool]$baseline.release -ne [bool]$current.release) {
    throw "Release-mode mismatch: baseline=$($baseline.release), current=$($current.release)"
}

$currentByAlgorithm = @{}
foreach ($bench in $current.benchmarks) {
    $currentByAlgorithm[$bench.algorithm] = $bench
}

$comparisons = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]
foreach ($baseBench in $baseline.benchmarks) {
    if (-not $currentByAlgorithm.ContainsKey($baseBench.algorithm)) {
        $failures.Add("Missing current native benchmark for $($baseBench.algorithm)")
        continue
    }
    $curBench = $currentByAlgorithm[$baseBench.algorithm]
    $baseMedian = [double]$baseBench.summary.median_us
    $curMedian = [double]$curBench.summary.median_us
    if ($baseMedian -le 0.0) {
        $failures.Add("Invalid baseline native median for $($baseBench.algorithm): $baseMedian")
        continue
    }
    $delta = $curMedian - $baseMedian
    $pct = ($delta / $baseMedian) * 100.0
    $regressed = $pct -gt $MaxRegressionPercent
    if ($regressed) {
        $failures.Add(("{0} native median regression {1}% exceeds threshold {2}% ({3} us -> {4} us)" -f $baseBench.algorithm, [Math]::Round($pct, 3), $MaxRegressionPercent, $baseMedian, $curMedian))
    }
    $comparisons.Add([ordered]@{
        algorithm = $baseBench.algorithm
        baseline_median_us = [Math]::Round($baseMedian, 3)
        current_median_us = [Math]::Round($curMedian, 3)
        delta_us = [Math]::Round($delta, 3)
        delta_percent = [Math]::Round($pct, 3)
        threshold_percent = $MaxRegressionPercent
        status = if ($regressed) { "fail" } else { "pass" }
    })
}

$status = if ($failures.Count -eq 0) { "pass" } else { "fail" }
$reportRoot = if ([IO.Path]::IsPathRooted($ReportDir)) {
    $ReportDir
} else {
    Join-Path $root $ReportDir
}
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$report = [ordered]@{
    schema = "moonbit-pathfinding.benchmark-native-guard.v1"
    generated_at = $generatedAt
    generated_by = "scripts/benchmark_native_guard.ps1"
    status = $status
    baseline_path = $baselineFullPath
    current_path = $currentPath
    target = $current.target
    release = [bool]$current.release
    warmup = $Warmup
    repeats = $Repeats
    max_regression_percent = $MaxRegressionPercent
    measurement_scope = "Compares median moon bench-reported mean times against a checked-in native benchmark baseline."
    comparisons = $comparisons.ToArray()
    failures = $failures.ToArray()
    benchmark_output = $benchOutput.ToArray()
}

$reportJson = $report | ConvertTo-Json -Depth 12
$reportJsonPath = Join-Path $reportRoot ("native-guard-$Target-$timestamp.json")
$latestReportJsonPath = Join-Path $reportRoot "latest-native-guard.json"
[IO.File]::WriteAllText($reportJsonPath, $reportJson + "`n", [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($latestReportJsonPath, $reportJson + "`n", [Text.Encoding]::UTF8)

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Native Benchmark Guard Report")
$md.Add("")
$md.Add("- Generated at: ``$generatedAt``")
$md.Add("- Baseline: ``$baselineFullPath``")
$md.Add("- Current run: ``$currentPath``")
$md.Add("- Target: ``$($current.target)``")
$md.Add("- Release: ``$([bool]$current.release)``")
$md.Add("- Warmup: ``$Warmup``")
$md.Add("- Repeats: ``$Repeats``")
$md.Add("- Max regression: ``$MaxRegressionPercent%``")
$md.Add("- Status: ``$status``")
$md.Add("")
$md.Add("| Algorithm | Baseline median us | Current median us | Delta us | Delta % | Status |")
$md.Add("|---|---:|---:|---:|---:|---|")
foreach ($cmp in $comparisons) {
    $md.Add("| $($cmp.algorithm) | $($cmp.baseline_median_us) | $($cmp.current_median_us) | $($cmp.delta_us) | $($cmp.delta_percent) | $($cmp.status) |")
}
if ($failures.Count -gt 0) {
    $md.Add("")
    $md.Add("## Failures")
    foreach ($failure in $failures) {
        $md.Add("- $failure")
    }
}
$md.Add("")
$md.Add("Raw JSON: ``$(Split-Path -Leaf $reportJsonPath)`` and ``latest-native-guard.json``.")

$reportMdPath = Join-Path $reportRoot "latest-native-guard.md"
[IO.File]::WriteAllText($reportMdPath, ($md -join "`n") + "`n", [Text.Encoding]::UTF8)

Write-Host "=== NATIVE BENCHMARK GUARD REPORT ==="
Write-Host $reportJsonPath
Write-Host $latestReportJsonPath
Write-Host $reportMdPath

if ($failures.Count -gt 0) {
    throw "Native benchmark guard failed: $($failures -join '; ')"
}
