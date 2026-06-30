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
- feat(codegen_infra): 类型化 IR 优化遍 + 可验证 pass 流水线（纲领方向三
  T3.1/T3.2）——`const_fold_typed`/`algebraic_simplify_typed`/`strength_reduce_typed`/
  `dce_typed`/`cse_typed` 五个纯函数优化遍，`TypedPass` 枚举 +
  `run_typed_pipeline`/`run_typed_to_fixpoint`/`run_typed_pipeline_validated`
  （每遍前后 `validate_ir` 断言良构、非法输入返回 `Err`）；各遍带「优化前后
  可观察求值等价」PBT（≥100 迭代，以 `interp_ir` 为基准）
  (codegen 类型化优化遍：常量折叠/代数化简/强度削减/DCE/CSE + 验证型流水线 + 等价 PBT)
- feat(logging): 真·OTLP 导出器（纲领方向七 T7.1）——`otlp_export_trace` 按
  OTLP（OpenTelemetry Protocol）protobuf 线缆格式把 span 序列化为可被真实
  collector 接收的 `ExportTraceServiceRequest` 字节，**复用方向九 @serialization
  的 protobuf wire 编码**（`Message`/`FieldEntry`/`FieldValue`/`encode`/
  `double_to_bits`）；新增 `OtlpSpanInput`、`otlp_span`、`otlp_any_value`、
  `otlp_key_value`，字段编号逐一对齐 OTel proto（common/trace/resource v1）；
  属性按键名升序物化保证三后端字节确定；以真实 protobuf 解码器逐字段往返的
  PBT（≥100 迭代）验证
  (logging 真·OTLP 导出器：span→protobuf 线缆字节 + 真解码器往返 PBT)
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

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/v0.0.1
