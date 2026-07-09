# evidence_guard.ps1 —— 证据索引断链门禁（H-4 + G-C2）。
#
# 校验 docs/verification/evidence_index.psv 的三元组完整性
# （与 src/evidence_index 引擎同一约定）：
#   * 每行恰好 3 个字段 `claim|test_ref|commit`；
#   * claim 非空；test_ref 含 `::` 锚点，`::` 前为真实存在的包目录，
#     `::` 后的锚点描述非空（避免「指向包却不说验证什么」的空壳引用）；
#   * commit 为 7..40 位十六进制且存在于 git 历史；
#   * (claim, test_ref) 组合全局唯一（同一断言不得重复登记，防止证据虚增）。
# 任一断链即非零退出，供 CI 消费。
$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot ".."
$psv = Join-Path $root "docs/verification/evidence_index.psv"

$failures = @()
$seen = @{}
$lineno = 0
foreach ($line in Get-Content $psv) {
    $lineno++
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split '\|'
    if ($parts.Count -ne 3) { $failures += "line ${lineno}: expected 3 fields"; continue }
    $claim, $testRef, $commit = $parts
    if ([string]::IsNullOrWhiteSpace($claim)) { $failures += "line ${lineno}: empty claim" }
    if ($testRef -notmatch '::') {
        $failures += "line ${lineno}: test_ref missing :: anchor"
    } else {
        $pkg = ($testRef -split '::', 2)[0]
        $anchor = ($testRef -split '::', 2)[1]
        if ([string]::IsNullOrWhiteSpace($pkg)) { $failures += "line ${lineno}: empty package in test_ref" }
        elseif (-not (Test-Path (Join-Path $root $pkg))) { $failures += "line ${lineno}: package dir missing: $pkg" }
        if ([string]::IsNullOrWhiteSpace($anchor)) { $failures += "line ${lineno}: empty anchor after :: in test_ref" }
    }
    if ($commit -notmatch '^[0-9a-f]{7,40}$') {
        $failures += "line ${lineno}: bad commit hash"
    } else {
        git -C $root cat-file -e "$commit^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) { $failures += "line ${lineno}: commit not in history: $commit" }
    }
    $key = "$claim|$testRef"
    if ($seen.ContainsKey($key)) {
        $failures += "line ${lineno}: duplicate (claim, test_ref) also at line $($seen[$key])"
    } else {
        $seen[$key] = $lineno
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "EVIDENCE BROKEN: $_" }
    exit 1
}
Write-Host "evidence_guard: all evidence triples sound."
