param(
    [string]$Target = "wasm-gc",
    [int]$Repeats = 3,
    [int]$Warmup = 1,
    [switch]$NoRelease,
    [string]$OutDir = "benches\results"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if ($Repeats -le 0) {
    throw "Repeats must be positive."
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
        package = "Suquster/moonbit-pathfinding/benches/bfs_bench"
        file = "benches/bfs_bench/bfs_bench.mbt"
        scenario = "1k-node sparse directed graph, density 1%, query 0 -> 999"
    },
    [ordered]@{
        algorithm = "Dijkstra"
        package = "Suquster/moonbit-pathfinding/benches/dijkstra_bench"
        file = "benches/dijkstra_bench/dijkstra_bench.mbt"
        scenario = "1k-node sparse weighted directed graph, density 1%, query 0 -> 999"
    },
    [ordered]@{
        algorithm = "A*"
        package = "Suquster/moonbit-pathfinding/benches/astar_bench"
        file = "benches/astar_bench/astar_bench.mbt"
        scenario = "32x32 open 4-neighbour grid with Manhattan heuristic"
    },
    [ordered]@{
        algorithm = "Kruskal MST"
        package = "Suquster/moonbit-pathfinding/benches/kruskal_bench"
        file = "benches/kruskal_bench/kruskal_bench.mbt"
        scenario = "1k-node 10k-edge weighted undirected multigraph"
    }
)

function Convert-DurationToMicroseconds {
    param(
        [double]$Value,
        [string]$Unit
    )

    switch ($Unit) {
        "ns" { return $Value / 1000.0 }
        "us" { return $Value }
        "µs" { return $Value }
        "μs" { return $Value }
        "ms" { return $Value * 1000.0 }
        "s" { return $Value * 1000000.0 }
        default { throw "Unsupported benchmark duration unit: $Unit" }
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
        min_us = [Math]::Round(($sorted | Select-Object -First 1), 3)
        median_us = [Math]::Round($median, 3)
        mean_us = [Math]::Round($sum / $Values.Count, 3)
        max_us = [Math]::Round(($sorted | Select-Object -Last 1), 3)
    }
}

function Parse-BenchOutput {
    param([string[]]$Output)

    $entries = New-Object System.Collections.Generic.List[object]
    $pattern = '^\s*(?<name>\S+)\s+(?<mean>[0-9]+(?:\.[0-9]+)?)\s+(?<mean_unit>\S+)\s+±\s+(?<sigma>[0-9]+(?:\.[0-9]+)?)\s+(?<sigma_unit>\S+)\s+(?<min>[0-9]+(?:\.[0-9]+)?)\s+(?<min_unit>\S+)\s+.*\s+(?<max>[0-9]+(?:\.[0-9]+)?)\s+(?<max_unit>\S+)\s+in\s+(?<outer>[0-9]+)\s+.\s+(?<inner>[0-9]+)\s+runs'
    foreach ($line in $Output) {
        $clean = [regex]::Replace($line, "`e\[[0-?]*[ -/]*[@-~]", "")
        $m = [regex]::Match($clean, $pattern)
        if (-not $m.Success) {
            continue
        }
        $mean = [double]$m.Groups["mean"].Value
        $sigma = [double]$m.Groups["sigma"].Value
        $min = [double]$m.Groups["min"].Value
        $max = [double]$m.Groups["max"].Value
        $entries.Add([pscustomobject][ordered]@{
            name = $m.Groups["name"].Value
            mean_us = [Math]::Round((Convert-DurationToMicroseconds -Value $mean -Unit $m.Groups["mean_unit"].Value), 3)
            sigma_us = [Math]::Round((Convert-DurationToMicroseconds -Value $sigma -Unit $m.Groups["sigma_unit"].Value), 3)
            min_us = [Math]::Round((Convert-DurationToMicroseconds -Value $min -Unit $m.Groups["min_unit"].Value), 3)
            max_us = [Math]::Round((Convert-DurationToMicroseconds -Value $max -Unit $m.Groups["max_unit"].Value), 3)
            outer_count = [int]$m.Groups["outer"].Value
            inner_runs = [int]$m.Groups["inner"].Value
        })
    }

    if ($entries.Count -eq 0) {
        throw "No native benchmark rows could be parsed from moon bench output."
    }
    $entries.ToArray()
}

