#!/usr/bin/env pwsh
# ──────────────────────────────────────────────────────────────────────
# wasm_size_guard.ps1 — 任务 27.2 · WASM 产物体积硬门禁（R1.1/R1.4/R1.5/R4.5）
# ──────────────────────────────────────────────────────────────────────
# 用途（对应 design.md §「方向 1 · 体积优化策略」与 requirements.md Requirement 1/4）：
#   把 `@playground` 导出层（pg_* 整型句柄协议）编译为 wasm-gc release 产物，
#   并以「磁盘字节数 ≤ WASM_SIZE_LIMIT（102400 字节 = 100 KB）」为硬门禁：
#     1. 运行 `moon build --target wasm-gc --release` 构建 Playground_Wasm_Module；
#        构建失败（非零退出）即门禁失败（不判定体积达标）。
#     2. 定位 `@playground` 链接产物 `playground.wasm`，读取其在磁盘上的字节数
#        （体积定义即「该 .wasm 文件在磁盘上的字节数」，R1.1）。产物缺失即门禁失败。
#     3. IF 字节数 > 102400：在报告中同时记录「实测字节数」与「102400 上限」，
#        以非零退出状态使体积门禁失败并阻止发布（R1.4 / R4.5）。
#     4. 确定性构建校验（R1.5）：可选地清理后重建一次，比较两次产物的字节数与
#        SHA-256；若不一致则门禁失败（重复运行必须产出字节数完全一致的 .wasm）。
#
# 产物定位说明：
#   `@playground` 在 `src/playground/moon.pkg` 中通过 `options(link: { "wasm-gc":
#   { exports: [...] } })` 声明 wasm-gc 链接导出，故 `moon build --target wasm-gc
#   --release` 会在构建目录下产出按包名命名的链接产物 `playground.wasm`
#   （本仓库构建根为 `_build/wasm-gc/release/build/src/playground/playground.wasm`；
#   旧版 moon 为 `target/wasm-gc/release/build/...`）。脚本对两种构建根与
#   `*/src/playground/playground.wasm` 路径做稳健探测，并在报告中说明定位方式。
#
# 退出码约定：
#   0  —— 实测字节数 ≤ 上限，构建成功、产物存在，且（如启用）确定性校验通过。
#   1  —— 实测字节数 > 上限（R1.4），或构建失败 / 产物缺失 / 确定性校验失败 /
#         报告写出失败（不判定体积达标）。
#   2  —— 前置条件不满足（如 moon 不在 PATH）。
#
# 兼容性：面向 pwsh（PowerShell 7+）编写，同时兼容 Windows PowerShell 5.1
#   （不使用 null 合并 / 三元等 7+ 专属语法）。
# ──────────────────────────────────────────────────────────────────────

