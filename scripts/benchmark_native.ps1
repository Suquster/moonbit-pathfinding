param(
    [string]$Target = "wasm-gc",
    [int]$Repeats = 10,
    [int]$Warmup = 3,
    [switch]$NoRelease,
    [string]$OutDir = "benches\results",
    # 前沿算法（CH/JPS/ALT）采集相关：
    [switch]$SkipAdvanced,
    [int]$AdvancedTimeoutSec = 240,
    [string]$AdvancedTarget = "native"
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

# Requirement 5.3：测量前 ≥3 次预热、≥10 次采样。低于下限时抬升到下限并告警，
# 保证脚本始终满足可复现基准的最小统计强度。
$MinWarmup = 3
$MinRepeats = 10
if ($Warmup -lt $MinWarmup) {
    Write-Warning "Warmup=$Warmup 低于 R5.3 下限 $MinWarmup，已抬升为 $MinWarmup。"
    $Warmup = $MinWarmup
}
if ($Repeats -lt $MinRepeats) {
    Write-Warning "Repeats=$Repeats 低于 R5.3 下限 $MinRepeats，已抬升为 $MinRepeats。"
    $Repeats = $MinRepeats
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
    },
    [ordered]@{
        algorithm = "Regex"
        package = "Suquster/moonbit-pathfinding/benches/regex_bench"
        file = "benches/regex_bench/regex_bench.mbt"
        scenario = "NFA / DFA / Pike VM on a?{n}a{n} pathological input plus demo real workloads"
    },
    [ordered]@{
        algorithm = "MiniCompiler"
        package = "Suquster/moonbit-pathfinding/benches/mini_compiler_bench"
        file = "benches/mini_compiler_bench/mini_compiler_bench.mbt"
        scenario = "MiniML lex/parse/infer/eval/compile+VM over increasing arith-chain (16/64/256), let-nest & app-depth (8/16/32) programs"
    },
    [ordered]@{
        algorithm = "LSP"
        package = "Suquster/moonbit-pathfinding/benches/lsp_bench"
        file = "benches/lsp_bench/lsp_bench.mbt"
        scenario = "LSP_Suite five workloads: decode/encode round-trip (8/64/512), dispatch routing (16/128/1024), analyze, apply_changes & references/rename over DSL docs (16/64/256)"
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

# ─────────────── 前沿算法（CH/JPS/ALT）基准采集（R5.1–5.4 / R8.4 / R8.5 / R8.7+R5.6） ───────────────
#
# CH/JPS/ALT 与基准 Dijkstra 的原始查询计时由 MoonBit 采集器
# `benches/advanced_bench` 经 `@infra_bench.compute_stats` 汇总统计量并输出
# `moonbit-pathfinding.benchmark.v1` JSON（含图规模/边数/查询数/样本量/原始计时/
# 统计量）；CH/JPS/ALT 的预处理耗时、数据集标识、相对 Dijkstra 的中位加速比与
# 「平均耗时不更高」判定作为附加证据一并输出。本节负责：运行采集器（带超时）、
# 抽取两段 JSON、注入真实环境元信息、写出 MD+JSON 双产物，并按数据集可用性施加
# R8.5 断言（真实 OSM 数据失败即门禁失败；合成图降级为记录性判定）。

function Get-JsonBetweenMarkers {
    param([string[]]$Lines, [string]$BeginMarker, [string]$EndMarker)
    $capture = $false
    $sb = New-Object System.Text.StringBuilder
    foreach ($line in $Lines) {
        $clean = [regex]::Replace([string]$line, "`e\[[0-?]*[ -/]*[@-~]", "")
        $trimmed = $clean.Trim()
        if ($trimmed -eq $BeginMarker) { $capture = $true; continue }
        if ($trimmed -eq $EndMarker) { $capture = $false; continue }
        if ($capture) { [void]$sb.AppendLine($clean) }
    }
    $sb.ToString().Trim()
}

# OSM 数据集探测（R8.7/R5.6）：benches/osm 下除 download.sh 外是否存在真实数据集。
$osmDir = Join-Path $root "benches/osm"
$osmFiles = @()
if (Test-Path $osmDir) {
    $osmFiles = @(Get-ChildItem -LiteralPath $osmDir -File | Where-Object { $_.Name -ne "download.sh" })
}
$osmAvailable = $osmFiles.Count -gt 0
if (-not $osmAvailable) {
    Write-Warning "OSM_Roadmap_Dataset 不可用（benches/osm 下无数据集文件）：以合成加权网格采集 CH/JPS/ALT 基准并记录数据缺失诊断，继续其余基准而不使套件失败（R8.7/R5.6）。"
}

$advReportJson = $null
$advEvidenceJson = $null
$advJsonPath = $null
$advMdPath = $null

if ($SkipAdvanced.IsPresent) {
    Write-Host "=== ADVANCED (CH/JPS/ALT) COLLECTION SKIPPED (-SkipAdvanced) ==="
} else {
    Write-Host "=== ADVANCED (CH/JPS/ALT) BENCHMARK: target=$AdvancedTarget release=$release timeout=${AdvancedTimeoutSec}s ==="
    $advPkg = "Suquster/moonbit-pathfinding/benches/advanced_bench"
    $advArgs = @("bench", "-p", $advPkg, "--target", $AdvancedTarget)
    if ($release) { $advArgs += "--release" }
    $advOutFile = Join-Path $outRoot "advanced-raw-stdout.log"
    $advErrFile = "$advOutFile.err"
    $advOk = $false
    $advDiagnostic = ""
    try {
        $proc = Start-Process -FilePath "moon" -ArgumentList $advArgs -NoNewWindow -PassThru -RedirectStandardOutput $advOutFile -RedirectStandardError $advErrFile
        $completed = $proc.WaitForExit($AdvancedTimeoutSec * 1000)
        if (-not $completed) {
            try { $proc.Kill() } catch { }
            $advDiagnostic = "前沿算法采集超时（>${AdvancedTimeoutSec}s）：已终止并降级，跳过 CH/JPS/ALT 基准而不使整个套件失败（R5.6）。"
            Write-Warning $advDiagnostic
        } elseif ($proc.ExitCode -ne 0) {
            $advDiagnostic = "前沿算法采集失败（moon bench 退出码 $($proc.ExitCode)）：降级跳过 CH/JPS/ALT 基准（R5.6）。"
            Write-Warning $advDiagnostic
        } else {
            $advOk = $true
        }
    } catch {
        $advDiagnostic = "前沿算法采集无法启动（$($_.Exception.Message)）：降级跳过 CH/JPS/ALT 基准（R5.6）。"
        Write-Warning $advDiagnostic
    }

    if ($advOk) {
        $advLines = @()
        if (Test-Path $advOutFile) { $advLines = @(Get-Content -LiteralPath $advOutFile) }
        $advReportJson = Get-JsonBetweenMarkers -Lines $advLines -BeginMarker "===ADV_BENCH_REPORT_BEGIN===" -EndMarker "===ADV_BENCH_REPORT_END==="
        $advEvidenceJson = Get-JsonBetweenMarkers -Lines $advLines -BeginMarker "===ADV_BENCH_EVIDENCE_BEGIN===" -EndMarker "===ADV_BENCH_EVIDENCE_END==="
        if ([string]::IsNullOrWhiteSpace($advReportJson) -or [string]::IsNullOrWhiteSpace($advEvidenceJson)) {
            $advDiagnostic = "前沿算法采集输出缺少 JSON 标记段：降级跳过 CH/JPS/ALT 基准（R5.6）。"
            Write-Warning $advDiagnostic
            $advOk = $false
        }
    }

    if ($advOk) {
        # 注入真实环境元信息（采集器写出占位符，避免在 MoonBit 侧获取环境）。
        $moonVersionOneLine = ($moonVersionOutput -replace "`r?`n", " ").Trim()
        $cpuDescriptor = "$($machine.architecture) x$($machine.processor_count)"
        $advReportJson = $advReportJson.Replace("__MOON_VERSION__", $moonVersionOneLine)
        $advReportJson = $advReportJson.Replace("__BACKEND__", $AdvancedTarget)
        $advReportJson = $advReportJson.Replace("__OS__", [string]$machine.os)
        $advReportJson = $advReportJson.Replace("__CPU__", $cpuDescriptor)

        $reportObj = $advReportJson | ConvertFrom-Json
        $evidenceObj = $advEvidenceJson | ConvertFrom-Json

        $advArtifact = [ordered]@{
            schema = "moonbit-pathfinding.benchmark.v1"
            generated_at = $generatedAt
            generated_by = "scripts/benchmark_native.ps1 (advanced CH/JPS/ALT)"
            moon_version = $moonVersionOneLine
            target = $AdvancedTarget
            release = $release
            warmup = $Warmup
            repeats = $Repeats
            osm_available = $osmAvailable
            dataset_diagnostic = if ($osmAvailable) { "" } else { "OSM_Roadmap_Dataset unavailable; synthetic weighted 4-grid used for reproducible timing evidence (R8.7)." }
            machine = $machine
            report = $reportObj
            evidence = $evidenceObj
        }
        $advJson = $advArtifact | ConvertTo-Json -Depth 20
        $advJsonPath = Join-Path $outRoot ("advanced-$AdvancedTarget-$timestamp.json")
        $latestAdvJsonPath = Join-Path $outRoot "latest-advanced.json"
        [IO.File]::WriteAllText($advJsonPath, $advJson + "`n", [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($latestAdvJsonPath, $advJson + "`n", [Text.Encoding]::UTF8)

        # Markdown 渲染（R5.1 双产物）。
        $amd = New-Object System.Collections.Generic.List[string]
        $amd.Add("# Advanced (CH / JPS / ALT) Benchmark Results")
        $amd.Add("")
        $amd.Add("- Generated at: ``$generatedAt``")
        $amd.Add('- Script: `scripts/benchmark_native.ps1` (advanced section)')
        $amd.Add('- Collector: `benches/advanced_bench` via `@infra_bench.compute_stats`')
        $amd.Add("- MoonBit: ``$moonVersionOneLine``")
        $amd.Add("- Target: ``$AdvancedTarget``, Release: ``$release``")
        $amd.Add("- Warmup: ``$($evidenceObj.warmup_count)``, Samples: ``$($evidenceObj.sample_count)``, Queries/sample: ``$($evidenceObj.query_count)``")
        $amd.Add("- Dataset: ``$($evidenceObj.dataset_id)`` (OSM available: ``$osmAvailable``)")
        if (-not $osmAvailable) {
            $amd.Add('- Diagnostic: OSM dataset unavailable; synthetic weighted 4-grid used (R8.7 degradation).')
        }
        $amd.Add("- Graph size: ``$($evidenceObj.graph_size)`` nodes, ``$($evidenceObj.edge_count)`` directed edges")
        $amd.Add("")
        $amd.Add("## Preprocessing time (time units, monotonic clock)")
        $amd.Add("")
        $amd.Add("| Algorithm | Preprocess |")
        $amd.Add("|---|---:|")
        $amd.Add("| CH | $($evidenceObj.ch_preprocess_ns) |")
        $amd.Add("| ALT | $($evidenceObj.alt_preprocess_ns) |")
        $amd.Add("| JPS (grid build) | $($evidenceObj.jps_preprocess_ns) |")
        $amd.Add("")
        $amd.Add("## Query timing per sample (one sample = $($evidenceObj.query_count) queries)")
        $amd.Add("")
        $amd.Add("| Algorithm | Median | Mean | Median speedup vs Dijkstra | Mean not higher than Dijkstra |")
        $amd.Add("|---|---:|---:|---:|:--:|")
        $amd.Add("| Dijkstra | $($evidenceObj.dijkstra_median_ns) | $($evidenceObj.dijkstra_mean_ns) | - | - |")
        $amd.Add("| CH | $($evidenceObj.ch_median_ns) | $($evidenceObj.ch_mean_ns) | $($evidenceObj.ch_speedup_median) | $($evidenceObj.ch_mean_not_higher) |")
        $amd.Add("| ALT | $($evidenceObj.alt_median_ns) | $($evidenceObj.alt_mean_ns) | $($evidenceObj.alt_speedup_median) | $($evidenceObj.alt_mean_not_higher) |")
        $amd.Add("| JPS | $($evidenceObj.jps_median_ns) | $($evidenceObj.jps_mean_ns) | - | - |")
        $amd.Add("")
        $amd.Add('> Statistics (min/max/median/mean/p95/stddev) computed by `@infra_bench.compute_stats`. Raw timings and per-case stats are in the JSON artifact.')
        if (-not $osmAvailable) {
            $amd.Add('> R8.5 speedup assertion is informational on synthetic data; it is enforced as a gate only against the real OSM dataset.')
        }
        $advMdPath = Join-Path $outRoot "latest-advanced.md"
        [IO.File]::WriteAllText($advMdPath, ($amd -join "`n") + "`n", [Text.Encoding]::UTF8)

        # R8.5：CH/ALT 平均查询耗时不高于 Dijkstra 的断言。
        $verdictFail = $false
        if (-not $evidenceObj.ch_mean_not_higher) {
            $m = "CH 平均查询耗时高于基准 Dijkstra（ch_mean=$($evidenceObj.ch_mean_ns), dijkstra_mean=$($evidenceObj.dijkstra_mean_ns)）。"
            if ($osmAvailable) { Write-Warning "$m R8.5 门禁失败。"; $verdictFail = $true }
            else { Write-Warning "$m 合成图记录性判定，不作为门禁（R8.7）。" }
        }
        if (-not $evidenceObj.alt_mean_not_higher) {
            $m = "ALT 平均查询耗时高于基准 Dijkstra（alt_mean=$($evidenceObj.alt_mean_ns), dijkstra_mean=$($evidenceObj.dijkstra_mean_ns)）。"
            if ($osmAvailable) { Write-Warning "$m R8.5 门禁失败。"; $verdictFail = $true }
            else { Write-Warning "$m 合成图记录性判定，不作为门禁（R8.7）。" }
        }
        if ($verdictFail) {
            throw "R8.5 断言失败：CH/ALT 在真实 OSM 数据上的平均查询耗时高于 Dijkstra。"
        }
    }
}

Write-Host "=== NATIVE BENCHMARK ARTIFACTS ==="
Write-Host $jsonPath
Write-Host $latestJsonPath
Write-Host $mdPath
if ($advJsonPath) {
    Write-Host "=== ADVANCED (CH/JPS/ALT) ARTIFACTS ==="
    Write-Host $advJsonPath
    Write-Host (Join-Path $outRoot "latest-advanced.json")
    Write-Host $advMdPath
}
