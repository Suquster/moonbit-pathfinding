<#
.SYNOPSIS
    Rust `pathfinding` crate 对比报告编排器（Requirement 6）。

.DESCRIPTION
    本脚本编排「本库（MoonBit）侧」与「Rust 侧」在统一工作负载矩阵上的对比采集，
    并产出可复现的对比报告（Markdown + JSON 双产物）。两侧采集器：

      * 本库侧：`bench_rust/moon_side`（MoonBit 主包，调用既有 @unweighted/@directed）。
      * Rust 侧：`bench_rust/`（Cargo 工程，依赖 `pathfinding` crate）。

    两侧用 **相同 64 位种子 + 完全相同的确定性生成算法**（逐位一致的 xorshift64）
    产出 **逐元素相同** 的图与查询集（R6.2），并以「黄金 JSON 图样本」交叉校验
    （不一致即门禁失败）。工作负载矩阵：BFS/Dijkstra/A* × 规模 {1000,10000,100000}
    × 平均出度 {4,16} × 每组 ≥100 查询（R6.1）。采样 ≥5 预热 + ≥30 计时（R6.3）。

    加速比统一以 **中位计时口径** 计算与呈现（R6.6）。失败 / 超时（单次采样 >60s）/
    两库结果不一致的用例被标注并 **排除出加速比**（R6.7）。报告记录 CPU/OS 与两套
    工具链版本及完整方法学声明（R6.3/R6.4）；跨机器 / 跨工具链差异显式标注且不据此
    声明加速比（R6.8）。

    缺少 cargo 或 moon 工具链时给出明确告警并优雅降级（仍产出可用的部分报告 / 黄金
    校验），不静默崩溃。

.NOTES
    可复现性（R6.5）：以相同参数重跑，本库侧中位计时与报告值相对差异应 ≤15%。
