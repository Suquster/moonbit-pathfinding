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

### Added
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

[Unreleased]: https://github.com/taoyouce/moonbit-pathfinding/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/taoyouce/moonbit-pathfinding/releases/tag/v0.0.1
