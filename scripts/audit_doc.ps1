#!/usr/bin/env pwsh
# Audit: 查找所有 src/**/*.mbt 中的 pub 声明并检查上方是否有 Doc_Comment
# Doc_Comment 定义: 紧挨 pub 声明上方、以 `///` 开头且不是 `///|` 分隔符的注释行
# 输出: 缺失 Doc_Comment 的 pub 声明列表

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$srcDir = Join-Path $root 'src'
$missing = @()
$total = 0

Get-ChildItem -Path $srcDir -Recurse -Filter '*.mbt' | ForEach-Object {
    $file = $_.FullName
    $lines = Get-Content -LiteralPath $file
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*pub(\(all\)|\(open\))?\s+(fn|let|struct|enum|trait|impl|type|typealias)') {
            $total++
            # 扫描上方注释,跳过 `///|` 分隔符
            $hasDoc = $false
            for ($j = $i - 1; $j -ge 0; $j--) {
                $prev = $lines[$j]
                if ($prev -match '^\s*$') { break }
                if ($prev -match '^\s*///\|\s*$') { continue }
                if ($prev -match '^\s*///') { $hasDoc = $true; break }
                if ($prev -match '^\s*//') { continue }
                break
            }
            if (-not $hasDoc) {
                $missing += "${file}:$($i+1): $($line.Trim())"
            }
        }
    }
}

Write-Host "=== Doc Comment Audit ===" -ForegroundColor Cyan
Write-Host "Total pub declarations: $total"
Write-Host "Missing Doc_Comment: $($missing.Count)"
if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "--- Missing List ---" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host $_ }
    exit 1
} else {
    Write-Host "All public APIs have Doc_Comment." -ForegroundColor Green
    exit 0
}
