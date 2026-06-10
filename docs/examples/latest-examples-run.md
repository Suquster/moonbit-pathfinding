# Examples Guard

- Generated at: 2026-05-31T18:24:35.1543038+08:00
- Script: scripts\examples_guard.ps1
- MoonBit: moon 0.1.20260427 (48d7def 2026-04-27)  Feature flags enabled: rr_moon_pkg
- Status: pass

| Example | Command | Status | Checked output markers |
|---|---|---|---:|
| maze_solver | moon run examples\maze_solver | pass | 6 |
| network_routing | moon run examples\network_routing | pass | 5 |
| eight_puzzle | moon run examples\eight_puzzle | pass | 6 |

## Expected Workflow Coverage

- maze_solver: BFS on ASCII mazes, including reachable paths and an unreachable goal.
- network_routing: Dijkstra on a directed latency graph, including a reachable multi-hop route and an unreachable source.
- eight_puzzle: A* on 3x3 sliding-tile states, including easy, medium, and challenging scenarios.

Raw JSON: examples-run-20260531-182435.json and latest-examples-run.json.
