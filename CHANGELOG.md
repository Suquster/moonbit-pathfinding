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

- feat(bench): four new INFRA native benchmark packages —
  `benches/infra_time_bench`（ISO 8601 解析/格式化、strftime、civil 换算、
  POSIX TZ 偏移）、`benches/infra_resilience_bench`（熔断器/令牌桶/滑动
  窗口/AIMD/带抖动退避）、`benches/infra_cli_bench`（解析/校验/拼写建议/
  help 生成）、`benches/infra_pbt_bench`（属性检查/失败缩小/加权生成/
  种子化图 fuzz），measured native results archived in
  `benches/results/infra-time-resilience-cli-pbt-native-2026-07-12.md`
- feat(scripts): `scripts/demos_guard.sh` — runs all 20
  `moon run examples/...` demos and checks deterministic output markers,
  wired into `scripts/acceptance.sh` as gate 6; evidence written to
  `docs/examples/latest-examples-run.md` / `.json`
  （20 个 demo 输出快照守卫接入验收门禁）

### Fixed

- fix(release): write mooncakes credentials without UTF-8 BOM in the release
  workflow and make `moon publish` idempotent on rerun
  （修复 release 工作流凭据 BOM 解析失败；发版幂等化）

## [0.2.0] - 2026-07-12

### Added — INFRA flagship demos, tutorials & performance evidence（INFRA 旗舰 demo、教程与性能证据）

- feat(examples): second demo batch — `actor_worker_pool` (supervised
  restart / routing / backpressure), `build_pipeline` (wave scheduling /
  incremental rebuild / auto-bisect), `serialization_studio` (typed wire +
  JSON round-trips / breaking-change detection), `dst_explorer`
  (deterministic replay / DPOR / linearizability), `config_diff_ops`
  (TOML/INI + diff3 + semver)（第二批 5 个 INFRA 端到端 demo）
- feat(examples): third demo batch — `hash_integrity`（SHA-2/3、BLAKE2b、
  HMAC 防篡改、HKDF/PBKDF2、流式 == 一次性、xxHash 分片）、
  `compress_workbench`（DEFLATE/zlib/gzip/zstd/LZ4 压缩率对比、字典压缩、
  损坏归档拒绝）、`time_scheduler`（RFC 3339/2822、POSIX TZ 夏令时、
  时间轮、工作窃取调度）、`resilience_gateway`（退避重试、熔断器、
  令牌桶/滑动窗口、隔板、AIMD、对冲请求）、`cli_devtool`（类型化校验、
  拼写建议、help/补全生成）、`observability_kit`（HDR 直方图、DDSketch、
  span 追踪）、`text_editor_core`（rope/piece table、Myers diff、
  LRU/布隆/roaring）、`parser_playground`（表达式求值、JSON 错误恢复、
  增量解析）、`pbt_fuzz_lab`（属性缩小、往返律、种子化图 fuzz）——
  20 directions now ship runnable end-to-end demos
- feat(bench): `benches/infra_hash_bench` (crypto digests vs fast hashes,
  streaming == one-shot smoke) and `benches/infra_compress_bench`
  (deflate/zstd/lz4 round-trip throughput, lossless smoke); native results
  archived in `benches/results/infra-hash-compress-native-2026-07-12.md`
  （新增哈希/压缩原生基准与结果归档）
- docs(tutorials): hands-on handbook for every direction —
  `docs/tutorials/README.md` (EN) and `docs/zh/tutorials.md` (中文)，
  key APIs + runnable snippets + demo mapping
- docs(readme): bilingual demo overview tables now list all 20 runnable
  example workflows（README 中英 demo 总览表补齐 20 条）

## [0.1.0] - 2026-07-12

### Added — Real OSM Playground & ecosystem（真实 OSM Playground 与生态）

- feat(playground): real OSM road-network mode — `pg_osm_*` integer-handle
  wasm export layer (reset/add_edge/build/route/path/cost/settled) running
  unidirectional and bidirectional Dijkstra on a CSR graph, live at
  <https://Suquster.github.io/moonbit-pathfinding/osm.html> with the Xiamen
  driving network (125,639 nodes / 215,947 edges, OpenStreetMap ©
  contributors, ODbL 1.0) (新增真实 OSM 路网模式：厦门驾车路网在浏览器内
  点选起终点，单向 vs 双向 Dijkstra 实时对比 settle 节点数与耗时，代价交叉校验)