#>
param(
    # 工作负载矩阵（R6.1）。
    [string]$Sizes = "1000,10000,100000",
    [string]$Degrees = "4,16",
    [int]$Queries = 100,
    # 采样强度（R6.3：≥5 预热、≥30 采样）。
    [int]$Warmup = 5,
    [int]$Samples = 30,
    # 64 位种子（十进制；默认 0x123456789ABCDEF0）。两侧共享以保证等价输入（R6.2）。
    [string]$Seed = "1311768467463790320",
    # 单次采样超时上界（秒），超过即标注并排除（R6.7）。
    [int]$TimeoutSec = 60,
    # 黄金交叉校验所用规模（保持 JSON 体量可控；默认仅最小规模）。
    [string]$GoldenSizes = "1000",
    # 产物目录。
    [string]$OutDir = "benches\results",
    [string]$MoonTarget = "native",
    # 快速验证模式：缩小矩阵与采样，便于本地 / CI 烟雾验证（不改变方法学）。
    [switch]$Quick,
    # 跨机器 / 跨工具链标注（R6.8）：两侧机器标识不同则显式标注且不声明加速比。
    [string]$RustMachineId = "",
    [string]$MoonMachineId = "",
    # 调试 / 降级开关。
    [switch]$SkipRust,
    [switch]$SkipMoon
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ─────────────────────────── 下限与快速模式 ───────────────────────────
# R6.3 硬下限：预热 ≥5、采样 ≥30。低于下限抬升并告警。
$MinWarmup = 5
$MinSamples = 30
if ($Quick.IsPresent) {
    Write-Warning "Quick 模式：缩小工作负载矩阵与采样以便快速验证（方法学不变；非正式对比证据）。"
    if (-not $PSBoundParameters.ContainsKey('Sizes')) { $Sizes = "1000" }
    if (-not $PSBoundParameters.ContainsKey('Degrees')) { $Degrees = "4" }
    if (-not $PSBoundParameters.ContainsKey('Queries')) { $Queries = 20 }
}
if ($Warmup -lt $MinWarmup) {
    Write-Warning "Warmup=$Warmup 低于 R6.3 下限 $MinWarmup，已抬升为 $MinWarmup。"
    $Warmup = $MinWarmup
}
if ($Samples -lt $MinSamples) {
    Write-Warning "Samples=$Samples 低于 R6.3 下限 $MinSamples，已抬升为 $MinSamples。"
    $Samples = $MinSamples
}
if ($Queries -lt 100 -and -not $Quick.IsPresent) {
    Write-Warning "Queries=$Queries 低于 R6.1 下限 100，已抬升为 100。"
    $Queries = 100
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
$benchRustDir = Join-Path $root "bench_rust"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToString("o")

# ─────────────────────────── 工具链探测（R6 优雅降级） ───────────────────────────
function Test-Tool {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

$hasCargo = Test-Tool "cargo"
$hasMoon = Test-Tool "moon"
$hasRustc = Test-Tool "rustc"

$degradations = New-Object System.Collections.Generic.List[string]
$runRust = (-not $SkipRust.IsPresent) -and $hasCargo
$runMoon = (-not $SkipMoon.IsPresent) -and $hasMoon

if ($SkipRust.IsPresent) { $degradations.Add("Rust 侧采集被显式跳过（-SkipRust）。") }
elseif (-not $hasCargo) { $degradations.Add("未检测到 cargo 工具链：跳过 Rust 侧采集，仅产出本库侧数据与方法学声明（优雅降级）。") }

if ($SkipMoon.IsPresent) { $degradations.Add("本库（MoonBit）侧采集被显式跳过（-SkipMoon）。") }
elseif (-not $hasMoon) { $degradations.Add("未检测到 moon 工具链：跳过本库侧采集（优雅降级）。") }

foreach ($d in $degradations) { Write-Warning $d }

# ─────────────────────────── 工具链版本（R6.3/R6.4） ───────────────────────────
function Get-CmdVersion {
    param([string]$Exe, [string[]]$VersionArgs)
    if (-not (Test-Tool $Exe)) { return "unavailable" }
    try {
        $out = (& $Exe @VersionArgs 2>&1 | ForEach-Object { [string]$_ }) -join " "
        return $out.Trim()
    } catch {
        return "unavailable"
    }
}

$moonVersion = Get-CmdVersion -Exe "moon" -VersionArgs @("version")
$rustcVersion = Get-CmdVersion -Exe "rustc" -VersionArgs @("--version")
$cargoVersion = Get-CmdVersion -Exe "cargo" -VersionArgs @("--version")

$machine = [ordered]@{
    computer_name   = $env:COMPUTERNAME
    os              = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    architecture    = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    processor_count = [Environment]::ProcessorCount
    cpu             = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) x$([Environment]::ProcessorCount)"
    pwsh            = $PSVersionTable.PSVersion.ToString()
}

# 跨机器 / 跨工具链判定（R6.8）。
$crossMachine = (-not [string]::IsNullOrWhiteSpace($RustMachineId)) -and `
    (-not [string]::IsNullOrWhiteSpace($MoonMachineId)) -and `
    ($RustMachineId -ne $MoonMachineId)
if ($crossMachine) {
    Write-Warning "检测到跨机器 / 跨工具链对比（Rust='$RustMachineId' vs Moon='$MoonMachineId'）：将显式标注且不据此声明加速比（R6.8）。"
}

# ─────────────────────────── 标记段抽取（与既有脚本一致） ───────────────────────────
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

# ─────────────────────────── 构建 Rust 工程 ───────────────────────────
$rustBin = $null
if ($runRust) {
    Write-Host "=== BUILD bench_rust (cargo build --release) ==="
    Push-Location $benchRustDir
    try {
        & cargo build --release 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            $runRust = $false
            $degradations.Add("cargo build --release 失败（退出码 $LASTEXITCODE）：跳过 Rust 侧采集（优雅降级）。")
            Write-Warning $degradations[-1]
        }
    } finally {
        Pop-Location
    }
    if ($runRust) {
        $candidate = Join-Path $benchRustDir "target/release/bench_rust"
        if (Test-Path "$candidate.exe") { $rustBin = "$candidate.exe" }
        elseif (Test-Path $candidate) { $rustBin = $candidate }
        else {
            $runRust = $false
            $degradations.Add("未找到 Rust 产物二进制：跳过 Rust 侧采集（优雅降级）。")
            Write-Warning $degradations[-1]
        }
    }
}

# ─────────────────────────── 采集函数 ───────────────────────────
function Invoke-RustHarness {
    param([string[]]$HarnessArgs, [string]$OutFile)
    $allArgs = $HarnessArgs + @("--out", $OutFile)
    & $rustBin @allArgs 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "Rust harness failed (exit $LASTEXITCODE): $($HarnessArgs -join ' ')" }
    return (Get-Content -LiteralPath $OutFile -Raw)
}

