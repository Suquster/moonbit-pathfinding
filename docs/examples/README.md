# Example Workflows

This directory stores reproducible output evidence for the runnable examples.

Run all example workflows and verify their expected output markers with:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\examples_guard.ps1
```

The guard executes the examples sequentially to avoid MoonBit build-lock noise,
checks scenario-specific output markers, and writes:

- `latest-examples-run.md`
- `latest-examples-run.json`
- timestamped `examples-run-*.json`

Current workflow coverage:

| Example | Algorithm | User-facing scenario | Negative / edge path |
|---|---|---|---|
| `examples/maze_solver` | BFS | ASCII maze shortest path overlays | Walled-off unreachable goal |
| `examples/network_routing` | Dijkstra | Minimum-latency route over routers A..J | Ingress-only router cannot originate routes |
| `examples/eight_puzzle` | A* | 8-puzzle solution traces | Challenging 20-move state with heuristic report |
