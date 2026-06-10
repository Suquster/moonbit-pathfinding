# Benchmark Guard Report

- Generated at: `2026-05-31T17:54:48.2939320+08:00`
- Baseline: `D:\my\STUDY\university\U_3\down\Competitions\MoonBit国产基础软件开源大赛\moonbit-pathfinding\benches\results\latest-smoke.json`
- Current run: `D:\my\STUDY\university\U_3\down\Competitions\MoonBit国产基础软件开源大赛\moonbit-pathfinding\_build\benchmark-guard\20260531-175448\latest-smoke.json`
- Target: `wasm-gc`
- Release: `True`
- Warmup: `1`
- Iterations: `5`
- Max regression: `50%`
- Status: `pass`

| Algorithm | Baseline median ms | Current median ms | Delta ms | Delta % | Status |
|---|---:|---:|---:|---:|---|
| BFS | 624.144 | 584.669 | -39.475 | -6.325 | pass |
| Dijkstra | 636.03 | 542.705 | -93.325 | -14.673 | pass |
| A* | 599.78 | 572.374 | -27.406 | -4.569 | pass |
| Kruskal MST | 585.356 | 572.2 | -13.156 | -2.248 | pass |

Raw JSON: `guard-wasm-gc-20260531-175448.json` and `latest-guard.json`.
