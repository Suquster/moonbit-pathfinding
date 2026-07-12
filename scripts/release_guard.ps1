param(
    [string]$OutDir = "docs\release"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = if ([IO.Path]::IsPathRooted($OutDir)) {
    $OutDir
} else {
    Join-Path $root $OutDir
}
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$generatedAt = (Get-Date).ToString("o")
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Add-Warning {
    param([string]$Message)
    $warnings.Add($Message)
}

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

$modPath = Join-Path $root "moon.mod"
$readmePath = Join-Path $root "README.md"
$readmeMbtPath = Join-Path $root "README.mbt.md"
$readmeZhPath = Join-Path $root "README.zh-CN.md"
$licensePath = Join-Path $root "LICENSE"
$changelogPath = Join-Path $root "CHANGELOG.md"
$releaseWorkflowPath = Join-Path $root ".github\workflows\release.yml"

# moon.mod 为新版 `key = "value"` 文本格式（非 JSON），这里提取发布元数据。
$modText = Get-Content -LiteralPath $modPath -Encoding UTF8 -Raw
function Get-ModField {
    param([string]$Name)
    $m = [regex]::Match($modText, ('(?m)^' + $Name + '\s*=\s*"(?<v>[^"]*)"'))
    if ($m.Success) { return $m.Groups['v'].Value }
    return ""
}
$mod = [ordered]@{}
$mod.name = Get-ModField "name"
$mod.version = Get-ModField "version"
$mod.readme = Get-ModField "readme"
$mod.repository = Get-ModField "repository"
$mod.license = Get-ModField "license"
$mod.description = Get-ModField "description"
$homepageMatch = [regex]::Match($modText, 'homepage:\s*"(?<v>[^"]*)"')
$mod.homepage = if ($homepageMatch.Success) { $homepageMatch.Groups['v'].Value } else { "" }
$keywordsMatch = [regex]::Match($modText, '(?s)keywords\s*=\s*\[(?<body>.*?)\]')
$mod.keywords = if ($keywordsMatch.Success) {
    @([regex]::Matches($keywordsMatch.Groups['body'].Value, '"[^"]+"') | ForEach-Object { $_.Value.Trim('"') })
} else { @() }
$checks = [ordered]@{}

$checks.module_name = $mod.name -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
if (-not $checks.module_name) { Add-Failure "moon.mod name must look like owner/package." }

$checks.version_semver = $mod.version -match '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$'
if (-not $checks.version_semver) { Add-Failure "moon.mod version must be SemVer." }

$checks.readme_exists = -not [string]::IsNullOrWhiteSpace($mod.readme) -and (Test-Path -LiteralPath (Join-Path $root $mod.readme))
if (-not $checks.readme_exists) { Add-Failure "moon.mod readme must point to an existing file." }

$checks.repository_url = $mod.repository -match '^https://github\.com/[^/]+/[^/]+/?$'
if (-not $checks.repository_url) { Add-Failure "moon.mod repository must be a GitHub HTTPS URL." }

$checks.homepage_url = $mod.homepage -match '^https://'
if (-not $checks.homepage_url) { Add-Failure "moon.mod homepage must be present and HTTPS." }

$checks.license_spdx = $mod.license -eq "Apache-2.0"
if (-not $checks.license_spdx) { Add-Failure "moon.mod license must be Apache-2.0." }

$checks.keywords = $mod.keywords.Count -ge 8
if (-not $checks.keywords) { Add-Failure "moon.mod should include at least 8 useful keywords." }

$checks.description = -not [string]::IsNullOrWhiteSpace($mod.description) -and $mod.description.Length -ge 80
if (-not $checks.description) { Add-Failure "moon.mod description should be specific and at least 80 characters." }

$licenseText = Get-Content -LiteralPath $licensePath -Encoding UTF8 -Raw
$checks.license_file = $licenseText.Contains("Apache License") -and $licenseText.Contains("Version 2.0")
if (-not $checks.license_file) { Add-Failure "LICENSE must contain Apache License Version 2.0 text." }

$changelogText = Get-Content -LiteralPath $changelogPath -Encoding UTF8 -Raw
$checks.changelog_unreleased = $changelogText.Contains("## [Unreleased]")
if (-not $checks.changelog_unreleased) { Add-Failure "CHANGELOG.md must contain an [Unreleased] section." }

$checks.changelog_current_version = $changelogText.Contains("## [$($mod.version)]")
if (-not $checks.changelog_current_version) { Add-Warning "CHANGELOG.md does not contain a released section matching moon.mod version $($mod.version)." }

$readmeText = Get-Content -LiteralPath $readmePath -Encoding UTF8 -Raw
$readmeZhText = Get-Content -LiteralPath $readmeZhPath -Encoding UTF8 -Raw
$checks.readme_badge_version = $readmeText.Contains("version-v$($mod.version)") -and $readmeZhText.Contains("version-v$($mod.version)")
if (-not $checks.readme_badge_version) { Add-Failure "README version badges must match moon.mod version." }

$checks.readme_mbt_exists = Test-Path -LiteralPath $readmeMbtPath
if (-not $checks.readme_mbt_exists) { Add-Failure "README.mbt.md executable documentation must exist." }

$workflowText = Get-Content -LiteralPath $releaseWorkflowPath -Encoding UTF8 -Raw
$checks.release_workflow_no_continue_on_error = -not $workflowText.Contains("continue-on-error: true")
if (-not $checks.release_workflow_no_continue_on_error) { Add-Failure "Release workflow must not allow moon publish to continue on error." }

$checks.release_workflow_no_publish_true = -not $workflowText.Contains("moon publish || true")
if (-not $checks.release_workflow_no_publish_true) { Add-Failure "Release workflow must not mask moon publish failure with || true." }

$checks.release_workflow_credentials = $workflowText.Contains("MOONCAKES_CREDENTIALS_JSON") -and $workflowText.Contains("MOONCAKES_USERNAME") -and $workflowText.Contains("MOONCAKES_TOKEN")
if (-not $checks.release_workflow_credentials) { Add-Failure "Release workflow must document/configure mooncakes credential materialization." }

Write-Host "=== RELEASE GUARD: moon package ==="
$package = Invoke-Captured -Command @("moon", "package")
if ($package.exit_code -ne 0) {
    Add-Failure "moon package failed with exit code $($package.exit_code)."
}

$packageOutput = $package.output -join "`n"
$packagePath = ""
$m = [regex]::Match($packageOutput, 'Package to (?<path>.+?\.zip)')
if ($m.Success) {
    $packagePath = $m.Groups["path"].Value.Trim()
}
$checks.package_artifact = -not [string]::IsNullOrWhiteSpace($packagePath) -and (Test-Path -LiteralPath $packagePath)
if (-not $checks.package_artifact) {
    Add-Failure "moon package did not produce a readable .zip artifact."
}

Write-Host "=== RELEASE GUARD: moon publish --dry-run ==="
$publishDryRun = Invoke-Captured -Command @("moon", "publish", "--dry-run")
$publishOutput = $publishDryRun.output -join "`n"
$publishStatus = if ($publishDryRun.exit_code -eq 0) {
    "dry-run-passed"
} elseif ($publishOutput.Contains("credentials") -or $publishOutput.Contains("login")) {
    Add-Warning "moon publish --dry-run is blocked locally by missing mooncakes credentials; run moon login or configure CI secrets before publishing."
    "blocked-missing-credentials"
} else {
    Add-Failure "moon publish --dry-run failed for a reason other than missing credentials."
    "failed"
}

$status = if ($failures.Count -eq 0) {
    if ($warnings.Count -eq 0) { "pass" } else { "pass-with-warnings" }
} else {
    "fail"
}

$moonVersion = (& moon version 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
$artifact = [ordered]@{
    schema = "moonbit-pathfinding.release-readiness.v1"
    generated_at = $generatedAt
    generated_by = "scripts/release_guard.ps1"
    moon_version = $moonVersion
    status = $status
    module = [ordered]@{
        name = $mod.name
        version = $mod.version
        readme = $mod.readme
        repository = $mod.repository
        homepage = $mod.homepage
        license = $mod.license
    }
    checks = $checks
    package_path = $packagePath
    package = $package
    publish_dry_run_status = $publishStatus
    publish_dry_run = $publishDryRun
    failures = $failures.ToArray()
    warnings = $warnings.ToArray()
}

$json = $artifact | ConvertTo-Json -Depth 12
$jsonPath = Join-Path $outRoot ("release-readiness-$timestamp.json")
$latestJsonPath = Join-Path $outRoot "latest-release-readiness.json"
[IO.File]::WriteAllText($jsonPath, $json + "`n", [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($latestJsonPath, $json + "`n", [Text.Encoding]::UTF8)

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Release Readiness")
$md.Add("")
$md.Add("- Generated at: $generatedAt")
$md.Add("- Script: scripts\release_guard.ps1")
$md.Add("- MoonBit: $($moonVersion -replace "`r?`n", " ")")
$md.Add("- Module: $($mod.name)@$($mod.version)")
$md.Add("- Status: $status")
$md.Add("- Package artifact: $packagePath")
$md.Add("- moon publish --dry-run: $publishStatus")
$md.Add("")
$md.Add("## Checklist")
$md.Add("")
$md.Add("| Check | Status |")
$md.Add("|---|---|")
foreach ($key in $checks.Keys) {
    $md.Add("| $key | $($checks[$key]) |")
}
if ($warnings.Count -gt 0) {
    $md.Add("")
    $md.Add("## Warnings")
    foreach ($warning in $warnings) {
        $md.Add("- $warning")
    }
}
if ($failures.Count -gt 0) {
    $md.Add("")
    $md.Add("## Failures")
    foreach ($failure in $failures) {
        $md.Add("- $failure")
    }
}
$md.Add("")
$md.Add("Raw JSON: $(Split-Path -Leaf $jsonPath) and latest-release-readiness.json.")

$mdPath = Join-Path $outRoot "latest-release-readiness.md"
[IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", [Text.Encoding]::UTF8)

Write-Host "=== RELEASE GUARD ARTIFACTS ==="
Write-Host $jsonPath
Write-Host $latestJsonPath
Write-Host $mdPath

if ($failures.Count -gt 0) {
    throw "Release guard failed: $($failures -join '; ')"
}
