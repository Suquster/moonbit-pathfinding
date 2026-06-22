#!/usr/bin/env pwsh
# ──────────────────────────────────────────────────────────────────────
# doc_api_guard.ps1 — 任务 29.4 · 文档完整性硬门禁（Doc_Api_Guard, R21.3/21.4）
# ──────────────────────────────────────────────────────────────────────
# 用途（对应 design.md §文档行数门禁 与 requirements.md Requirement 21.3/21.4）：
#   在既有 audit_doc.ps1 的基础上扩展为「R21.3 文档行数门禁」：
#     1. 扫描全部 src/**/*.mbt（排除 *_test.mbt / *_wbtest.mbt），识别每个
#        Pub_Api（以 `pub` 修饰的函数 / 类型 / 方法 / trait / impl 等）。
#     2. 统计该 API 紧邻上方的 `///` Doc_Comment 中的「非空注释行」数量。
#        非空注释行定义（R21.3）：去除首尾空白后长度 > 0 的 `///` 注释行；
#        `///|` 是 MoonBit 的块分隔符，不属于文档内容，亦标记文档块的上界。
#     3. IF 某 Pub_Api 的非空注释行 < MinLines（默认 5）：以「API 标识 +
#        实际非空注释行数」报告，并以非零退出状态使门禁失败（R21.4）。
#
# 与 audit_doc.ps1 的关系：
#   audit_doc.ps1 只校验「是否存在 Doc_Comment」（≥1 行即通过）。本脚本进一步
#   要求「非空注释行 ≥ 5」，是其严格超集；audit_doc 保留用于快速巡检。
#
# 退出码约定：
#   0  —— 全部 Pub_Api 的非空注释行 ≥ 阈值。
#   1  —— 至少一个 Pub_Api 的非空注释行 < 阈值（R21.4），或报告写出失败。
#   2  —— 前置条件不满足（如 src 目录不存在）。
#
# 兼容性：面向 pwsh（PowerShell 7+）编写，同时兼容 Windows PowerShell 5.1
#   （不使用 null 合并 / 三元等 7+ 专属语法），跨平台运行。
# ──────────────────────────────────────────────────────────────────────

