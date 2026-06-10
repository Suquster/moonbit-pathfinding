param(
    [string]$PackagePath = "src\proofs",
    [string]$OutDir = "docs\verification"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$packageFullPath = if ([IO.Path]::IsPathRooted($PackagePath)) {
    $PackagePath
} else {
    Join-Path $root $PackagePath
}
$outRoot = if ([IO.Path]::IsPathRooted($OutDir)) {
    $OutDir
} else {
    Join-Path $root $OutDir
}
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToString("o")

function Invoke-Captured {
    param([string[]]$Command)

    $output = New-Object System.Collections.Generic.List[string]
    & $Command[0] @($Command[1..($Command.Length - 1)]) 2>&1 | ForEach-Object {
        $line = [string]$_
        $output.Add($line)
        Write-Host $line
    }
    [ordered]@{
        command = $Command
        exit_code = $LASTEXITCODE
        output = $output.ToArray()
    }
}

Write-Host "=== PROOF EVIDENCE: runtime predicates ==="
$runtime = Invoke-Captured -Command @("moon", "test", $PackagePath)
if ($runtime.exit_code -ne 0) {
    throw "Runtime proof predicate tests failed."
}

Write-Host "=== PROOF EVIDENCE: moon prove tool availability ==="
$proveHelp = Invoke-Captured -Command @("moon", "prove", "--help")

$why3 = Get-Command why3 -ErrorAction SilentlyContinue
$why3Available = $null -ne $why3
$why3Version = ""
if ($why3Available) {
    $why3VersionOutput = (& why3 --version 2>&1 | ForEach-Object { [string]$_ })
    $why3Version = $why3VersionOutput -join "`n"
}

$prove = $null
$proveStatus = "not-run"
if ($proveHelp.exit_code -ne 0) {
    $proveStatus = "moon-prove-unavailable"
} elseif (-not $why3Available) {
    Write-Host "Why3 is not available on PATH; running moon prove once to capture the official diagnostic."
    $prove = Invoke-Captured -Command @("moon", "prove", $PackagePath)
    $proveStatus = "blocked-missing-why3"
} else {
    $prove = Invoke-Captured -Command @("moon", "prove", $PackagePath)
    $proveStatus = if ($prove.exit_code -eq 0) { "passed" } else { "failed" }
}

$moonVersion = (& moon version 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
$artifact = [ordered]@{
    schema = "moonbit-pathfinding.proof-evidence.v1"
    generated_at = $generatedAt
    generated_by = "scripts/proof_evidence.ps1"
    moon_version = $moonVersion
    package_path = $PackagePath
    runtime_predicates = $runtime
    moon_prove_help = $proveHelp
    why3_available = $why3Available
    why3_path = if ($why3Available) { $why3.Source } else { "" }
    why3_version = $why3Version
    moon_prove_status = $proveStatus
    moon_prove = $prove
    interpretation = if ($proveStatus -eq "blocked-missing-why3") {
        "Runtime proof predicates passed, and moon prove exists, but static proof discharge is blocked on this machine because Why3 is missing from PATH."
    } elseif ($proveStatus -eq "passed") {
        "Runtime proof predicates passed and moon prove discharged the selected package."
    } else {
        "See moon_prove_status and captured output for the current proof result."
    }
}

$json = $artifact | ConvertTo-Json -Depth 12
$jsonPath = Join-Path $outRoot ("proof-evidence-$timestamp.json")
$latestJsonPath = Join-Path $outRoot "latest-proof-evidence.json"
[IO.File]::WriteAllText($jsonPath, $json + "`n", [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($latestJsonPath, $json + "`n", [Text.Encoding]::UTF8)

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Proof Evidence")
$md.Add("")
$md.Add("- Generated at: $generatedAt")
$md.Add("- Script: scripts\proof_evidence.ps1")
$md.Add("- Package: $PackagePath")
$md.Add("- MoonBit: $($moonVersion -replace "`r?`n", " ")")
$md.Add("- Runtime predicate tests: ExitCode=$($runtime.exit_code)")
$md.Add("- moon prove --help: ExitCode=$($proveHelp.exit_code)")
$md.Add("- Why3 available: $why3Available")
if ($why3Available) {
    $md.Add("- Why3: $($why3Version -replace "`r?`n", " ")")
}
$md.Add("- moon prove status: $proveStatus")
$md.Add("")
$md.Add("## Interpretation")
$md.Add("")
$md.Add($artifact.interpretation)
$md.Add("")
$md.Add("## Bad-Witness Coverage")
$md.Add("")
$md.Add("- bad witness: bfs_post rejects a non-minimal returned path")
$md.Add("- bad witness: bfs_post rejects None when a goal is reachable")
$md.Add("- bad witness: dijkstra_post rejects invalid edge transition")
$md.Add("- bad witness: dijkstra_post rejects mismatched returned cost")
$md.Add("")
$md.Add("Raw JSON: $(Split-Path -Leaf $jsonPath) and latest-proof-evidence.json.")

$mdPath = Join-Path $outRoot "latest-proof-evidence.md"
[IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", [Text.Encoding]::UTF8)

Write-Host "=== PROOF EVIDENCE ARTIFACTS ==="
Write-Host $jsonPath
Write-Host $latestJsonPath
Write-Host $mdPath

if ($proveStatus -eq "failed") {
    throw "moon prove failed; see proof evidence artifact."
}
