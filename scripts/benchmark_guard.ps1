param(
    [string]$BaselinePath = "benches\results\latest-smoke.json",
    [string]$Target = "wasm-gc",
    [int]$Iterations = 5,
    [int]$Warmup = 1,
    [double]$MaxRegressionPercent = 50.0,
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
    throw "Baseline benchmark artifact not found: $baselineFullPath"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToString("o")
$tempOutDir = Join-Path "_build\benchmark-guard" $timestamp
$tempOutFullPath = Join-Path $root $tempOutDir
New-Item -ItemType Directory -Force -Path $tempOutFullPath | Out-Null

$benchScript = Join-Path $PSScriptRoot "benchmark_smoke.ps1"
$benchArgs = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $benchScript,
    "-Target",
    $Target,
    "-Iterations",
    $Iterations,
    "-Warmup",
    $Warmup,
    "-OutDir",
    $tempOutDir
)
if ($NoRelease.IsPresent) {
    $benchArgs += "-NoRelease"
}

Write-Host "=== BENCHMARK GUARD RUN ==="
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
    throw "benchmark_smoke.ps1 failed with exit code $benchExit"
}

$currentPath = Join-Path $tempOutFullPath "latest-smoke.json"
if (-not (Test-Path -LiteralPath $currentPath)) {
    throw "Current benchmark artifact was not generated: $currentPath"
}

$baseline = Get-Content -LiteralPath $baselineFullPath -Encoding UTF8 | ConvertFrom-Json
$current = Get-Content -LiteralPath $currentPath -Encoding UTF8 | ConvertFrom-Json

if ($baseline.schema -ne "moonbit-pathfinding.benchmark-smoke.v1") {
    throw "Unsupported baseline schema: $($baseline.schema)"
}
if ($current.schema -ne "moonbit-pathfinding.benchmark-smoke.v1") {
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
        $failures.Add("Missing current benchmark for $($baseBench.algorithm)")
        continue
    }
    $curBench = $currentByAlgorithm[$baseBench.algorithm]
    $baseMedian = [double]$baseBench.stats.median_ms
    $curMedian = [double]$curBench.stats.median_ms
    if ($baseMedian -le 0.0) {
        $failures.Add("Invalid baseline median for $($baseBench.algorithm): $baseMedian")
        continue
    }
    $delta = $curMedian - $baseMedian
    $pct = ($delta / $baseMedian) * 100.0
    $regressed = $pct -gt $MaxRegressionPercent
    if ($regressed) {
        $failures.Add(("{0} median regression {1}% exceeds threshold {2}% ({3} ms -> {4} ms)" -f $baseBench.algorithm, [Math]::Round($pct, 3), $MaxRegressionPercent, $baseMedian, $curMedian))
    }
    $comparisons.Add([ordered]@{
        algorithm = $baseBench.algorithm
        baseline_median_ms = [Math]::Round($baseMedian, 3)
        current_median_ms = [Math]::Round($curMedian, 3)
        delta_ms = [Math]::Round($delta, 3)
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
    schema = "moonbit-pathfinding.benchmark-guard.v1"
    generated_at = $generatedAt
    generated_by = "scripts/benchmark_guard.ps1"
    status = $status
    baseline_path = $baselineFullPath
    current_path = $currentPath
    target = $current.target
    release = [bool]$current.release
    warmup = $Warmup
    iterations = $Iterations
    max_regression_percent = $MaxRegressionPercent
    measurement_scope = "Compares median end-to-end smoke timings against a checked-in baseline. Intended as an early regression guard, not a cross-language performance claim."
    comparisons = $comparisons.ToArray()
    failures = $failures.ToArray()
    benchmark_output = $benchOutput.ToArray()
}

$reportJson = $report | ConvertTo-Json -Depth 12
$reportJsonPath = Join-Path $reportRoot ("guard-$Target-$timestamp.json")
$latestReportJsonPath = Join-Path $reportRoot "latest-guard.json"
[IO.File]::WriteAllText($reportJsonPath, $reportJson + "`n", [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($latestReportJsonPath, $reportJson + "`n", [Text.Encoding]::UTF8)

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Benchmark Guard Report")
$md.Add("")
$md.Add("- Generated at: ``$generatedAt``")
$md.Add("- Baseline: ``$baselineFullPath``")
$md.Add("- Current run: ``$currentPath``")
$md.Add("- Target: ``$($current.target)``")
$md.Add("- Release: ``$([bool]$current.release)``")
$md.Add("- Warmup: ``$Warmup``")
$md.Add("- Iterations: ``$Iterations``")
$md.Add("- Max regression: ``$MaxRegressionPercent%``")
$md.Add("- Status: ``$status``")
$md.Add("")
$md.Add("| Algorithm | Baseline median ms | Current median ms | Delta ms | Delta % | Status |")
$md.Add("|---|---:|---:|---:|---:|---|")
foreach ($cmp in $comparisons) {
    $md.Add("| $($cmp.algorithm) | $($cmp.baseline_median_ms) | $($cmp.current_median_ms) | $($cmp.delta_ms) | $($cmp.delta_percent) | $($cmp.status) |")
}
if ($failures.Count -gt 0) {
    $md.Add("")
    $md.Add("## Failures")
    foreach ($failure in $failures) {
        $md.Add("- $failure")
    }
}
$md.Add("")
$md.Add("Raw JSON: ``$(Split-Path -Leaf $reportJsonPath)`` and ``latest-guard.json``.")

$reportMdPath = Join-Path $reportRoot "latest-guard.md"
[IO.File]::WriteAllText($reportMdPath, ($md -join "`n") + "`n", [Text.Encoding]::UTF8)

Write-Host "=== BENCHMARK GUARD REPORT ==="
Write-Host $reportJsonPath
Write-Host $latestReportJsonPath
Write-Host $reportMdPath

if ($failures.Count -gt 0) {
    throw "Benchmark guard failed: $($failures -join '; ')"
}
