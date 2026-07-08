# mooncakes_audit.ps1 —— mooncakes.io 全量索引抓取 + 审计快照刷新（G-A3 + H-1）。
#
# 职责边界：网络抓取与快照落盘在脚本层完成；分类 / 缺口 / 许可证审计的
# 纯计算在 src/mooncakes_audit（MoonBit，离线可测）。
#
# 输出：
#   docs/verification/mooncakes_index.psv —— 每行 `name|version|license|description`
#   （字段内竖线仅可能出现在尾字段 description，与引擎解析约定一致）；
#   控制台摘要 —— 总包数与许可证 Top 分布，供 ECOSYSTEM_COMPARISON 刷新对照。
$ErrorActionPreference = "Stop"

$apiUrl = "https://mooncakes.io/api/v0/modules"
$outPath = Join-Path $PSScriptRoot "../docs/verification/mooncakes_index.psv"

Write-Host "Fetching mooncakes index from $apiUrl ..."
$modules = Invoke-RestMethod -Uri $apiUrl -Method Get

$lines = foreach ($m in $modules) {
    $name = "$($m.name)" -replace '\|', '/'
    $version = "$($m.version)" -replace '\|', '/'
    $license = "$($m.license)" -replace '\|', '/'
    $desc = ("$($m.description)" -replace "`r", ' ') -replace "`n", ' '
    "$name|$version|$license|$desc"
}

$lines | Set-Content -Path $outPath -Encoding UTF8
Write-Host "Snapshot written: $outPath ($($lines.Count) packages)"

$licenseTop = $modules | Group-Object license | Sort-Object Count -Descending | Select-Object -First 8
Write-Host "License distribution (top 8):"
foreach ($g in $licenseTop) {
    $label = if ([string]::IsNullOrEmpty($g.Name)) { "(none)" } else { $g.Name }
    Write-Host ("  {0,-24} {1}" -f $label, $g.Count)
}
