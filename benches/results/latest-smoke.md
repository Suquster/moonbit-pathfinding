# Benchmark Smoke Results

- Generated at: `2026-05-31T17:48:41.1748336+08:00`
- Script: `scripts/benchmark_smoke.ps1`
- MoonBit: `moon 0.1.20260427 (48d7def 2026-04-27)  Feature flags enabled: rr_moon_pkg`
- Target: `wasm-gc`
- Release: `True`
- Warmup: `1`
- Iterations: `5`
- Machine: `Microsoft Windows 10.0.26200`, `X64`, `16` logical processors
- Git revision: `uncommitted`

> Scope: end-to-end `moon test -p ...` package timing. These results are reproducible smoke evidence, not a cross-language speedup claim.

| Algorithm | Scenario | Min ms | Median ms | Mean ms | Max ms |
|---|---|---:|---:|---:|---:|
| BFS | 1k-node sparse directed graph, density 1%, query 0 -> 999 | 522.079 | 624.144 | 640.74 | 788.109 |
| Dijkstra | 1k-node sparse weighted directed graph, density 1%, query 0 -> 999 | 580.606 | 636.03 | 627.059 | 663.09 |
| A* | 32x32 open 4-neighbour grid with Manhattan heuristic, query (0,0) -> (31,31) | 557.758 | 599.78 | 595.297 | 614.138 |
| Kruskal MST | 1k-node 10k-edge weighted undirected multigraph | 574.714 | 585.356 | 603.77 | 681.886 |

Raw JSON: `smoke-wasm-gc-20260531-174841.json` and `latest-smoke.json`.
