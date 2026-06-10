param(
    [string]$OutDir = "docs\examples"
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

$examples = @(
    [ordered]@{
        name = "maze_solver"
        package = "examples\maze_solver"
        command = @("moon", "run", "examples\maze_solver")
        markers = @(
            "moonbit-pathfinding · maze_solver example",
            "Scenario 1: straight corridor",
            "Solved path (steps = 4):",
            "Scenario 4: unreachable goal (walled-off)",
            "No path from S to G.",
            "Solved path (steps = 41):"
        )
    },
    [ordered]@{
        name = "network_routing"
        package = "examples\network_routing"
        command = @("moon", "run", "examples\network_routing")
        markers = @(
            "moonbit-pathfinding · network_routing example",
            "Router J : (no outgoing links",
            "Route: Router A -> Router D -> Router C -> Router E -> Router I -> Router J",
            "Total latency: 32.5 ms",
            "No route available (destination is unreachable from Router J)."
        )
    },
    [ordered]@{
        name = "eight_puzzle"
        package = "examples\eight_puzzle"
        command = @("moon", "run", "examples\eight_puzzle")
        markers = @(
            "moonbit-pathfinding · eight_puzzle example",
            "Scenario 1: easy (1-step swap)",
            "Solved in 1 moves (A* total cost = 1).",
            "Solved in 6 moves (A* total cost = 6).",
            "Scenario 3: challenging (Manhattan >= 12)",
            "Solved in 20 moves (A* total cost = 20)."
        )
    }
)

function Invoke-Example {
    param([object]$Example)

    $output = New-Object System.Collections.Generic.List[string]
    & $Example.command[0] @($Example.command[1..($Example.command.Length - 1)]) 2>&1 | ForEach-Object {
        $line = [string]$_
        $output.Add($line)
        Write-Host $line
    }
    $text = $output -join "`n"
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($marker in $Example.markers) {
        if (-not $text.Contains($marker)) {
            $missing.Add($marker)
        }
    }
    [ordered]@{
        name = $Example.name
        package = $Example.package
        command = $Example.command
        exit_code = $LASTEXITCODE
        output = $output.ToArray()
        required_markers = $Example.markers
        missing_markers = $missing.ToArray()
        status = if ($LASTEXITCODE -eq 0 -and $missing.Count -eq 0) { "pass" } else { "fail" }
    }
}

$moonVersion = (& moon version 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
$results = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]

foreach ($example in $examples) {
    Write-Host "=== EXAMPLE: $($example.name) ==="
    $result = Invoke-Example -Example $example
    $results.Add($result)
    if ($result.status -ne "pass") {
        $failures.Add("$($example.name) failed: exit=$($result.exit_code), missing=$($result.missing_markers -join ', ')")
    }
}

$status = if ($failures.Count -eq 0) { "pass" } else { "fail" }
$artifact = [ordered]@{
    schema = "moonbit-pathfinding.examples-guard.v1"
    generated_at = $generatedAt
    generated_by = "scripts/examples_guard.ps1"
    moon_version = $moonVersion
    status = $status
    examples = $results.ToArray()
    failures = $failures.ToArray()
}

$json = $artifact | ConvertTo-Json -Depth 12
$jsonPath = Join-Path $outRoot ("examples-run-$timestamp.json")
$latestJsonPath = Join-Path $outRoot "latest-examples-run.json"
[IO.File]::WriteAllText($jsonPath, $json + "`n", [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($latestJsonPath, $json + "`n", [Text.Encoding]::UTF8)

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Examples Guard")
$md.Add("")
$md.Add("- Generated at: $generatedAt")
$md.Add("- Script: scripts\examples_guard.ps1")
$md.Add("- MoonBit: $($moonVersion -replace "`r?`n", " ")")
$md.Add("- Status: $status")
$md.Add("")
$md.Add("| Example | Command | Status | Checked output markers |")
$md.Add("|---|---|---|---:|")
foreach ($result in $results) {
    $cmd = $result.command -join " "
    $md.Add("| $($result.name) | $cmd | $($result.status) | $($result.required_markers.Count) |")
}
if ($failures.Count -gt 0) {
    $md.Add("")
    $md.Add("## Failures")
    foreach ($failure in $failures) {
        $md.Add("- $failure")
    }
}
$md.Add("")
$md.Add("## Expected Workflow Coverage")
$md.Add("")
$md.Add("- maze_solver: BFS on ASCII mazes, including reachable paths and an unreachable goal.")
$md.Add("- network_routing: Dijkstra on a directed latency graph, including a reachable multi-hop route and an unreachable source.")
$md.Add("- eight_puzzle: A* on 3x3 sliding-tile states, including easy, medium, and challenging scenarios.")
$md.Add("")
$md.Add("Raw JSON: $(Split-Path -Leaf $jsonPath) and latest-examples-run.json.")

$mdPath = Join-Path $outRoot "latest-examples-run.md"
[IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", [Text.Encoding]::UTF8)

Write-Host "=== EXAMPLES GUARD ARTIFACTS ==="
Write-Host $jsonPath
Write-Host $latestJsonPath
Write-Host $mdPath

if ($failures.Count -gt 0) {
    throw "Examples guard failed: $($failures -join '; ')"
}