- feat(playground): `scripts/build_playground_osm.py` — reproducible network
  artifact builder from the cached Overpass response (largest SCC, haversine
  decimeter weights) (可复现的 OSM 路网预处理脚本)
- feat(wit): 9 new typed component-model exports (`pg-osm-*`) in
  `wit/playground.wit`, gated end-to-end under wasmtime by
  `scripts/wit_gate.sh` (WIT 组件模型新增 9 个类型化导出，wasmtime 逐函数门禁)
- docs: formal 18/18 same-algorithm Rust benchmark chart embedded in both
  READMEs; downstream consumers
  [moonbit-pathfinding-demo](https://github.com/Suquster/moonbit-pathfinding-demo)
  and [moonbit-maze](https://github.com/Suquster/moonbit-maze); 5-minute
  defense script; community article draft (正式同算法 benchmark 图表、
  两个下游消费仓、答辩台本与社区文章草稿)

### Fixed — Pre-acceptance feedback（预验收反馈整改）

- fix(directed): make ALT farthest-first landmark selection prioritize
  uncovered disconnected components, prevent repeated landmarks, and accept
  empty graphs without trapping (ALT 地标选择优先覆盖非连通分量、避免重复地标，
  并为零节点图提供安全空预处理结果)
- perf(actor): `run_until_idle` unseeded fast path — advance-cursor scheduling
  replaces the per-step full-table scan (`settle_stops` + `pick_ready`), making
  message processing amortised O(1) per message while preserving the exact
  processing order of the step-by-step semantics; cross-cell events
  (Terminated delivery / supervision handling) set `cross_dirty` and rescan
  from index 0 (无种子 `run_until_idle` 推进游标快路径：每消息摊销 O(1)，与逐
  `step` 处理序列完全一致；修复 `massive_actor_scheduling` 基准 27× 回归——
  native 109.9ms → 2.5ms，回归 guard 恢复 PASS)
- fix(build): remove the deprecated `moon.mod.json` (superseded by `moon.mod`),
  eliminating the "Both moon.mod.json and moon.mod exist" warning
  (删除废弃 `moon.mod.json`，消除新工具链重复配置告警)
- ci: add the required deny-warn acceptance gates via `scripts/acceptance.sh` —
  probes toolchain support for `moon fmt --deny-warn` / `moon info --deny-warn`
  and falls back to equivalent semantics (`moon fmt --check`, `moon info` +
  `.mbti` drift gate) plus `moon check --deny-warn` on newer toolchains where
  the flag moved to check/test (CI 纳入验收要求的 deny-warn 两个过程，跨工具链
  版本兼容执行，并叠加接口无漂移门禁)

### Fixed — Playground goes live（Playground 上线）

- fix(playground): declare the parent library as a `path` dependency in
  `playground/moon.mod.json` so the bridge module builds standalone; drop the
  empty `playground/src` package (修复 playground 独立 module 的依赖解析，桥接层
  可独立 `moon build`/`moon test`)
- fix(playground): make the "unreachable goal" sentinel test wall off the
  diagonal too, so the goal is unreachable under 8-neighbour JPS as well as
  4-neighbour BFS/Dijkstra/A* (对角线一并封墙，使目标在 8 邻域 JPS 下同样不可达)
- fix(ci): `pages.yml` now builds the `src/playground` pg_* export layer from
  the repository root and assembles `playground.wasm` from
  `_build/wasm-gc/release/build/src/playground/` (Pages 流水线改为根 module 构建
  并组装正确的 pg_* 导出层产物)
- docs(readme): Playground badge planned → live; rewrite the Playground section
  in both languages with the live-demo URL and offline instructions
  (README 徽章与 Playground 章节转为 live 状态，双语同步)

### Added — Production Hardening（生产级加固，仅新增 / 不破坏既有 API）

> 本批次将 10 个基础设施方向包整体提升至「业界顶尖（旗舰）」生产级质量。
> 全程遵循 **bypass 原则**：所有新能力以新增类型/函数/方法实现，未修改或删除任何
> 加固前既有公开签名；11 个变更的 `.mbti` 经审计**只增不减**（422 行纯新增、0 删除）；
> 未改动任何加固前既有测试（301 个既有测试文件零改动，仅新增测试文件）。
> 所有属性测试 **≥100 迭代**，关键路径覆盖 **wasm-gc / js / native 三后端一致**。

- feat(infra_text): 新增共享高效文本构建工具 `TextBuilder`（`push_char`/`push_str`/
  `build`/`reset` 等），以 `Array[Char]` 缓冲 + 分块 `join` 替代 O(n²) 字符串拼接
  (新增共享文本构建器，供各方向复用)
- feat(infra_pbt): PBT 框架增强——生成器组合子 `one_of`/`frequency`/`sized`、
  反例收缩 `shrink`（`Shrinkable`/`check_with_shrink`/`CheckResult`）、统计收集
  `Stats`/`holds_for_all_stats` (属性测试框架补齐 shrink/组合子/统计)
- feat(logging): 新增 Sink 层（`SinkTarget`/`SinkHandle`，含 `console`/`callback`/
  `buffered`）与运行时调级 `set_level`，落地真实 I/O 输出 (日志 Sink 层与运行时调级)
- feat(build_tool): 新增动作执行框架——`Action`/`Executor` trait/`DryRunExecutor`/
  `CallbackExecutor`/`ParallelSchedule`/`BuildLog`/`run_actions`，支持并行波次调度与
  指纹增量判定 (构建工具动作执行/并行调度/增量构建日志)
- feat(regex_engine): 新增 Unicode General Category 支持、`CharSet` 二分查询、
  实用 API（`find_at`/`split_n`/`replace_fn`）与 Hybrid 匹配器（缓存上限 + NFA 回退）
  (正则 Unicode 类别 / Hybrid 执行 / 实用 API)
- feat(parser_combinator): 新增错误恢复组合子 `with_recovery` 与有界 packrat
  缓存 `BoundedCache`（LRU 淘汰），保持增量解析与一次性解析等价
  (解析器错误恢复 / 有界 packrat 缓存)
- feat(serialization): 新增 proto3 service/rpc/import 解析与打印、结构化代码生成
  AST（`CodeNode`/`render_code`）、`Any` 类型与流式编解码（`ByteSink`/`ByteSource`/
  `encode_to`/`decode_from`） (序列化 service-rpc-import / 结构化代码生成 / Any / 流式)
- feat(codegen_infra): 新增类型化 IR（`Operand`/`TypedInstr`/`TypedBlock`/
  `TypedFunction`，替代字符串化指令）、IR 验证器（SSA/类型/控制流）与解释器
  (代码生成类型化 IR / 验证器 / 解释器)
- feat(dst): 新增可执行任务体（`SimContext`/`ExecutableTask`/`run_executable`）与
  `eventually` 最终性断言，复用确定性 `World`/`NetworkSim`/`SimClock`
  (确定性仿真可执行任务 / eventually)
- feat(mini_compiler): 新增 match/元组/列表特性（`Pattern`/`ExprX`/`check_x`/`eval_x`）
  与字节码 `peephole`/`tco` 优化，类型错误含 expected/actual
  (迷你编译器模式匹配 / peephole / 尾调用优化)
- feat(lsp_server): 新增 JSON-RPC 成帧/校验（`encode_frame`/`decode_frame`，
  兼容 `\r\n` 与 `\n`；`validate_jsonrpc`/`FrameError`/`JsonRpcError`）与 O(N)
  增量文档同步 `apply_incremental` (LSP 成帧 / 校验 / O(N) 增量同步)
- perf: 消除 serialization / build_tool / regex_engine / parser_combinator /
  logging 五个方向的 O(n²) 循环字符串拼接，统一改用 `infra_text.TextBuilder`，
  并以逐字符等价性测试锁定输出不变 (消除五方向 O(n²) 拼接，输出逐字符等价)

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

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/v0.0.1