[CmdletBinding()]
param(
    # 每个 Pub_Api 要求的最小非空注释行数。<0 时回退到 DOC_MIN_LINES 环境
    # 变量，仍未提供则取 R21.3 规定的 5。
    [int]$MinLines = -1,
    # 被扫描的源码根目录（相对脚本父目录或绝对路径）。
    [string]$SrcDir = "src",
    # 报告产物输出目录。
    [string]$OutDir = "docs/verification",
    # 控制台最多打印多少条不达标 API（完整清单始终写入产物）。
    [int]$MaxListed = 200,
    # 排除模式（PowerShell -like 通配，匹配规范化后的相对路径与文件名）。
    [string[]]$ExcludeGlobs = @('*_test.mbt', '*_wbtest.mbt')
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 文本产物统一使用「无 BOM」的 UTF-8，确保 JSON 可被严格解析器直接读取。
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ───────────────────────── 阈值解析（兼容 5.1，不用 null 合并） ─────────────────────────

if ($MinLines -lt 0) {
    if ($env:DOC_MIN_LINES) {
        $MinLines = [int]$env:DOC_MIN_LINES
    } else {
        $MinLines = 5
    }
}

Write-Host "=== Doc API Guard (task 29.4 · R21.3/21.4) ===" -ForegroundColor Cyan
Write-Host ("Requirement : 每个 Pub_Api 的非空 Doc_Comment 行 >= {0}" -f $MinLines)
Write-Host ("Exclude     : {0}" -f ($ExcludeGlobs -join ', '))

# ───────────────────────── 路径解析与前置检查 ─────────────────────────

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$srcRoot = if ([IO.Path]::IsPathRooted($SrcDir)) { $SrcDir } else { Join-Path $root $SrcDir }
$outRoot = if ([IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $root $OutDir }

if (-not (Test-Path -LiteralPath $srcRoot)) {
    Write-Host "::error::源码目录不存在：$srcRoot" -ForegroundColor Red
    exit 2
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# ───────────────────── 辅助：相对路径规范化（统一用 /） ─────────────────────

function Get-RelPath {
    param([string]$FullPath)
    $rel = $FullPath
    if ($FullPath.StartsWith($root)) {
        $rel = $FullPath.Substring($root.Length).TrimStart('\', '/')
    }
    return ($rel -replace '\\', '/')
}

function Test-Excluded {
    param([string]$RelPath, [string]$FileName, [string[]]$Globs)
    foreach ($g in $Globs) {
        if ($RelPath -like $g) { return $true }
        if ($FileName -like $g) { return $true }
    }
    return $false
}

# ───────────────────── 辅助：从 pub 声明行提取 API 标识（R21.4 报告用） ─────────────────────
# 尽力解析出可读的 API 标识，如 `fn DSU::new`、`struct DSU`、
# `impl Weight for Int::zero`、`trait Weight`。无法解析时回退到裁剪后的原行。

function Get-ApiIdentifier {
    param([string]$Line)
    $t = $Line.Trim()
    $head = [regex]::Match($t, '^pub(?:\((?:all|open|readonly)\))?\s+(fn|let|const|struct|enum|trait|impl|type|typealias)\b')
    if (-not $head.Success) {
        # 退化：截断原始行作为标识。
        if ($t.Length -gt 80) { return $t.Substring(0, 80) + ' …' }
        return $t
    }
    $kind = $head.Groups[1].Value
    $rest = $t.Substring($head.Length)
    switch ($kind) {
        'fn' {
            # 可选泛型 [..]，随后是 名称 或 Type::method。
            $m = [regex]::Match($rest, '^\s*(?:\[[^\]]*\]\s*)?([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)?)')
            if ($m.Success) { return "fn " + $m.Groups[1].Value }
        }
        'impl' {
            # 形如 `Trait for Type with fn method(...)`，尽量带上方法名。
            $mm = [regex]::Match($rest, '^\s*(.+?)\s+with\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)')
            if ($mm.Success) { return "impl " + $mm.Groups[1].Value.Trim() + "::" + $mm.Groups[2].Value }
            $m2 = [regex]::Match($rest, '^\s*(.+?)\s*(\{|$)')
            if ($m2.Success) { return "impl " + $m2.Groups[1].Value.Trim() }
        }
        default {
            # struct / enum / trait / type / typealias / let / const：取首个标识符。
            $m = [regex]::Match($rest, '^\s*([A-Za-z_][A-Za-z0-9_]*)')
            if ($m.Success) { return "$kind " + $m.Groups[1].Value }
        }
    }
    if ($t.Length -gt 80) { return $t.Substring(0, 80) + ' …' }
    return $t
}

# ───────────────────── 辅助：统计某 pub 行上方 Doc_Comment 的非空注释行数（R21.3） ─────────────────────
# 从 pub 行上一行起向上扫描契约：
#   - 空白行            → 文档块结束（停止）
#   - `///|` 分隔符行   → 文档块上界（停止，不计入）
#   - `///` 文档行      → 去掉 `///` 前缀并 Trim；长度>0 计为非空注释行
#   - `#...` 属性行     → 跳过（继续向上，doc 可能在属性之上）
#   - 其他非注释代码行  → 停止

function Measure-DocLines {
    param([string[]]$Lines, [int]$PubIndex)
    $nonEmpty = 0
    $totalDoc = 0
    for ($j = $PubIndex - 1; $j -ge 0; $j--) {
        $prev = $Lines[$j]
        if ($prev -match '^\s*$') { break }
        if ($prev -match '^\s*///\|') { break }
        if ($prev -match '^\s*///') {
            $totalDoc++
            $content = ($prev -replace '^\s*///', '').Trim()
            if ($content.Length -gt 0) { $nonEmpty++ }
            continue
        }
        if ($prev -match '^\s*#') { continue }
        break
    }
    return [pscustomobject]@{ NonEmpty = $nonEmpty; TotalDoc = $totalDoc }
}

# ───────────────────── 1. 扫描全部源文件，识别 Pub_Api 并统计文档行 ─────────────────────

# Pub_Api 声明匹配：行首（允许缩进）以 pub 修饰，后接受支持的声明关键字。
# `(fn|...)` 后无强制空格，以兼容 `pub fn[N : Eq] Type::method(...)` 写法。
$pubRegex = '^\s*pub(\((all|open|readonly)\))?\s+(fn|let|const|struct|enum|trait|impl|type|typealias)\b'

$apis = New-Object System.Collections.Generic.List[object]
$violations = New-Object System.Collections.Generic.List[object]
$scannedFiles = 0
$totalApis = 0

$mbtFiles = Get-ChildItem -Path $srcRoot -Recurse -Filter '*.mbt' -File | Sort-Object FullName
foreach ($f in $mbtFiles) {
    $rel = Get-RelPath -FullPath $f.FullName
    if (Test-Excluded -RelPath $rel -FileName $f.Name -Globs $ExcludeGlobs) { continue }
    $scannedFiles++

    $lines = Get-Content -LiteralPath $f.FullName
    if ($null -eq $lines) { continue }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match $pubRegex) {
            $totalApis++
            $apiId = Get-ApiIdentifier -Line $line
            $doc = Measure-DocLines -Lines $lines -PubIndex $i
            $record = [pscustomobject]@{
                file       = $rel
                line       = $i + 1
                api        = $apiId
                doc_lines  = $doc.NonEmpty
                total_doc  = $doc.TotalDoc
                location   = "{0}:{1}" -f $rel, ($i + 1)
            }
            $apis.Add($record)
            if ($doc.NonEmpty -lt $MinLines) {
                $violations.Add($record)
            }
        }
    }
}

# ───────────────────── 2. 组装产物（MD + JSON） ─────────────────────

$passed = $violations.Count -eq 0
$status = if ($passed) { "passed" } else { "failed" }

# 不达标项按「非空注释行升序、其次位置」排序，便于优先修补文档最缺的 API。
$sortedViolations = $violations | Sort-Object doc_lines, location

$artifact = [ordered]@{
    schema          = "moonbit-pathfinding.doc-api-guard.v1"
    generated_at    = $generatedAt
    generated_by    = "scripts/doc_api_guard.ps1"
    min_lines       = $MinLines
    src_dir         = (Get-RelPath -FullPath $srcRoot)
    exclude_globs   = $ExcludeGlobs
    scanned_files   = $scannedFiles
    total_apis      = $totalApis
    violation_count = $violations.Count
    status          = $status
    violations      = @($sortedViolations | ForEach-Object {
            [ordered]@{
                api       = $_.api
                location  = $_.location
                doc_lines = $_.doc_lines
            }
        })
}

function Write-DocGuardArtifacts {
    param([object]$Artifact, [string[]]$MarkdownLines)
    try {
        New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
        $json = $Artifact | ConvertTo-Json -Depth 12
        $jsonPath = Join-Path $outRoot ("doc-api-guard-$timestamp.json")
        $latestJson = Join-Path $outRoot "latest-doc-api-guard.json"
        $mdPath = Join-Path $outRoot "latest-doc-api-guard.md"
        [IO.File]::WriteAllText($jsonPath, $json + "`n", $Utf8NoBom)
        [IO.File]::WriteAllText($latestJson, $json + "`n", $Utf8NoBom)
        [IO.File]::WriteAllText($mdPath, ($MarkdownLines -join "`n") + "`n", $Utf8NoBom)
        Write-Host "=== DOC API GUARD ARTIFACTS ===" -ForegroundColor Cyan
        Write-Host $jsonPath
        Write-Host $latestJson
        Write-Host $mdPath
        return $true
    } catch {
        Write-Host "::error::文档门禁报告写出失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Doc API Guard Report")
$md.Add("")
$md.Add("- Generated at: $generatedAt")
$md.Add("- Script: scripts/doc_api_guard.ps1")
$md.Add("- Min non-empty doc lines per Pub_Api: $MinLines")
$md.Add("- Scanned source dir: " + (Get-RelPath -FullPath $srcRoot))
$md.Add("- Exclude globs: " + ($ExcludeGlobs -join ', '))
$md.Add("- Scanned files: $scannedFiles")
$md.Add("- Total Pub_Api: $totalApis")
$md.Add("- Violations (< $MinLines lines): $($violations.Count)")
$md.Add("- Status: $($status.ToUpper())")
$md.Add("")
$md.Add("## 文档不达标的 Pub_Api（API 标识 + 实际非空注释行数 · R21.4）")
$md.Add("")
if ($violations.Count -eq 0) {
    $md.Add("（全部 Pub_Api 文档行数达标）")
} else {
    $md.Add("| API 标识 | 位置 | 非空注释行 | 缺口 |")
    $md.Add("| --- | --- | ---: | ---: |")
    foreach ($v in $sortedViolations) {
        $md.Add(("| {0} | {1} | {2} | {3} |" -f $v.api, $v.location, $v.doc_lines, ($MinLines - $v.doc_lines)))
    }
}
$md.Add("")

$wrote = Write-DocGuardArtifacts -Artifact $artifact -MarkdownLines $md.ToArray()

# ───────────────────── 3. 控制台摘要与门禁退出语义 ─────────────────────

Write-Host ""
Write-Host "--- Summary ---" -ForegroundColor Cyan
Write-Host ("Scanned files : {0}" -f $scannedFiles)
Write-Host ("Total Pub_Api : {0}" -f $totalApis)
Write-Host ("Violations    : {0} (< {1} non-empty doc lines)" -f $violations.Count, $MinLines)

if (-not $wrote) {
    # 报告写出失败按门禁失败处理。
    exit 1
}

if (-not $passed) {
    # R21.4：以「API 标识 + 实际非空注释行数」逐条报告并非零退出。
    Write-Host ("::error::Doc API gate FAILED: {0} 个 Pub_Api 的非空注释行 < {1}" -f $violations.Count, $MinLines) -ForegroundColor Red
    $shown = [Math]::Min($MaxListed, $sortedViolations.Count)
    for ($i = 0; $i -lt $shown; $i++) {
        $v = $sortedViolations[$i]
        Write-Host ("  {0}  [{1}]  doc_lines={2} (需 >= {3})" -f $v.api, $v.location, $v.doc_lines, $MinLines)
    }
    if ($sortedViolations.Count -gt $shown) {
        Write-Host ("  … 其余 {0} 项见报告产物 latest-doc-api-guard.md" -f ($sortedViolations.Count - $shown)) -ForegroundColor Yellow
    }
    exit 1
}

Write-Host ("::notice::Doc API gate PASSED: 全部 {0} 个 Pub_Api 的非空注释行 >= {1}" -f $totalApis, $MinLines) -ForegroundColor Green
exit 0