function Invoke-NativeBenchCommand {
    param([string]$Package)

    $moonArgs = @("bench", "-p", $Package, "--target", $Target, "--no-parallelize")
    if ($release) {
        $moonArgs += "--release"
    }

    $output = New-Object System.Collections.Generic.List[string]
    & moon @moonArgs 2>&1 | ForEach-Object {
        $line = [string]$_
        $output.Add($line)
        Write-Host $line
    }
    $code = $LASTEXITCODE

    [ordered]@{
        command = @("moon") + $moonArgs
        exit_code = $code
        output = $output.ToArray()
        parsed = if ($code -eq 0) { @(Parse-BenchOutput -Output $output.ToArray()) } else { @() }
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
    Write-Host "=== NATIVE BENCH $($bench.algorithm): warmup=$Warmup repeats=$Repeats target=$Target release=$release ==="
    for ($i = 0; $i -lt $Warmup; $i += 1) {
        $warm = Invoke-NativeBenchCommand -Package $bench.package
        if ($warm.exit_code -ne 0) {
            throw "Warmup failed for $($bench.algorithm): exit $($warm.exit_code)"
        }
    }

    $runs = New-Object System.Collections.Generic.List[object]
    $means = New-Object System.Collections.Generic.List[double]
    for ($i = 0; $i -lt $Repeats; $i += 1) {
        $run = Invoke-NativeBenchCommand -Package $bench.package
        $runs.Add($run)
        if ($run.exit_code -ne 0) {
            throw "Native benchmark failed for $($bench.algorithm): exit $($run.exit_code)"
        }
        $row = @($run.parsed)[0]
        $means.Add([double]$row.mean_us)
        Write-Host ("{0} repeat {1}/{2}: {3} us mean" -f $bench.algorithm, ($i + 1), $Repeats, $row.mean_us)
    }

    $results.Add([ordered]@{
        algorithm = $bench.algorithm
        package = $bench.package
        file = $bench.file
        scenario = $bench.scenario
        summary = Get-Stats -Values $means.ToArray()
        runs = $runs.ToArray()
    })
}

$artifact = [ordered]@{
    schema = "moonbit-pathfinding.benchmark-native.v1"
    generated_at = $generatedAt
    generated_by = "scripts/benchmark_native.ps1"
    moon_version = $moonVersionOutput
    git_revision = $gitRev.Trim()
    git_status_short = $gitStatusShort
    target = $Target
    release = $release
    warmup = $Warmup
    repeats = $Repeats
    measurement_scope = "Native moon bench statistics parsed from @bench.T blocks. Summary medians aggregate moon bench-reported mean time across repeated invocations."
    machine = $machine
    benchmarks = $results.ToArray()
}

$jsonPath = Join-Path $outRoot ("native-$Target-$timestamp.json")
$latestJsonPath = Join-Path $outRoot "latest-native.json"
$json = $artifact | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText($jsonPath, $json + "`n", [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($latestJsonPath, $json + "`n", [Text.Encoding]::UTF8)

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Native Benchmark Results")
$md.Add("")
$md.Add("- Generated at: ``$generatedAt``")
$md.Add('- Script: `scripts/benchmark_native.ps1`')
$md.Add("- MoonBit: ``$($moonVersionOutput -replace "`r?`n", " ")``")
$md.Add("- Target: ``$Target``")
$md.Add("- Release: ``$release``")
$md.Add("- Warmup: ``$Warmup``")
$md.Add("- Repeats: ``$Repeats``")
$md.Add("- Machine: ``$($machine.os)``, ``$($machine.architecture)``, ``$($machine.processor_count)`` logical processors")
$md.Add("- Git revision: ``$($gitRev.Trim())``")
$md.Add("")
$md.Add('> Scope: native `moon bench` statistics from `@bench.T` blocks. This is algorithm-level regression evidence, not a cross-language speedup claim.')
$md.Add("")
$md.Add("| Algorithm | Scenario | Median mean us | Mean us | Min us | Max us |")
$md.Add("|---|---|---:|---:|---:|---:|")
foreach ($r in $results) {
    $md.Add("| $($r.algorithm) | $($r.scenario) | $($r.summary.median_us) | $($r.summary.mean_us) | $($r.summary.min_us) | $($r.summary.max_us) |")
}
$md.Add("")
$md.Add("Raw JSON: ``$(Split-Path -Leaf $jsonPath)`` and ``latest-native.json``.")

$mdPath = Join-Path $outRoot "latest-native.md"
[IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", [Text.Encoding]::UTF8)

Write-Host "=== NATIVE BENCHMARK ARTIFACTS ==="
Write-Host $jsonPath
Write-Host $latestJsonPath
Write-Host $mdPath
