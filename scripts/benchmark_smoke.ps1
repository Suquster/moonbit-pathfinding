param(
    [string]$Target = "wasm-gc",
    [int]$Iterations = 5,
    [int]$Warmup = 1,
    [switch]$NoRelease,
    [string]$OutDir = "benches\results"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if ($Iterations -le 0) {
    throw "Iterations must be positive."
}
if ($Warmup -lt 0) {
    throw "Warmup must be non-negative."
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$release = -not $NoRelease.IsPresent
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToString("o")

$benchmarks = @(
    [ordered]@{
        algorithm = "BFS"
        package = "taoyouce/moonbit-pathfinding/benches/bfs_bench"
        file = "benches/bfs_bench/bfs_bench.mbt"
        scenario = "1k-node sparse directed graph, density 1%, query 0 -> 999"
        input = [ordered]@{ nodes = 1000; density = 0.01; seed = 42; edge_kind = "unweighted directed" }
        baseline = "Smoke gate only; verifies termination and endpoint invariants, not a published speedup claim."
    },
    [ordered]@{
        algorithm = "Dijkstra"
        package = "taoyouce/moonbit-pathfinding/benches/dijkstra_bench"
        file = "benches/dijkstra_bench/dijkstra_bench.mbt"
        scenario = "1k-node sparse weighted directed graph, density 1%, query 0 -> 999"
        input = [ordered]@{ nodes = 1000; density = 0.01; seed = 7; max_weight = 10; edge_kind = "non-negative weighted directed" }
        baseline = "Smoke gate only; verifies shortest-path output invariants, not a published cross-language comparison."
    },
    [ordered]@{
        algorithm = "A*"
        package = "taoyouce/moonbit-pathfinding/benches/astar_bench"
        file = "benches/astar_bench/astar_bench.mbt"
        scenario = "32x32 open 4-neighbour grid with Manhattan heuristic, query (0,0) -> (31,31)"
        input = [ordered]@{ width = 32; height = 32; nodes = 1024; expected_cost = 62; heuristic = "Manhattan" }
        baseline = "Correctness baseline is the Manhattan distance on an open grid."
    },
    [ordered]@{
        algorithm = "Kruskal MST"
        package = "taoyouce/moonbit-pathfinding/benches/kruskal_bench"
        file = "benches/kruskal_bench/kruskal_bench.mbt"
        scenario = "1k-node 10k-edge weighted undirected multigraph"
        input = [ordered]@{ nodes = 1000; edges = 10000; seed = 17; max_weight = 100; edge_kind = "weighted undirected multigraph" }
        baseline = "Smoke gate only; verifies MSF edge-count and weight-range invariants."
    }
)

function Invoke-BenchCommand {
    param(
        [string]$Package
    )

    $moonArgs = @("test", "-p", $Package, "--target", $Target, "--no-parallelize")
    if ($release) {
        $moonArgs += "--release"
    }

    $output = New-Object System.Collections.Generic.List[string]
    $elapsed = Measure-Command {
        & moon @moonArgs 2>&1 | ForEach-Object { $output.Add([string]$_) }
    }
    $code = $LASTEXITCODE

    [ordered]@{
        command = @("moon") + $moonArgs
        elapsed_ms = [Math]::Round($elapsed.TotalMilliseconds, 3)
        exit_code = $code
        output = $output.ToArray()
    }
}

function Get-Stats {
    param([double[]]$Values)

    $sorted = @($Values | Sort-Object)
    $count = $sorted.Count
    $median = if ($count % 2 -eq 1) {
        $sorted[[int][Math]::Floor($count / 2)]
    } else {
        ($sorted[$count / 2 - 1] + $sorted[$count / 2]) / 2.0
    }
    $sum = 0.0
    foreach ($v in $Values) {
        $sum += $v
    }
    [ordered]@{
        min_ms = [Math]::Round(($sorted | Select-Object -First 1), 3)
        median_ms = [Math]::Round($median, 3)
        mean_ms = [Math]::Round($sum / $Values.Count, 3)
        max_ms = [Math]::Round(($sorted | Select-Object -Last 1), 3)
    }
}

$moonVersionOutput = (& moon version 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
$gitRev = (& git rev-parse --short HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRev)) {
    $gitRev = "uncommitted"
}
$gitStatusShort = (& git status --short 2>$null | ForEach-Object { [string]$_ })
$machine = [ordered]@{
    computer_name = $env:COMPUTERNAME
    os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    processor_count = [Environment]::ProcessorCount
    pwsh = $PSVersionTable.PSVersion.ToString()
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($bench in $benchmarks) {
    Write-Host "=== BENCH $($bench.algorithm): warmup=$Warmup iterations=$Iterations target=$Target release=$release ==="
    for ($i = 0; $i -lt $Warmup; $i += 1) {
        $warm = Invoke-BenchCommand -Package $bench.package
        if ($warm.exit_code -ne 0) {
            throw "Warmup failed for $($bench.algorithm): exit $($warm.exit_code)`n$($warm.output -join "`n")"
        }
    }

    $runs = New-Object System.Collections.Generic.List[object]
    $times = New-Object System.Collections.Generic.List[double]
    for ($i = 0; $i -lt $Iterations; $i += 1) {
        $run = Invoke-BenchCommand -Package $bench.package
        $runs.Add($run)
        $times.Add([double]$run.elapsed_ms)
        if ($run.exit_code -ne 0) {
            throw "Benchmark failed for $($bench.algorithm): exit $($run.exit_code)`n$($run.output -join "`n")"
        }
        Write-Host ("{0} iter {1}/{2}: {3} ms" -f $bench.algorithm, ($i + 1), $Iterations, $run.elapsed_ms)
    }

    $stats = Get-Stats -Values $times.ToArray()
    $results.Add([ordered]@{
        algorithm = $bench.algorithm
        package = $bench.package
        file = $bench.file
        scenario = $bench.scenario
        input = $bench.input
        baseline = $bench.baseline
        stats = $stats
        runs = $runs.ToArray()
    })
}

$artifact = [ordered]@{
    schema = "moonbit-pathfinding.benchmark-smoke.v1"
    generated_at = $generatedAt
    generated_by = "scripts/benchmark_smoke.ps1"
    moon_version = $moonVersionOutput
    git_revision = $gitRev.Trim()
    git_status_short = $gitStatusShort
    target = $Target
    release = $release
    warmup = $Warmup
    iterations = $Iterations
    measurement_scope = "End-to-end moon test package execution timing. Includes harness startup/compilation cache effects; use as reproducible smoke evidence, not microbenchmark-only algorithm time."
    machine = $machine
    benchmarks = $results.ToArray()
}

$jsonPath = Join-Path $outRoot ("smoke-$Target-$timestamp.json")
$latestJsonPath = Join-Path $outRoot "latest-smoke.json"
$json = $artifact | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText($jsonPath, $json + "`n", [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($latestJsonPath, $json + "`n", [Text.Encoding]::UTF8)

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Benchmark Smoke Results")
$md.Add("")
$md.Add("- Generated at: ``$generatedAt``")
$md.Add('- Script: `scripts/benchmark_smoke.ps1`')
$md.Add("- MoonBit: ``$($moonVersionOutput -replace "`r?`n", " ")``")
$md.Add("- Target: ``$Target``")
$md.Add("- Release: ``$release``")
$md.Add("- Warmup: ``$Warmup``")
$md.Add("- Iterations: ``$Iterations``")
$md.Add("- Machine: ``$($machine.os)``, ``$($machine.architecture)``, ``$($machine.processor_count)`` logical processors")
$md.Add("- Git revision: ``$($gitRev.Trim())``")
$md.Add("")
$md.Add('> Scope: end-to-end `moon test -p ...` package timing. These results are reproducible smoke evidence, not a cross-language speedup claim.')
$md.Add("")
$md.Add("| Algorithm | Scenario | Min ms | Median ms | Mean ms | Max ms |")
$md.Add("|---|---|---:|---:|---:|---:|")
foreach ($r in $results) {
    $md.Add("| $($r.algorithm) | $($r.scenario) | $($r.stats.min_ms) | $($r.stats.median_ms) | $($r.stats.mean_ms) | $($r.stats.max_ms) |")
}
$md.Add("")
$md.Add("Raw JSON: ``$(Split-Path -Leaf $jsonPath)`` and ``latest-smoke.json``.")

$mdPath = Join-Path $outRoot "latest-smoke.md"
[IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", [Text.Encoding]::UTF8)

Write-Host "=== BENCHMARK ARTIFACTS ==="
Write-Host $jsonPath
Write-Host $latestJsonPath
Write-Host $mdPath