[CmdletBinding()]
param(
    # 体积上限（字节）。<0 时回退到 WASM_SIZE_LIMIT 环境变量，仍未提供则取
    # R1 规定的 102400（100 KB）。
    [long]$Limit = -1,
    # 报告产物输出目录。
    [string]$OutDir = "docs/verification",
    # 目标 wasm 包（用于定位链接产物 <pkg>.wasm）。
    [string]$Package = "src/playground",
    # 链接产物文件名（`@playground` 的 options(link:) 产物按包名命名）。
    [string]$WasmName = "playground.wasm",
    # 跳过确定性构建校验（R1.5）。默认执行校验：清理后重建一次并比较两次产物
    # 的字节数 / SHA-256。CI 中如需缩短时间可显式传入 -SkipDeterminismCheck。
    # 用 [switch] 而非 [bool] 以兼容 `pwsh -File`（-File 下参数为字面字符串，
    # `$false` 会被当作真值字符串）。
    [switch]$SkipDeterminismCheck
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 是否执行确定性校验：默认开启，传入 -SkipDeterminismCheck 时关闭。
$VerifyDeterminism = -not $SkipDeterminismCheck

# 文本产物统一使用「无 BOM」UTF-8，确保 JSON 可被严格解析器直接读取。
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# 体积上限常量（R1.1）：WASM_SIZE_LIMIT = 102400 字节（100 KB）。
$WASM_SIZE_LIMIT_DEFAULT = 102400L

# ───────────────────────── 上限解析（兼容 5.1，不用 null 合并） ─────────────────────────

if ($Limit -lt 0) {
    if ($env:WASM_SIZE_LIMIT) {
        $Limit = [long]$env:WASM_SIZE_LIMIT
    } else {
        $Limit = $WASM_SIZE_LIMIT_DEFAULT
    }
}

Write-Host "=== WASM Size Gate (task 27.2 · R1.1/R1.4/R1.5/R4.5) ===" -ForegroundColor Cyan
Write-Host ("Limit     : .wasm disk bytes <= {0} 字节 ({1} KB)" -f $Limit, [math]::Round($Limit / 1024.0, 1))
Write-Host ("Package   : {0} (artifact: {1})" -f $Package, $WasmName)
Write-Host ("Determinism check : {0}" -f $VerifyDeterminism)

# ───────────────────────── 路径解析与前置检查 ─────────────────────────

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = if ([IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $root $OutDir }

$moonCmd = Get-Command moon -ErrorAction SilentlyContinue
if ($null -eq $moonCmd) {
    Write-Host "::error::'moon' 不在 PATH 中，无法运行 WASM 体积门禁。" -ForegroundColor Red
    exit 2
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$moonVersion = ((& moon version 2>&1 | ForEach-Object { [string]$_ }) -join " ").Trim()

# 候选构建根（新版 _build / 旧版 target），用于稳健定位链接产物。
$buildRoots = @(
    (Join-Path $root "_build/wasm-gc/release/build"),
    (Join-Path $root "target/wasm-gc/release/build")
)
# 包内的首选产物路径（按 <Package>/<WasmName> 直接命中）。
$preferredRelative = (($Package -replace '\\', '/') + "/" + $WasmName)

# ───────────────────── 失败收尾：写出诊断产物并以指定码退出 ─────────────────────

function Write-WasmArtifacts {
    param(
        [object]$Artifact,
        [string[]]$MarkdownLines
    )
    try {
        New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
        $json = $Artifact | ConvertTo-Json -Depth 12
        $jsonPath = Join-Path $outRoot ("wasm-size-guard-$timestamp.json")
        $latestJson = Join-Path $outRoot "latest-wasm-size-guard.json"
        $mdPath = Join-Path $outRoot "latest-wasm-size-guard.md"
        [IO.File]::WriteAllText($jsonPath, $json + "`n", $Utf8NoBom)
        [IO.File]::WriteAllText($latestJson, $json + "`n", $Utf8NoBom)
        [IO.File]::WriteAllText($mdPath, ($MarkdownLines -join "`n") + "`n", $Utf8NoBom)
        Write-Host "=== WASM SIZE GUARD ARTIFACTS ===" -ForegroundColor Cyan
        Write-Host $jsonPath
        Write-Host $latestJson
        Write-Host $mdPath
        return $true
    } catch {
        Write-Host "::error::WASM 体积报告写出失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 运行一次 release 构建，返回退出码与输出。
function Invoke-WasmBuild {
    $out = New-Object System.Collections.Generic.List[string]
    & moon build --target wasm-gc --release 2>&1 | ForEach-Object {
        $line = [string]$_
        $out.Add($line)
    }
    [ordered]@{ exit_code = $LASTEXITCODE; output = $out.ToArray() }
}

# 稳健定位链接产物 playground.wasm：优先按 <Package>/<WasmName> 命中，
# 否则在候选构建根下递归查找同名产物（取最深匹配 src/playground 路径者）。
function Resolve-WasmArtifact {
    foreach ($br in $buildRoots) {
        $p = Join-Path $br $preferredRelative
        if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
    }
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($br in $buildRoots) {
        if (Test-Path -LiteralPath $br) {
            Get-ChildItem -LiteralPath $br -Recurse -File -Filter $WasmName -ErrorAction SilentlyContinue |
                ForEach-Object { $candidates.Add($_.FullName) }
        }
    }
    if ($candidates.Count -eq 0) { return $null }
    # 优先选择路径中包含 src/playground 的产物。
    foreach ($c in $candidates) {
        $n = $c -replace '\\', '/'
        if ($n -like "*$($Package -replace '\\', '/')*") { return $c }
    }
    return $candidates[0]
}

# 读取文件磁盘字节数（R1.1 体积定义）。
function Get-FileBytes {
    param([string]$Path)
    return ([IO.FileInfo]$Path).Length
}

# 计算 SHA-256（用于确定性校验 R1.5）。
function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

# 失败收尾的统一封装：组装 artifact + markdown 并退出。
function Fail-Gate {
    param(
        [string]$Reason,
        [object]$ExtraFields
    )
    Write-Host "::error::WASM 体积门禁失败：$Reason" -ForegroundColor Red
    $artifact = [ordered]@{
        schema       = "moonbit-pathfinding.wasm-size-guard.v1"
        generated_at = $generatedAt
        generated_by = "scripts/wasm_size_guard.ps1"
        moon_version = $moonVersion
        package      = $Package
        wasm_name    = $WasmName
        limit_bytes  = $Limit
        status       = "failed"
        reason       = $Reason
    }
    if ($null -ne $ExtraFields) {
        foreach ($k in $ExtraFields.Keys) { $artifact[$k] = $ExtraFields[$k] }
    }
    $md = @(
        "# WASM Size Guard Report",
        "",
        "- Generated at: $generatedAt",
        "- Script: scripts/wasm_size_guard.ps1",
        "- MoonBit: $moonVersion",
        "- Package: $Package",
        "- Artifact: $WasmName",
        "- Limit: $Limit 字节",
        "- Status: FAILED",
        "- Reason: $Reason",
        ""
    )
    [void](Write-WasmArtifacts -Artifact $artifact -MarkdownLines $md)
    exit 1
}

# ───────────────────── 1. 构建（失败即门禁失败，不判定达标） ─────────────────────

Write-Host ""
Write-Host "--- moon build --target wasm-gc --release（第 1 次） ---" -ForegroundColor Cyan
$build1 = Invoke-WasmBuild
if ($build1.exit_code -ne 0) {
    $tail = $build1.output
    $tailCount = [Math]::Min(40, $tail.Count)
    if ($tailCount -gt 0) {
        Write-Host "--- 构建输出末尾 $tailCount 行 ---" -ForegroundColor Yellow
        $tail[($tail.Count - $tailCount)..($tail.Count - 1)] | ForEach-Object { Write-Host "  $_" }
    }
    Fail-Gate -Reason ("moon build --target wasm-gc --release 以非零状态退出（exit={0}）。" -f $build1.exit_code) `
        -ExtraFields ([ordered]@{ build_exit = $build1.exit_code })
}

# ───────────────────── 2. 定位产物（缺失即门禁失败） ─────────────────────

$wasmPath = Resolve-WasmArtifact
if ($null -eq $wasmPath) {
    Fail-Gate -Reason ("未找到链接产物 {0}（已在 {1} 下递归查找）。请确认 {2}/moon.pkg 已配置 options(link:) 的 wasm-gc exports 列表。" -f $WasmName, ($buildRoots -join " | "), $Package) `
        -ExtraFields ([ordered]@{ searched_roots = $buildRoots })
}
$relPath = $wasmPath
if ($wasmPath.StartsWith($root)) {
    $relPath = $wasmPath.Substring($root.Length).TrimStart([char]'/', [char]'\') -replace '\\', '/'
}

$bytes1 = Get-FileBytes -Path $wasmPath
$sha1 = Get-Sha256 -Path $wasmPath
Write-Host ("--- 定位产物: {0} ---" -f $relPath) -ForegroundColor Cyan
Write-Host ("  实测字节数 = {0}，SHA-256 = {1}" -f $bytes1, $sha1)

# ───────────────────── 3. 确定性校验（R1.5，可选） ─────────────────────

$determinism = [ordered]@{
    verified     = $false
    bytes_first  = $bytes1
    sha256_first = $sha1
}
if ($VerifyDeterminism) {
    Write-Host ""
    Write-Host "--- 确定性校验：moon clean + 重建（第 2 次） ---" -ForegroundColor Cyan
    & moon clean 2>&1 | Out-Null
    $build2 = Invoke-WasmBuild
    if ($build2.exit_code -ne 0) {
        Fail-Gate -Reason ("确定性校验阶段重建失败（exit={0}）。" -f $build2.exit_code) `
            -ExtraFields ([ordered]@{ wasm_path = $relPath; bytes = $bytes1; sha256 = $sha1; build2_exit = $build2.exit_code })
    }
    $wasmPath2 = Resolve-WasmArtifact
    if ($null -eq $wasmPath2) {
        Fail-Gate -Reason "确定性校验阶段重建后未找到链接产物。" `
            -ExtraFields ([ordered]@{ wasm_path = $relPath; bytes = $bytes1; sha256 = $sha1 })
    }
    $bytes2 = Get-FileBytes -Path $wasmPath2
    $sha2 = Get-Sha256 -Path $wasmPath2
    Write-Host ("  重建字节数 = {0}，SHA-256 = {1}" -f $bytes2, $sha2)
    $determinism.bytes_second = $bytes2
    $determinism.sha256_second = $sha2
    if ($bytes1 -ne $bytes2 -or $sha1 -ne $sha2) {
        Fail-Gate -Reason ("确定性校验失败（R1.5）：两次构建字节数/哈希不一致（{0}/{1} vs {2}/{3}）。" -f $bytes1, $sha1, $bytes2, $sha2) `
            -ExtraFields ([ordered]@{ wasm_path = $relPath; determinism = $determinism })
    }
    $determinism.verified = $true
    Write-Host "  确定性校验通过：两次构建字节数与 SHA-256 完全一致。" -ForegroundColor Green
}

# ───────────────────── 4. 体积判定与产物组装（R1.1/R1.4） ─────────────────────

$passed = $bytes1 -le $Limit
$status = if ($passed) { "passed" } else { "failed" }
$marginBytes = $Limit - $bytes1
$usagePct = [math]::Round($bytes1 * 100.0 / $Limit, 1)

$artifact = [ordered]@{
    schema          = "moonbit-pathfinding.wasm-size-guard.v1"
    generated_at    = $generatedAt
    generated_by    = "scripts/wasm_size_guard.ps1"
    moon_version    = $moonVersion
    package         = $Package
    wasm_name       = $WasmName
    wasm_path       = $relPath
    locate_method   = "options(link:) → <build-root>/$preferredRelative（缺省时按构建根递归查找同名产物）"
    measured_bytes  = $bytes1
    limit_bytes     = $Limit
    margin_bytes    = $marginBytes
    usage_percent   = $usagePct
    sha256          = $sha1
    determinism     = $determinism
    status          = $status
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# WASM Size Guard Report")
$md.Add("")
$md.Add("- Generated at: $generatedAt")
$md.Add("- Script: scripts/wasm_size_guard.ps1")
$md.Add("- MoonBit: $moonVersion")
$md.Add("- Package: $Package")
$md.Add("- Artifact: $relPath")
$md.Add("- Locate method: options(link:) 链接产物 <build-root>/$preferredRelative")
$md.Add(("- Measured size: {0} 字节（{1} KB，占上限 {2}%）" -f $bytes1, [math]::Round($bytes1 / 1024.0, 1), $usagePct))
$md.Add(("- Limit: {0} 字节（100 KB）" -f $Limit))
$md.Add(("- Margin: {0} 字节" -f $marginBytes))
$md.Add("- SHA-256: $sha1")
if ($VerifyDeterminism) {
    $md.Add(("- Determinism (R1.5): {0}（两次构建字节数/SHA-256 一致性校验）" -f $determinism.verified))
} else {
    $md.Add("- Determinism (R1.5): 未在本次运行校验（-SkipDeterminismCheck）")
}
$md.Add("- Status: $($status.ToUpper())")
$md.Add("")

$wrote = Write-WasmArtifacts -Artifact $artifact -MarkdownLines $md.ToArray()
if (-not $wrote) { exit 1 }

# ───────────────────── 5. 控制台摘要与门禁退出语义 ─────────────────────

Write-Host ""
Write-Host "--- Summary ---" -ForegroundColor Cyan
Write-Host ("Measured: {0} 字节 / Limit: {1} 字节 / Margin: {2} 字节" -f $bytes1, $Limit, $marginBytes)

if (-not $passed) {
    # R1.4 / R4.5：记录实测字节数与上限，并以非零退出阻止发布。
    Write-Host ("::error::WASM size gate FAILED: 实测 {0} 字节 > 上限 {1} 字节（超出 {2} 字节）。中止发布并保留上一版本。" -f $bytes1, $Limit, ([math]::Abs($marginBytes))) -ForegroundColor Red
    exit 1
}

Write-Host ("::notice::WASM size gate PASSED: 实测 {0} 字节 <= 上限 {1} 字节（余量 {2} 字节）。" -f $bytes1, $Limit, $marginBytes) -ForegroundColor Green
exit 0
