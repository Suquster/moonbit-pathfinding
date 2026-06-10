# Native Benchmark Results

- Generated at: `2026-05-31T18:02:46.5953416+08:00`
- Script: `scripts/benchmark_native.ps1`
- MoonBit: `moon 0.1.20260427 (48d7def 2026-04-27)  Feature flags enabled: rr_moon_pkg`
- Target: `wasm-gc`
- Release: `True`
- Warmup: `1`
- Repeats: `3`
- Machine: `Microsoft Windows 10.0.26200`, `X64`, `16` logical processors
- Git revision: `uncommitted`

> Scope: native `moon bench` statistics from `@bench.T` blocks. This is algorithm-level regression evidence, not a cross-language speedup claim.

| Algorithm | Scenario | Median mean us | Mean us | Min us | Max us |
|---|---|---:|---:|---:|---:|
| BFS | 1k-node sparse directed graph, density 1%, query 0 -> 999 | 131.6 | 131.833 | 125.47 | 138.43 |
| Dijkstra | 1k-node sparse weighted directed graph, density 1%, query 0 -> 999 | 648 | 663.73 | 612.49 | 730.7 |
| A* | 32x32 open 4-neighbour grid with Manhattan heuristic | 360.69 | 358.54 | 340.45 | 374.48 |
| Kruskal MST | 1k-node 10k-edge weighted undirected multigraph | 3520 | 3496.667 | 3420 | 3550 |

Raw JSON: `native-wasm-gc-20260531-180246.json` and `latest-native.json`.
