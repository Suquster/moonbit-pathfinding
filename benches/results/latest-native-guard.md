# Native Benchmark Guard Report

- Generated at: `2026-05-31T18:06:56.8452293+08:00`
- Baseline: `D:\my\STUDY\university\U_3\down\Competitions\MoonBit国产基础软件开源大赛\moonbit-pathfinding\benches\results\latest-native.json`
- Current run: `D:\my\STUDY\university\U_3\down\Competitions\MoonBit国产基础软件开源大赛\moonbit-pathfinding\_build\native-benchmark-guard\20260531-180656\latest-native.json`
- Target: `wasm-gc`
- Release: `True`
- Warmup: `1`
- Repeats: `3`
- Max regression: `25%`
- Status: `pass`

| Algorithm | Baseline median us | Current median us | Delta us | Delta % | Status |
|---|---:|---:|---:|---:|---|
| BFS | 131.6 | 143.53 | 11.93 | 9.065 | pass |
| Dijkstra | 648 | 657.63 | 9.63 | 1.486 | pass |
| A* | 360.69 | 393.33 | 32.64 | 9.049 | pass |
| Kruskal MST | 3520 | 3600 | 80 | 2.273 | pass |

Raw JSON: `native-guard-wasm-gc-20260531-180656.json` and `latest-native-guard.json`.
