#!/usr/bin/env pwsh
# Local acceptance gate for championship delivery.
#
# Runs the same evidence chain that reviewers care about: type check,
# formatting, full tests, executable README examples, docs build, public API
# doc audit, optional benchmark guard, and coverage gate. Use -SkipCoverage for
# quick inner-loop checks.

[CmdletBinding()]
param(
    [switch]$SkipCoverage,
    [double]$CoverageThreshold = 85.0,
    [switch]$RunBenchmarkGuard,
    [double]$BenchmarkRegressionThreshold = 50.0,
    [switch]$RunNativeBenchmarkGuard,
    [double]$NativeBenchmarkRegressionThreshold = 25.0,
    [switch]$RunProofEvidence,
    [switch]$RunExamplesGuard,
    [switch]$RunReleaseGuard
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root

function Invoke-Gate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string[]]$Command
    )

    Write-Host ""
    Write-Host "=== ACCEPTANCE BEGIN: $Name ===" -ForegroundColor Cyan
    & $Command[0] @($Command[1..($Command.Length - 1)])
    $code = $LASTEXITCODE
    Write-Host "=== ACCEPTANCE END: $Name ExitCode=$code ===" -ForegroundColor Cyan
    if ($code -ne 0) {
        throw "Acceptance gate failed: $Name (ExitCode=$code)"
    }
}

Invoke-Gate -Name 'moon check' -Command @('moon', 'check')
Invoke-Gate -Name 'moon fmt --check' -Command @('moon', 'fmt', '--check')
Invoke-Gate -Name 'moon test' -Command @('moon', 'test')
Invoke-Gate -Name 'moon test README.mbt.md' -Command @('moon', 'test', 'README.mbt.md')
Invoke-Gate -Name 'moon doc' -Command @('moon', 'doc')
Invoke-Gate -Name 'scripts/audit_doc.ps1' -Command @('pwsh', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'scripts\audit_doc.ps1'))

if ($RunBenchmarkGuard) {
    Invoke-Gate -Name 'scripts/benchmark_guard.ps1' -Command @('pwsh', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'scripts\benchmark_guard.ps1'), '-MaxRegressionPercent', "$BenchmarkRegressionThreshold")
} else {
    Write-Host ""
    Write-Host "=== ACCEPTANCE SKIP: benchmark guard skipped; pass -RunBenchmarkGuard to enable ===" -ForegroundColor Yellow
}

if ($RunNativeBenchmarkGuard) {
    Invoke-Gate -Name 'scripts/benchmark_native_guard.ps1' -Command @('pwsh', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'scripts\benchmark_native_guard.ps1'), '-MaxRegressionPercent', "$NativeBenchmarkRegressionThreshold")
} else {
    Write-Host ""
    Write-Host "=== ACCEPTANCE SKIP: native benchmark guard skipped; pass -RunNativeBenchmarkGuard to enable ===" -ForegroundColor Yellow
}

if ($RunProofEvidence) {
    Invoke-Gate -Name 'scripts/proof_evidence.ps1' -Command @('pwsh', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'scripts\proof_evidence.ps1'))
} else {
    Write-Host ""
    Write-Host "=== ACCEPTANCE SKIP: proof evidence skipped; pass -RunProofEvidence to enable ===" -ForegroundColor Yellow
}

if ($RunExamplesGuard) {
    Invoke-Gate -Name 'scripts/examples_guard.ps1' -Command @('pwsh', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'scripts\examples_guard.ps1'))
} else {
    Write-Host ""
    Write-Host "=== ACCEPTANCE SKIP: examples guard skipped; pass -RunExamplesGuard to enable ===" -ForegroundColor Yellow
}

if ($RunReleaseGuard) {
    Invoke-Gate -Name 'scripts/release_guard.ps1' -Command @('pwsh', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'scripts\release_guard.ps1'))
} else {
    Write-Host ""
    Write-Host "=== ACCEPTANCE SKIP: release guard skipped; pass -RunReleaseGuard to enable ===" -ForegroundColor Yellow
}

if (-not $SkipCoverage) {
    $env:COVERAGE_THRESHOLD = "$CoverageThreshold"
    Invoke-Gate -Name 'moon test --enable-coverage' -Command @('moon', 'test', '--enable-coverage')
    Invoke-Gate -Name 'moon coverage analyze' -Command @('moon', 'coverage', 'analyze')
    Invoke-Gate -Name 'moon coverage report -f summary' -Command @('moon', 'coverage', 'report', '-f', 'summary')
    Invoke-Gate -Name 'scripts/check_coverage.ps1' -Command @('pwsh', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'scripts\check_coverage.ps1'), '-Threshold', "$CoverageThreshold")
} else {
    Write-Host ""
    Write-Host "=== ACCEPTANCE SKIP: coverage gates skipped by -SkipCoverage ===" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== ACCEPTANCE PASSED ===" -ForegroundColor Green