function Invoke-MoonHarness {
    param([string[]]$HarnessArgs, [string]$BeginMarker, [string]$EndMarker)
    $moonArgs = @("run", "bench_rust/moon_side", "--target", $MoonTarget, "--release", "--") + $HarnessArgs
    $errTmp = [System.IO.Path]::GetTempFileName()
    Push-Location $root
    try {
        # 仅捕获 stdout 做标记段抽取；stderr（编译告警等）单独导出，避免与产物 JSON 交错。
        $stdout = & moon @moonArgs 2>$errTmp
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if (Test-Path $errTmp) {
        # 过滤 moon 的逐行 INFO 追踪噪声（环境相关），仅保留告警/错误等有用诊断。
        Get-Content -LiteralPath $errTmp | Where-Object {
            $_ -notmatch '^\d{4}-\d\d-\d\dT.*\bINFO\b'
        } | ForEach-Object { Write-Host $_ }
        Remove-Item -LiteralPath $errTmp -ErrorAction SilentlyContinue
    }
    if ($code -ne 0) { throw "Moon harness failed (exit $code): $($HarnessArgs -join ' ')" }
    $lines = @($stdout | ForEach-Object { [string]$_ })
    $json = Get-JsonBetweenMarkers -Lines $lines -BeginMarker $BeginMarker -EndMarker $EndMarker
    if ([string]::IsNullOrWhiteSpace($json)) { throw "Moon harness produced no JSON between markers $BeginMarker..$EndMarker" }
    return $json
}

# ─────────────────────────── 黄金交叉校验（R6.2） ───────────────────────────
$goldenVerdict = [ordered]@{
    performed = $false
    matched   = $null
    detail    = ""
}

if ($runRust -and $runMoon) {
    Write-Host "=== GOLDEN CROSS-CHECK (element-wise graph/query identity, R6.2) ==="
    $commonGoldenArgs = @(
        "--mode", "golden",
        "--seed", $Seed,
        "--queries", "$Queries",
        "--golden-sizes", $GoldenSizes,
        "--degrees", $Degrees
    )
    $rustGoldenFile = Join-Path $outRoot "rust-golden-$timestamp.json"
    $rustGoldenRaw = Invoke-RustHarness -HarnessArgs $commonGoldenArgs -OutFile $rustGoldenFile
    $moonGoldenRaw = Invoke-MoonHarness -HarnessArgs $commonGoldenArgs -BeginMarker "===MOONSIDE_GOLDEN_BEGIN===" -EndMarker "===MOONSIDE_GOLDEN_END==="

    $rustGolden = $rustGoldenRaw | ConvertFrom-Json
    $moonGolden = $moonGoldenRaw | ConvertFrom-Json

    # 逐元素比较：以紧凑规范化 JSON 串比较 configs 数组。
    $rustConfigsJson = ($rustGolden.configs | ConvertTo-Json -Depth 12 -Compress)
    $moonConfigsJson = ($moonGolden.configs | ConvertTo-Json -Depth 12 -Compress)

    $goldenVerdict.performed = $true
    if ($rustConfigsJson -eq $moonConfigsJson) {
        $goldenVerdict.matched = $true
        $goldenVerdict.detail = "两侧黄金图样本逐元素一致（configs 规范化 JSON 相等）。"
        Write-Host "[golden] MATCH: 两侧生成的图与查询逐元素一致（R6.2 满足）。"
    } else {
        $goldenVerdict.matched = $false
        $goldenVerdict.detail = "两侧黄金图样本不一致：生成算法在两侧未逐元素对齐，加速比不可信。"
        Write-Error "[golden] MISMATCH: 两侧生成的图/查询不一致（R6.2 违反）。"
        # 写出差异样本以便审计。
        [IO.File]::WriteAllText((Join-Path $outRoot "golden-mismatch-rust-$timestamp.json"), $rustConfigsJson, [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText((Join-Path $outRoot "golden-mismatch-moon-$timestamp.json"), $moonConfigsJson, [Text.Encoding]::UTF8)
        throw "黄金交叉校验失败（R6.2）：两侧图/查询不逐元素一致，已中止对比以免产出不可信加速比。"
    }
} else {
    Write-Warning "黄金交叉校验需同时具备 Rust 侧与本库侧采集；当前缺其一，跳过交叉校验（优雅降级）。"
}

# ─────────────────────────── 基准采集（R6.1/R6.3） ───────────────────────────
$commonBenchArgs = @(
    "--mode", "bench",
    "--seed", $Seed,
    "--queries", "$Queries",
    "--warmup", "$Warmup",
    "--samples", "$Samples",
    "--sizes", $Sizes,
    "--degrees", $Degrees,
    "--timeout-sec", "$TimeoutSec"
)

$rustReport = $null
$moonReport = $null

if ($runRust) {
    Write-Host "=== RUST SIDE BENCH ==="
    $rustBenchFile = Join-Path $outRoot "rust-bench-$timestamp.json"
    $rustReportRaw = Invoke-RustHarness -HarnessArgs $commonBenchArgs -OutFile $rustBenchFile
    $rustReport = $rustReportRaw | ConvertFrom-Json
}

if ($runMoon) {
    Write-Host "=== MOONBIT (本库) SIDE BENCH ==="
    $moonReportRaw = Invoke-MoonHarness -HarnessArgs $commonBenchArgs -BeginMarker "===MOONSIDE_BENCH_BEGIN===" -EndMarker "===MOONSIDE_BENCH_END==="
    $moonReport = $moonReportRaw | ConvertFrom-Json
    [IO.File]::WriteAllText((Join-Path $outRoot "moon-bench-$timestamp.json"), $moonReportRaw, [Text.Encoding]::UTF8)
}

# ─────────────────────────── 配对、一致性与加速比（R6.6/R6.7） ───────────────────────────
function Get-CaseKey {
    param($Case)
    return "$($Case.algorithm)|$($Case.graph_size)|$($Case.avg_out_degree)"
}

function Signatures-Equal {
    param($A, $B)
    if ($null -eq $A -or $null -eq $B) { return $false }
    if ($A.Count -ne $B.Count) { return $false }
    for ($i = 0; $i -lt $A.Count; $i++) {
        if ([int]$A[$i] -ne [int]$B[$i]) { return $false }
    }
    return $true
}

$comparisons = New-Object System.Collections.Generic.List[object]

if ($null -ne $rustReport -and $null -ne $moonReport) {
    $moonByKey = @{}
    foreach ($c in $moonReport.cases) { $moonByKey[(Get-CaseKey $c)] = $c }

    foreach ($rc in $rustReport.cases) {
        $key = Get-CaseKey $rc
        $mc = $moonByKey[$key]
        if ($null -eq $mc) {
            $comparisons.Add([ordered]@{
                key = $key; algorithm = $rc.algorithm; graph_size = $rc.graph_size; avg_out_degree = $rc.avg_out_degree
                included = $false; exclude_reason = "本库侧缺少对应用例"
                rust_median_ms = $rc.stats.median_ms; moon_median_ms = $null; speedup_moon_over_rust = $null
            })
            continue
        }

        $consistent = Signatures-Equal -A $rc.signatures -B $mc.signatures
        $timedOut = $rc.timed_out -or $mc.timed_out
        $excludeReason = ""
        if ($timedOut) { $excludeReason = "超时（单次采样 >${TimeoutSec}s）" }
        elseif (-not $consistent) { $excludeReason = "两库结果不一致（结果签名不同）" }
        elseif ($crossMachine) { $excludeReason = "跨机器/工具链，不据此声明加速比（R6.8）" }
        elseif ([double]$mc.stats.median_ms -le 0 -or [double]$rc.stats.median_ms -le 0) { $excludeReason = "中位计时非正，无法计算比值" }

        $included = [string]::IsNullOrEmpty($excludeReason)
        $speedup = $null
        if ($included) {
            # 加速比口径：本库相对 Rust 的中位加速（>1 表示本库更快）（R6.6）。
            $speedup = [double]$rc.stats.median_ms / [double]$mc.stats.median_ms
        }

        $comparisons.Add([ordered]@{
            key = $key; algorithm = $rc.algorithm; graph_size = $rc.graph_size; avg_out_degree = $rc.avg_out_degree
            edge_count = $rc.edge_count; query_count = $rc.query_count
            included = $included; exclude_reason = $excludeReason
            consistent = $consistent; timed_out = $timedOut
            rust_median_ms = [double]$rc.stats.median_ms; rust_min_ms = [double]$rc.stats.min_ms; rust_mean_ms = [double]$rc.stats.mean_ms; rust_p95_ms = [double]$rc.stats.p95_ms
            moon_median_ms = [double]$mc.stats.median_ms; moon_min_ms = [double]$mc.stats.min_ms; moon_mean_ms = [double]$mc.stats.mean_ms; moon_p95_ms = [double]$mc.stats.p95_ms
            speedup_moon_over_rust = $speedup
        })
    }
}

# ─────────────────────────── 方法学声明（R6.4） ───────────────────────────
$methodology = @(
    "输入生成：两侧共享逐位一致的 xorshift64 随机源与完全相同的确定性生成算法；边数 = 节点数 × 平均出度，按 (u,v,w) 顺序生成（自环改写为 (u+1)%n），查询按 (s,t) 顺序生成。",
    "随机种子：$Seed（十进制，64 位）；两侧用同一种子产出逐元素相同的图与查询集（黄金 JSON 交叉校验，R6.2）。",
    "工作负载矩阵：BFS/Dijkstra/A* × 规模 {$Sizes} × 平均出度 {$Degrees} × 每组 $Queries 查询。",
    "A* 启发式：一般图上使用零启发式（admissible），等价一致代价搜索；两侧一致。",
    "预热/测量：每用例 ≥$Warmup 预热 + ≥$Samples 计时采样；单次采样 = 运行该用例全部查询一遍；计时单位毫秒。",
    "加速比口径：统一以中位计时计算（本库中位 ÷ Rust 中位 → 本库相对 Rust 的加速；>1 表示本库更快）（R6.6）。",
    "排除规则：失败 / 超时（单次采样 >${TimeoutSec}s）/ 两库结果不一致（结果签名不同）的用例标注并排除出加速比（R6.7）。",
    "测量环境：见报告头部 CPU/OS 与两套工具链版本；跨机器/跨工具链对比显式标注且不据此声明加速比（R6.8）。"
)

# ─────────────────────────── 写出 JSON 产物 ───────────────────────────
$includedComparisons = @($comparisons | Where-Object { $_.included })
$medianSpeedups = @($includedComparisons | ForEach-Object { [double]$_.speedup_moon_over_rust })
$aggregateMedianSpeedup = $null
if ($medianSpeedups.Count -gt 0) {
    $sortedSp = @($medianSpeedups | Sort-Object)
    $cnt = $sortedSp.Count
    if ($cnt % 2 -eq 1) { $aggregateMedianSpeedup = $sortedSp[[int][Math]::Floor($cnt / 2)] }
    else { $aggregateMedianSpeedup = ($sortedSp[$cnt / 2 - 1] + $sortedSp[$cnt / 2]) / 2.0 }
}

$artifact = [ordered]@{
    schema = "moonbit-pathfinding.rust-comparison.report.v1"
    generated_at = $generatedAt
    generated_by = "scripts/rust_comparison.ps1"
    quick_mode = $Quick.IsPresent
    seed = $Seed
    workload = [ordered]@{ sizes = $Sizes; degrees = $Degrees; queries = $Queries; warmup = $Warmup; samples = $Samples; timeout_sec = $TimeoutSec }
    machine = $machine
    toolchains = [ordered]@{ moon = $moonVersion; rustc = $rustcVersion; cargo = $cargoVersion; rust_library = "pathfinding 4.11.0"; moon_library = "moonbit-pathfinding" }
    cross_machine = $crossMachine
    cross_machine_ids = [ordered]@{ rust = $RustMachineId; moon = $MoonMachineId }
    golden_cross_check = $goldenVerdict
    methodology = $methodology
    degradations = $degradations.ToArray()
    aggregate_median_speedup_moon_over_rust = $aggregateMedianSpeedup
    comparisons = $comparisons.ToArray()
    rust_report_present = ($null -ne $rustReport)
    moon_report_present = ($null -ne $moonReport)
}

$jsonPath = Join-Path $outRoot ("rust-comparison-$timestamp.json")
$latestJsonPath = Join-Path $outRoot "latest-rust-comparison.json"
$json = $artifact | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($jsonPath, $json + "`n", [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($latestJsonPath, $json + "`n", [Text.Encoding]::UTF8)

# ─────────────────────────── 写出 Markdown 产物（R6.1 双产物） ───────────────────────────
function Fmt {
    param($v)
    if ($null -eq $v) { return "-" }
    return [Math]::Round([double]$v, 4)
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Rust ``pathfinding`` Comparison Report")
$md.Add("")
$md.Add("- Generated at: ``$generatedAt``")
$md.Add('- Script: `scripts/rust_comparison.ps1`')
$md.Add('- Sides: MoonBit `bench_rust/moon_side` (本库) vs Rust `bench_rust/` (`pathfinding` crate)')
$md.Add("- Seed: ``$Seed`` (decimal, 64-bit)")
$md.Add("- Workload: BFS/Dijkstra/A* × sizes {``$Sizes``} × avg out-degree {``$Degrees``} × ``$Queries`` queries")
$md.Add("- Sampling: warmup ``$Warmup``, samples ``$Samples``, timeout ``${TimeoutSec}s`` per sample")
$md.Add("- Machine: ``$($machine.os)``, ``$($machine.cpu)``")
$md.Add("- Toolchains: moon ``$moonVersion``; ``$rustcVersion``; ``$cargoVersion``; Rust lib ``pathfinding 4.11.0``")
if ($Quick.IsPresent) { $md.Add("- **Quick mode**: reduced matrix (smoke validation, not formal comparison evidence)") }
$md.Add("")

# 黄金交叉校验状态。
$md.Add("## Golden cross-check (R6.2)")
$md.Add("")
if ($goldenVerdict.performed) {
    $status = if ($goldenVerdict.matched) { "✅ MATCH" } else { "❌ MISMATCH" }
    $md.Add("$status — $($goldenVerdict.detail)")
} else {
    $md.Add("Skipped (requires both Rust and MoonBit sides).")
}
$md.Add("")

# 降级 / 环境告警。
if ($degradations.Count -gt 0) {
    $md.Add("## Environment notes / degradations")
    $md.Add("")
    foreach ($d in $degradations) { $md.Add("- $d") }
    $md.Add("")
}
if ($crossMachine) {
    $md.Add("> ⚠️ Cross-machine/toolchain data (Rust='$RustMachineId' vs Moon='$MoonMachineId'): speedups are NOT claimed (R6.8).")
    $md.Add("")
}

# 加速比汇总。
$md.Add("## Aggregate")
$md.Add("")
if ($null -ne $aggregateMedianSpeedup) {
    $md.Add("- Median of per-case median speedups (MoonBit over Rust): **$(Fmt $aggregateMedianSpeedup)×** (>1 means MoonBit faster)")
    $md.Add("- Included cases: ``$($includedComparisons.Count)`` / ``$($comparisons.Count)``")
} else {
    $md.Add("- No included cases for speedup (all excluded or one side missing).")
}
$md.Add("")

# 逐用例对比表。
$md.Add("## Per-case comparison (median caliber, R6.6)")
$md.Add("")
$md.Add("| Algorithm | Nodes | Deg | Edges | Rust median ms | MoonBit median ms | Speedup (Moon/Rust) | Included | Note |")
$md.Add("|---|---:|---:|---:|---:|---:|---:|:--:|---|")
foreach ($c in $comparisons) {
    $inc = if ($c.included) { "✅" } else { "❌" }
    $note = if ($c.included) { "" } else { $c.exclude_reason }
    $sp = if ($null -ne $c.speedup_moon_over_rust) { "$(Fmt $c.speedup_moon_over_rust)×" } else { "-" }
    $md.Add("| $($c.algorithm) | $($c.graph_size) | $($c.avg_out_degree) | $($c.edge_count) | $(Fmt $c.rust_median_ms) | $(Fmt $c.moon_median_ms) | $sp | $inc | $note |")
}
$md.Add("")

# 方法学声明。
$md.Add("## Methodology (R6.4)")
$md.Add("")
foreach ($m in $methodology) { $md.Add("- $m") }
$md.Add("")
$md.Add("Raw artifacts: ``$(Split-Path -Leaf $jsonPath)``, ``latest-rust-comparison.json``.")

$mdPath = Join-Path $outRoot "latest-rust-comparison.md"
[IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", [Text.Encoding]::UTF8)

Write-Host "=== RUST COMPARISON ARTIFACTS ==="
Write-Host $jsonPath
Write-Host $latestJsonPath
Write-Host $mdPath

# 若两侧均缺失，提示但不失败（基础设施任务：交付完整工程与脚本，环境受限时降级）。
if ($null -eq $rustReport -and $null -eq $moonReport) {
    Write-Warning "两侧采集均未执行（工具链缺失或被跳过）：仅产出方法学声明与环境说明报告。"
}
