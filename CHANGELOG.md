# Changelog

All notable changes to `moonbit-pathfinding` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> 🌐 Language: **English + 简体中文（双语）**
>
> **Bilingual commit-log convention (since v0.3.0, per tasks.md 30.3):**
>
> 为呼应 R23.4 / 任务 30.3，本 CHANGELOG 同时接受英文主句与中文副句。每条
> 变更可以用以下两种风格之一：
>
> 1. **双语行**：英文在前、中文括注补充，例：
>    ```
>    - feat(directed): add Yen's K-shortest paths (新增 Yen K 最短路算法)
>    ```
> 2. **独立中文行（`feat(zh):` 前缀）**：适合中文本地化要点，不触发
>    Conventional Commits 的"type(scope)"解析歧义：
>    ```
>    - feat(directed): add Yen's K-shortest paths
>    - feat(zh): 新增 Yen K 最短路算法，`Err(InvalidK)` 处理 k ≤ 0
>    ```
>
> 约定目的：保证 mooncakes.io / GitHub Release 页面中英文读者都能
> 快速了解变更要点；同时不破坏 Conventional Commits 规范。

---

## [Unreleased]

## [0.0.3] - 2026-06-10

### Added
- feat(directed): add `dijkstra_all` returning a full `ShortestPathTree` with
  `path_to` / `distance_to` queries (新增 dijkstra_all 全表单源最短路树)
- feat(unweighted): add `bfs_all` returning a full `BfsTree` of hop counts
  with path reconstruction (新增 bfs_all 全表 BFS 树)
- feat(directed): add `bellman_ford_paths` — Bellman-Ford with parent
  tracking, returning a `ShortestPathTree` (新增带路径重建的 Bellman-Ford)
- feat(directed): add `floyd_warshall_paths` — all-pairs distances plus
  next-hop table for route reconstruction (新增 Floyd-Warshall 路径重建版)
- feat(directed): add `johnson` all-pairs shortest paths for sparse graphs
  with negative edges, O(V·E·logV) (新增 Johnson 稀疏图全对最短路)
- feat(directed): add `dinic` maximum flow, O(V²·E) (新增 Dinic 最大流)
- feat(directed): add `min_cut` minimum s-t cut extraction via max-flow
  min-cut theorem (新增最小割：割值、割边集与源侧节点集)
- feat(directed): add `min_cost_max_flow` via SPFA successive shortest
  augmenting paths (新增最小费用最大流)
- feat(undirected): add `hopcroft_karp` maximum bipartite matching,
  O(E·√V) (新增 Hopcroft-Karp 二分图最大匹配)
- feat(directed): add `eulerian_path` directed Eulerian path/circuit via
  Hierholzer's algorithm (新增欧拉路径/回路)
- feat(directed): add `condensation` SCC condensation DAG built on
  `tarjan_scc` (新增 SCC 缩点 DAG)
- feat(undirected): add Prim's MST `prim_mst` with adjacency-function API
  (新增 Prim 最小生成树，惰性二叉堆实现，支持非连通图生成森林)
- feat(directed): add DAG shortest path `dag_shortest_path` via
  topological-order relaxation, supporting negative edge weights
  (新增 DAG 最短路，拓扑序松弛，O(V+E)，支持负权边)
- feat(undirected): add `bridges`, `articulation_points`, and the combined
  `bridges_and_articulation_points` (iterative Tarjan, single DFS pass)
  (新增桥与割点检测，迭代式 DFS，深图不爆栈)
- feat(directed): add `bidirectional_dijkstra` meeting-in-the-middle
  shortest path (新增双向 Dijkstra，长路径上约 2 倍加速)
- feat(core): add `PQueue::peek` for O(1) minimum inspection
  (新增优先队列 peek 方法)
- release: add `scripts/release_guard.ps1` to audit mooncakes package metadata,
  `moon package` artifact generation, and local `moon publish --dry-run`
  environment status.
- docs: add reproducible release-readiness artifacts under `docs/release/`.

### Changed
- release: switch the tag workflow from best-effort publish to a hard-gated
  mooncakes release path that requires credentials before creating a GitHub
  Release.
- ci: make missing public API documentation fail the docs job instead of
  downgrading it to a best-effort warning.
- package: use `README.md` as the mooncakes readme and add a homepage URL in
  `moon.mod.json`.
- fix(advanced): correct ALT heuristic triangle-inequality directions
  (admissibility) and add early termination on goal settlement
  (修复 ALT 启发函数可纳性并增加提前终止)
- perf: iterative JPS jump / DSU find, CH edge-difference contraction order,
  Yen adjacency prebuild, dense-array Floyd-Warshall, sparse Edmonds-Karp
  residuals, IDA* O(1) cycle check
  (多项算法性能与健壮性优化)

### Planned for v0.1.0 (Week 1-2)
- DFS, Dijkstra, A*, Bellman-Ford implementations
- CI/CD pipeline (check, fmt, test)
- OSC 2026 registration submitted

### Planned for v0.2.0 (Week 3-4)
- Floyd-Warshall, Kruskal MST, Connected Components
- 3 runnable examples (maze_solver, eight_puzzle, network_routing)
- `README.mbt.md` executable documentation
- OSC 2026 acceptance submission

### Planned for v0.3.0 (Week 5-6)
- 7 advanced algorithms: IDA*, Bidirectional BFS, Yen, Tarjan SCC,
  Topological Sort, Kuhn-Munkres, Edmonds-Karp
- 12 property-based tests via `moonbitlang/quickcheck`
- Performance benchmarks + Chinese/English documentation
- Submission to `moonbitlang/awesome-moonbit`

### Candidate scope for v1.0.0 — Championship Release
- Runtime-checked proof predicates for BFS and Dijkstra, with `moon prove`
  tracked as a toolchain-dependent upgrade path.
- 3 frontier algorithms: **Contraction Hierarchies, JPS, ALT**, backed by
  correctness tests before performance claims.
- Multi-backend consistency CI (wasm-gc / native / js).
- Browser playground decision: either ship a locally reproducible demo with
  recorded frame-rate evidence, or keep it out of the release claim surface.
- Reproducible benchmark artifacts under `benches/results/`, including machine,
  backend, input generator, seed, and raw timing data.
- Fuzz and differential testing against in-repository baseline algorithms.

---

## [0.0.1] - 2026-05-08

### Added
- Initial project layout
- `src/unweighted/bfs.mbt` — Generic BFS with `Eq + Hash` constraint
- Blackbox test suite (4/4 passing) including knight's tour example
- Apache-2.0 license
- "Ported from Rust pathfinding" attribution
- This CHANGELOG

### Developer notes
- BFS implementation prepared with `/// invariant:` comments for future
  `moon prove` integration.
- Project adopts the "successor function" API philosophy from Rust's
  `pathfinding` crate, with independent algorithm implementations.

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/v0.0.1
