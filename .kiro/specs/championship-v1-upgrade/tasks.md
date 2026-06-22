# Implementation Plan · 实现任务清单

> Championship_V1_Upgrade（冠军级 v1.0.0 升级）· 全程中文 · 默认 🟣 档位3「业界顶尖（旗舰）」标准
>
> 本清单基于 `requirements.md`（22 条需求 / 6 大方向 + 横切约束 R22）与 `design.md`（架构、组件、数据模型、
> 32 条正确性属性 P1–P32 及属性→PBT 测试文件映射、测试策略、门禁脚本清单）。
> 实现语言为 **MoonBit**（设计已给出具体语言，无需再选）。

## Overview

> 实现方针

- **API 冻结 + bypass（R22.3/22.8）**：只新增包/类型/函数，绝不修改或删除既有公开签名；`.mbti` 只增不减。
- **构建顺序**：先共享/基础包（`@graph` / `@infra_bench` / `@infra_fuzz` / `@docgen`）→ 形式验证扩展（`@proofs`）
  → 差分/模糊测试与覆盖率门禁 → CH/JPS/ALT 生产级 + 基准/压力/Rust 对比 → `@playground` + wasm + GitHub Pages
  → 文档卓越（复杂度表 / ASCII 可视化 / Cookbook / 文档行数门禁）。
- **每个新增公开函数至少一个属性测试**，`holds_for_all` 的 `count ≥ 100`（R22.1）；标签格式
  `// Feature: championship-v1-upgrade, Property {N}: {属性文本}`。
- **横切红线（R22.4/22.5/22.6）**：禁止循环内字符串 `+` 拼接（统一走 `@infra_text.TextBuilder`）、禁止
  `abort`/`todo!`/`unimplemented`/`panic` 占位、禁止字符串模拟结构化数据。
- **每完成一个方向**执行收尾校验：`moon info && moon fmt && moon test` 并在 `wasm-gc`/`js`/`native` 三后端验证一致（R22.2/22.10）。
- 标记 `*` 的子任务为测试类（属性/单元/集成），可在 MVP 阶段跳过；父任务与核心实现任务不得标 `*`。

## Tasks

### 方向 4 · API 人机工程学与类型安全（基础包 `@graph`，优先落地供其余方向复用）

- [x] 1. 创建 `src/graph` 包与结构化错误类型 PathError
  - [x] 1.1 实现 `PathError` 枚举（5 互斥变体）与 `message()`
    - 新建 `src/graph/moon.pkg`（仅依赖 `@core`/`@infra_text`）、`src/graph/path_error.mbt`
    - 定义 `SourceNotFound`/`TargetNotFound`/`Unreachable`/`NegativeCycle`/`InvalidArgument(String)`，`derive(Eq, Show)`
    - `message()` 用 `@infra_text.TextBuilder` 构建非空且变体唯一的诊断串（禁止循环内 `+`）
    - _Requirements: 13.1, 13.7, 22.6_
  - [x] 1.2 编写 PathError 消息属性测试
    - **Property 21: PathError 诊断消息非空且唯一标识变体**
    - 测试文件 `src/graph/prop_patherror_message_test.mbt`，`holds_for_all` count≥100
    - **Validates: Requirements 13.7**

- [x] 2. 实现流式 GraphBuilder 与物化 Graph
  - [x] 2.1 实现 `Graph[N,W]` 与 successor 物化
    - 新建 `src/graph/graph.mbt`：`Graph` 结构 + `successors`/`node_count`/`edge_count`
    - _Requirements: 12.1, 12.7_
  - [x] 2.2 实现 `GraphBuilder[N,W]` 链式构造器
    - 新建 `src/graph/builder.mbt`：`new`/`add_node`/`add_edge`/`add_undirected_edge`/`build`
    - 链式方法返回 self（R12.6）；重复 (源,目标) 末次权重覆盖（R12.3）；空构造器物化为有效空图（R12.4）
    - 节点合法性延迟到 `build` 校验：悬挂边返回 `Err(InvalidArgument)` 且不改累积状态（R12.5）
    - 支持 ≥1e6 节点 / ≤1e7 边的容量目标（R12.1）
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6_
  - [x] 2.3 编写构造器物化完整性属性测试
    - **Property 17: 构造器物化完整性与末次覆盖**
    - `src/graph/prop_builder_materialize_test.mbt`，count≥100
    - **Validates: Requirements 12.2, 12.3**
  - [x] 2.4 编写悬挂边失败属性测试
    - **Property 18: 悬挂边物化失败且状态不变**
    - `src/graph/prop_builder_dangling_test.mbt`，count≥100
    - **Validates: Requirements 12.5**
  - [x] 2.5 编写构造器图等价属性测试
    - **Property 19: 构造器图与等价图查询结果相同**（与既有方式构建的等价图交叉对拍，测试期可依赖 `@directed`）
    - `src/graph/prop_builder_equiv_test.mbt`，count≥100
    - **Validates: Requirements 12.7**

- [x] 3. 实现惰性路径迭代器 LazyPath
  - [x] 3.1 实现 `LazyPath[N]`
    - 新建 `src/graph/lazy_path.mbt`：`from_path`/`empty`/`next`，仅持 O(1) 游标 `pos`（R14.5）
    - 耗尽后 `next()` 幂等返回 `None`；无解 `empty()` 首次 `next()` 即 `None`
    - _Requirements: 14.1, 14.2, 14.3, 14.5, 14.6, 14.7_
  - [x] 3.2 编写惰性迭代等价属性测试
    - **Property 22: 惰性迭代器与物化路径等价**
    - `src/graph/prop_lazypath_equiv_test.mbt`，count≥100
    - **Validates: Requirements 14.1, 14.2, 14.4**
  - [x] 3.3 编写惰性迭代幂等属性测试
    - **Property 23: 惰性迭代器耗尽后幂等**
    - `src/graph/prop_lazypath_idempotent_test.mbt`，count≥100
    - **Validates: Requirements 14.3, 14.7**

- [x] 4. 实现通用图适配器 GraphRepr（邻接矩阵 / 边表 / CSR）
  - [x] 4.1 实现 `GraphRepr[W]`、`CsrGraph[W]` 与统一邻居接口
    - 新建 `src/graph/graph_repr.mbt`：`AdjMatrix`/`EdgeList`/`Csr` 三表 + `neighbors` + `to_successors`
    - `neighbors` 升序、不遗漏不重复、重复调用顺序一致（R15.3）；孤立节点返回空成功结果（R15.4）
    - 越界标识（<0 或 ≥N）返回 `Err(PathError)` 且不改底层图（R15.5）
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5, 15.6_
  - [x] 4.2 编写三表邻居一致属性测试
    - **Property 24: Graph_Adapter 三表邻居一致、升序、确定**
    - `src/graph/prop_adapter_consistency_test.mbt`，count≥100
    - **Validates: Requirements 15.2, 15.3**
  - [x] 4.3 编写越界报错属性测试
    - **Property 25: Graph_Adapter 越界标识报错且底层不变**
    - `src/graph/prop_adapter_oob_test.mbt`，count≥100
    - **Validates: Requirements 15.5**

- [x] 5. 提供返回 PathError 的新增算法入口（bypass，不改既有 Option 签名）
  - [x] 5.1 实现结构化错误入口
    - 新建 `src/graph/typed_query.mbt`：包装既有算法，区分源缺失/目标缺失/不可达/负权环/非法参数映射到对应 `PathError` 变体
    - 源缺失/目标缺失/非法参数三种情形保持输入图不被修改（R13.2/13.3/13.6）
    - 既有返回 `Option` 的算法签名保持冻结（R13.8）
    - _Requirements: 13.2, 13.3, 13.4, 13.5, 13.6, 13.8_
  - [x] 5.2 编写错误变体映射属性测试
    - **Property 20: 错误条件映射到正确 PathError 变体且图不变**
    - `src/graph/prop_patherror_map_test.mbt`，count≥100
    - **Validates: Requirements 13.2, 13.3, 13.4, 13.5, 13.6**

### 方向 2（基础设施部分）· `@infra_bench` 统计量与报告框架

- [x] 6. 创建 `src/infra_bench` 包：统计量、报告与回归判定
  - [x] 6.1 实现 `BenchStats` 与 `compute_stats`
    - 新建 `src/infra_bench/moon.pkg`（依赖 `@core`/`@infra_text`/`@graph`）、`src/infra_bench/stats.mbt`
    - p95 用最近秩、stddev 用总体标准差；空样本返回 `Err(@graph.PathError::InvalidArgument)`
    - _Requirements: 5.2_
  - [x] 6.2 编写统计量数学不变量属性测试
    - **Property 5: 统计量数学不变量（model-based）**
    - `src/infra_bench/prop_stats_test.mbt`，count≥100
    - **Validates: Requirements 5.2**
  - [x] 6.3 实现 `BenchCase`/`BenchReport` 与 MD+JSON 序列化
    - 新建 `src/infra_bench/report.mbt`：记录 moon 版本/后端/机器/生成器/种子/规模/原始计时/统计量
    - `to_markdown`/`to_json` 用 `TextBuilder` 构建（禁止循环内 `+`）
    - _Requirements: 5.1, 5.2_
  - [x] 6.4 编写基准报告往返属性测试
    - **Property 6: 基准报告 JSON 序列化往返一致**
    - `src/infra_bench/prop_report_roundtrip_test.mbt`，count≥100
    - **Validates: Requirements 5.1**
  - [x] 6.5 实现 `RegressionVerdict` 与 `regression_check`
    - 新建 `src/infra_bench/regression.mbt`：按算法名配对，中位回归超容差（默认 10%）标记 `failed`
    - _Requirements: 5.5_
  - [x] 6.6 编写回归判定/加速比口径属性测试
    - **Property 8: 回归判定与加速比口径正确**
    - `src/infra_bench/prop_regression_test.mbt`，count≥100
    - **Validates: Requirements 5.5, 6.6, 6.7**

### 方向 5（基础设施部分）· `@infra_fuzz` 生成器与 shrink

- [x] 7. 创建 `src/infra_fuzz` 包：结构化图生成器、收缩与差分比较器
  - [x] 7.1 实现 `FuzzGraph` 与生成器
    - 新建 `src/infra_fuzz/moon.pkg`（依赖 `@core`/`@infra_pbt`）、`src/infra_fuzz/gen.mbt`
    - `fuzz_graph_gen`（节点 0..10000、边 0..100000，覆盖空/单节点/稠密/稀疏/自环/平行边/多分量，R17.1）
    - `fuzz_graph_nonneg_gen`（仅非负权，供 Dijkstra/BFS/Bellman-Ford 差分，R16.6）
    - 完全由 `@infra_pbt.Rng`（`UInt64` 种子）驱动以保证可复现（R17.7）
    - _Requirements: 16.6, 17.1, 17.7_
  - [x] 7.2 实现反例收缩 `shrink_fuzz_graph`
    - 新建 `src/infra_fuzz/shrink.mbt`：产出「移除任一节点/边」候选集，配合 `@infra_pbt.check_with_shrink`，≤1000 迭代
    - _Requirements: 17.6_
  - [x] 7.3 实现 `approx_eq` 与 `EquivClass`
    - 新建 `src/infra_fuzz/diff.mbt`：1e-9 容差比较 + 等价类枚举（精确枚举，禁止字符串模拟）
    - _Requirements: 16.1, 16.2, 16.3_
  - [x] 7.4 编写生成器确定性属性测试
    - **Property 7: 生成器同种子确定性**
    - `src/infra_fuzz/prop_gen_determinism_test.mbt`，count≥100
    - **Validates: Requirements 5.4, 6.2, 17.7**
  - [x] 7.5 编写收缩局部最小性属性测试
    - **Property 28: 反例收缩的局部最小性**
    - `src/infra_fuzz/prop_shrink_minimal_test.mbt`，count≥100
    - **Validates: Requirements 17.6**

### 方向 6（基础设施部分）· `@docgen` 复杂度表与 ASCII 渲染

- [x] 8. 创建 `src/docgen` 包：Doc_Generator 与 ASCII 可视化
  - [x] 8.1 实现 `AlgoMeta`、`algorithm_metadata()` 与 `complexity_table()`
    - 新建 `src/docgen/moon.pkg`（依赖 `@core`/`@infra_text`/`@graph`）、`src/docgen/complexity.mbt`
    - 静态元数据恰好 33 条（30 经典 + CH/JPS/ALT）；`complexity_table` O(n) 线性、用 `TextBuilder`（禁止循环内 `+`）
    - 任一必填字段为空返回 `Err(PathError)` 且不部分写入（R19.5）
    - _Requirements: 19.1, 19.2, 19.3, 19.4, 19.5_
  - [x] 8.2 编写复杂度表完整唯一属性测试
    - **Property 29: 复杂度表完整、唯一、字段非空**
    - `src/docgen/prop_complexity_complete_test.mbt`，count≥100
    - **Validates: Requirements 19.1, 19.2**
  - [x] 8.3 编写表内容由元数据决定属性测试
    - **Property 30: 复杂度表内容由元数据决定**
    - `src/docgen/prop_complexity_content_test.mbt`，count≥100
    - **Validates: Requirements 19.3**
  - [x] 8.4 编写元数据空字段失败属性测试
    - **Property 31: 元数据缺失/空字段时生成失败且不部分写入**
    - `src/docgen/prop_complexity_invalid_test.mbt`，count≥100
    - **Validates: Requirements 19.5**
  - [x] 8.5 实现 `AsciiGrid` 与 `render_ascii`
    - 新建 `src/docgen/ascii.mbt`：5 互异单字符 `S`/`G`/`#`/`*`/`.` + 图例，用 `TextBuilder`
    - `path` 为空时省略 `*` 并在图例标注「无可行路径」（R20.3）
    - _Requirements: 20.2, 20.3_
  - [x] 8.6 编写 ASCII 渲染字符集属性测试
    - **Property 32: ASCII 渲染字符集与图例约束**
    - `src/docgen/prop_ascii_render_test.mbt`，count≥100
    - **Validates: Requirements 20.2, 20.3**

- [x] 9. 收尾校验 A（基础包）
  - 运行 `moon info`（确认 `.mbti` 只增不减）、`moon fmt`、`moon test`，并在 `wasm-gc`/`js`/`native` 三后端验证一致
  - grep 扫描确认 `@graph`/`@infra_bench`/`@infra_fuzz`/`@docgen` 无 `abort`/`todo!`/`panic` 占位、无循环内 `+` 拼接
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 22.1, 22.2, 22.3, 22.4, 22.5, 22.6, 22.10_

### 方向 3 · 形式验证升级（`@proofs` 扩展）

- [x] 10. 泛化证明谓词组合子（从 BFS/Dijkstra 推广到 30 算法基座）
  - [x] 10.1 实现四类核心谓词与聚合组合子
    - 扩展 `src/proofs/predicates.mbt`：path-validity(A) / cost-consistency(B) / none-witness(C) / bad-witness 拒绝(D)
    - 新增 `shortest_path_post` 统一聚合组合子（泛型 `N : Eq + Hash`、`W : @core.Weight`）
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_
  - [x] 10.2 编写 path-validity 谓词属性测试
    - **Property 11: 路径结构合法性谓词正确判定**
    - `src/proofs/prop_path_validity_test.mbt`，count≥100
    - **Validates: Requirements 9.2, 9.3**
  - [x] 10.3 编写 cost-consistency 谓词属性测试
    - **Property 12: 代价一致性谓词正确判定**
    - `src/proofs/prop_cost_consistency_test.mbt`，count≥100
    - **Validates: Requirements 9.4**
  - [x] 10.4 编写 none-witness 谓词属性测试
    - **Property 13: 无解见证谓词正确判定**
    - `src/proofs/prop_none_witness_test.mbt`，count≥100
    - **Validates: Requirements 9.5**
  - [x] 10.5 编写 bad-witness 拒绝属性测试
    - **Property 14: 坏见证被拒绝且不改输入**
    - `src/proofs/prop_bad_witness_test.mbt`，count≥100
    - **Validates: Requirements 9.6**

- [x] 11. 为 30 种经典算法补齐证明谓词
  - [x] 11.1 最短路族 `*_post` 谓词
    - `src/proofs/` 内为 dijkstra/astar/bellman_ford/dag_sp/bidirectional_*/ida_star/yen/johnson/floyd_warshall 提供 ≥1 谓词（A+B+C）
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_
  - [x] 11.2 无权可达族谓词
    - 为 bfs/bfs_all/dfs/bidirectional_bfs 提供 ≥1 谓词（A+C）
    - _Requirements: 9.1, 9.2, 9.3, 9.5_
  - [x] 11.3 生成树与连通性族谓词
    - 为 kruskal/prim（生成树不变量）、connected_components/tarjan_scc/bridges/condensation（划分/桥定义）提供 ≥1 谓词
    - _Requirements: 9.1, 9.2_
  - [x] 11.4 流与匹配/拓扑/欧拉族谓词
    - 为 edmonds_karp/dinic/min_cut/min_cost_flow/hopcroft_karp/kuhn_munkres/eulerian/topo_sort 提供 ≥1 谓词（最大流=最小割、匹配合法、序合法）
    - _Requirements: 9.1, 9.2_
  - [x] 11.5 编写 30 算法谓词三后端一致性测试
    - 在 `wasm-gc`/`js`/`native` 上对各谓词给出相同通过/失败判定，分歧即门禁失败
    - `src/proofs/prop_predicate_tri_backend_test.mbt`，count≥100
    - **Validates: Requirements 9.1, 9.7, 9.8**

- [x] 12. 循环不变式注解与运行时断言
  - [x] 12.1 实现不变式断言谓词并补注解
    - 新增 `dijkstra_pop_monotonic`、`bfs_level_invariant`；为各经典算法主循环以 `///|` 注释记录不变式（布尔陈述+初始化+保持）
    - _Requirements: 10.1, 10.2, 10.3, 10.4_
  - [x] 12.2 编写循环不变式属性测试
    - **Property 15: 循环不变式成立**（≥100 随机图；违反即报告不变式名与迭代序号）
    - `src/proofs/prop_loop_invariant_test.mbt`，count≥100
    - **Validates: Requirements 10.3, 10.4, 10.5, 10.6**

- [x] 13. Proof_Pipeline 证明报告管线
  - [x] 13.1 实现 `ProofEntry`/`ProofReport` 与序列化/聚合
    - 新建 `src/proofs/proof_report.mbt`：`to_markdown`/`to_json`（逐项语义一致）+ `any_failed`，含 ISO8601 UTC 时间戳与后端列表
    - _Requirements: 11.1, 11.2, 11.3_
  - [x] 13.2 编写证明报告往返/聚合属性测试
    - **Property 16: 证明报告往返一致与失败聚合**
    - `src/proofs/prop_proof_report_test.mbt`，count≥100
    - **Validates: Requirements 11.1, 11.4**
  - [x] 13.3 实现 `scripts/proof_pipeline.ps1` 门禁脚本
    - 扩展既有 `proof_evidence.ps1`：聚合全部谓词测试 → MD+JSON 报告 → 任一失败/写出失败即非零退出；`moon prove` 不可用时记录环境限制并仍输出运行时谓词结果
    - _Requirements: 11.4, 11.5, 11.6_

- [x] 14. 收尾校验 B（形式验证）
  - 运行 `moon info && moon fmt && moon test`，三后端一致；运行 `proof_pipeline.ps1` 确认报告生成与非零退出语义
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 22.2, 22.3, 22.10_

### 方向 5 · 差分测试与模糊测试 + 覆盖率门禁

- [x] 15. 实现跨算法差分验证器 Differential_Tester
  - [x] 15.1 实现等价类差分比对（测试期依赖具体算法包）
    - 新建 `src/infra_fuzz/differential_test.mbt` 支撑逻辑：BFS↔Dijkstra（单位权精确）、Dijkstra↔Bellman-Ford（≤1e-9）、Floyd-Warshall↔Johnson（全对矩阵 ≤1e-9）
    - 不一致即报告图实例、两侧输出、收缩后最小反例与种子（R16.7）
    - _Requirements: 16.1, 16.2, 16.3, 16.4, 16.5, 16.7_
  - [x] 15.2 编写等价类差分属性测试
    - **Property 26: 等价类差分一致**（规模约束 节点 1–500 / 边 0–5000 / 权 0.01–1e6；非负权生成器）
    - `src/infra_fuzz/prop_differential_test.mbt`，count≥100
    - **Validates: Requirements 16.1, 16.2, 16.3, 16.4**

- [x] 16. 实现模糊测试鲁棒性校验
  - [x] 16.1 实现模糊测试驱动逻辑
    - 每算法 ≥100 实例；10s 内终止、返回有效结果或结构化 `PathError`、不崩溃/不死循环；超时标记失败并记录种子；非法参数结构化处理
    - _Requirements: 17.2, 17.3, 17.4, 17.5_
  - [x] 16.2 编写模糊输入鲁棒属性测试
    - **Property 27: 算法对模糊输入鲁棒**
    - `src/infra_fuzz/prop_fuzz_robust_test.mbt`，count≥100
    - **Validates: Requirements 17.1, 17.3, 17.5**

- [x] 17. 实现行覆盖率门禁
  - [x] 17.1 实现 `scripts/coverage_guard.ps1`
    - 扩展 `check_coverage.ps1`：运行 `moon coverage analyze`，被测源排除 `*_test.mbt`/`*_wbtest.mbt`/`benches/`
    - 行覆盖率 <95.0% 以「文件路径+行号」列未覆盖位置并非零退出；记录后端名与数值（≥1 位小数）；解析失败即门禁失败
    - _Requirements: 18.1, 18.2, 18.3, 18.4_

- [x] 18. 收尾校验 C（差分/模糊/覆盖率）
  - 运行 `moon info && moon fmt && moon test`，三后端一致；运行 `coverage_guard.ps1` 确认 ≥95% 门禁
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 18.1, 22.2, 22.10_

### 方向 2 · 性能冠军（CH/JPS/ALT 生产级 + 基准/压力 + Rust 对比）

- [x] 19. CH/JPS/ALT 升级为生产级（bypass 新增，不改既有签名）
  - [x] 19.1 能力补全与新增入口
    - 审查 `src/advanced` 消除任何 `abort`/`todo!`/占位/空壳（R8.1）
    - 以新增方式补强：如 `ch_preprocess_with_order`、`alt_preprocess_with_landmarks`、批量查询入口；既有 `ch_query`/`jps`/`alt_query` 冻结（R8.6）
    - _Requirements: 8.1, 8.6_
  - [x] 19.2 接入 OSM 路网子集解析
    - 解析 `benches/osm` 数据为 `@graph.CsrGraph`；数据缺失时跳过真实路网基准、记录诊断并改用合成数据完成正确性验证（R8.7）
    - _Requirements: 8.7_
  - [x] 19.3 编写前沿算法差分一致属性测试
    - **Property 10: 前沿算法与基准算法差分一致**（CH/ALT vs Dijkstra；JPS vs A\*，≥100 查询，整数精确/浮点 ≤1e-9）
    - `src/advanced/prop_frontier_diff_test.mbt`，count≥100
    - **Validates: Requirements 8.2, 8.3**

- [x] 20. 大规模压力测试
  - [x] 20.1 实现 10k 节点压力测试驱动
    - 新建 `benches/stress_bench`：BFS/Dijkstra/A\* 在 10000 节点图、60s 超时内终止、不改输入图、不 panic；超时标记失败并记录诊断
    - _Requirements: 7.1, 7.4, 7.5_
  - [x] 20.2 编写大规模路径合法/代价属性测试
    - **Property 9: 大规模算法路径合法性与代价一致性**
    - `benches/stress_bench/prop_stress_test.mbt`，count≥100
    - **Validates: Requirements 7.1, 7.2, 7.3, 7.4**

- [x] 21. 基准采集与回归门禁脚本
  - [x] 21.1 扩展基准采集脚本
    - 扩展 `scripts/benchmark_native.ps1`：预热 ≥3、采样 ≥10、MD+JSON 双产物、调用 `@infra_bench.compute_stats`
    - 为 CH/JPS/ALT 记录预处理耗时、≥10 次重复平均/中位查询耗时、样本量、数据集标识与图规模；CH/ALT 记录相对 Dijkstra 中位加速比并断言平均耗时不更高
    - 环境缺凭据/数据集时告警并继续其余基准（R5.6）
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.6, 8.4, 8.5_
  - [x] 21.2 实现 `scripts/regression_guard.ps1`
    - 读基线 JSON 与当前 JSON，调用 `@infra_bench.regression_check`，任一 `failed=true` 非零退出并记录算法/基线中位/当前中位/回归百分比
    - _Requirements: 5.5_

- [x] 22. Rust pathfinding crate 对比报告
  - [x] 22.1 实现 Rust 对比工程与脚本
    - 新建 `bench_rust/`（Cargo，依赖 `pathfinding` crate）+ `scripts/rust_comparison.ps1`
    - 相同 64 位种子产出逐元素相同图与查询（黄金 JSON 交叉校验）；矩阵 BFS/Dijkstra/A\* × {1000,10000,100000} × 出度{4,16} × ≥100 查询
    - ≥5 预热 + ≥30 采样，记录 CPU/OS/两套工具链版本与方法学声明；中位口径加速比；失败/超时(>60s)/不一致用例标注并排除；跨机/跨工具链差异显式标注
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

- [x] 23. 收尾校验 D（性能冠军）
  - 运行 `moon info && moon fmt && moon test`，三后端一致；运行基准+`regression_guard.ps1` 确认回归门禁
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 8.6, 22.2, 22.3, 22.10_

### 方向 1 · WASM Playground 交互可视化

- [x] 24. 创建 `src/playground` 包：逐步执行引擎
  - [x] 24.1 实现 `PlaygroundAlgo`/`StepState`/`StepTrace` 与 `trace_search`set +H
  
    - 新建 `src/playground/moon.pkg`（生产代码仅依赖 `@core`，以控制 wasm 体积）、`src/playground/stepper.mbt`
    - 在 successor 之上运行 BFS/DFS/Dijkstra/A\*/JPS，每步产出结构化单步状态；目标可达回溯 `final_path`，否则 `None`
    - _Requirements: 1.2, 3.1, 3.3, 3.4_
  - [x] 24.2 编写逐步轨迹结构不变量属性测试
    - **Property 1: 逐步轨迹结构不变量**
    - `src/playground/prop_trace_invariant_test.mbt`，count≥100
    - **Validates: Requirements 1.2, 2.6**
  - [x] 24.3 编写终止路径合法/可达一致属性测试
    - **Property 4: 终止路径合法性与可达一致性**
    - `src/playground/prop_final_path_test.mbt`，count≥100
    - **Validates: Requirements 3.3, 3.4**

- [x] 25. 实现网格模型与端点编辑
  - [x] 25.1 实现 `Grid` 与编辑/转换操作
    - 新建 `src/playground/grid.mbt`：`new`/`set_start`/`set_goal`/`toggle_obstacle`/`to_successors`/`manhattan`
    - 编辑为纯变换（值语义）；非法放置（越界/障碍/端点重叠/端点格切障碍）返回 `Err(@graph.PathError)` 且不改入参
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_
  - [x] 25.2 编写合法编辑重算属性测试
    - **Property 2: 合法端点/障碍编辑更新布局并据此重算**
    - `src/playground/prop_edit_recompute_test.mbt`，count≥100
    - **Validates: Requirements 2.1, 2.2, 2.4**
  - [x] 25.3 编写非法编辑被拒属性测试
    - **Property 3: 非法编辑被拒绝且状态不变**
    - `src/playground/prop_edit_reject_test.mbt`，count≥100
    - **Validates: Requirements 2.3, 2.5**

- [x] 26. 实现 wasm-gc 导出层
  - [x] 26.1 实现整型句柄协议导出函数
    - 新建 `src/playground/exports.mbt`：`pg_reset`/`pg_set_*`/`pg_select_algo`/`pg_compute`/`pg_step_*`/`pg_final_path_*`/`pg_last_error`
    - 固定 `N=Int`/`W=Int` 单态化；缺失算法入口返回 `PathError` 码而非静默空（R1.3）；不可达 `pg_final_path_len` 返回 -1（R3.4）
    - _Requirements: 1.2, 1.3, 3.4_
  - [x] 26.2 编写导出层 smoke 单元测试
    - 验证 `pg_compute` 返回步数、各 `pg_step_*` 读取与 `pg_last_error` 错误码映射
    - `src/playground/exports_test.mbt`
    - _Requirements: 1.2, 1.3_

- [ ] 27. 宿主页面、体积门禁与 GitHub Pages 部署
  - [x] 27.1 实现宿主静态资源
    - 新建 `playground/web/index.html`、`app.js`（Canvas 渲染 + 拖拽 + 滚动 1s 帧率计数 + 每 500ms 刷新 fps/网格规模/算法名 + <60fps 警告不中断）、`style.css`
    - 全部同源、不请求外部网络服务（R4.3）
    - _Requirements: 2.1, 2.2, 2.3, 3.5, 3.6, 4.3_
  - [x] 27.2 实现 `scripts/wasm_size_guard.ps1`
    - `moon build --target wasm-gc --release` 后读取 `.wasm` 磁盘字节数，与 `WASM_SIZE_LIMIT=102400` 比较；超限记录实测 vs 上限并非零退出；确定性构建保证重复运行字节数一致
    - _Requirements: 1.1, 1.4, 1.5, 4.5_
  - [x] 27.3 实现 `.github/workflows/pages.yml`
    - 推送主干 → 安装 MoonBit → release 构建 → `wasm_size_guard.ps1`（超限中止保留上一版本）→ 组装 `playground/web` → 发布 Pages，600s 预算内；任一步非零退出即中止并保留上一版本 + 诊断
    - _Requirements: 4.1, 4.2, 4.4, 4.5_

- [-] 28. 收尾校验 E（Playground）
  - 运行 `moon info && moon fmt && moon test`，三后端一致；运行 `wasm_size_guard.ps1` 确认 `.wasm` ≤100KB
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 1.1, 22.2, 22.10_

### 方向 6 · 文档卓越

- [ ] 29. 文档生成接入、ASCII 可视化、Cookbook 与文档门禁
  - [x] 29.1 将复杂度表接入 README
    - 在 `README.mbt.md` 以 `@docgen.complexity_table(@docgen.algorithm_metadata())` 生成 33 行复杂度表（文档即测试）
    - _Requirements: 19.1, 19.2, 19.3_
  - [x] 29.2 为六种算法补 ASCII 可视化文档注释
    - 为 BFS/DFS/Dijkstra/A\*/JPS/CH 每个公开入口在 `Doc_Comment` 提供 ≥1 个 ASCII 示意块（3×3–20×20），可经 `moon test README.mbt.md` 编译运行
    - _Requirements: 20.1, 20.4_
  - [x] 29.3 编写 Cookbook（≥20 用例）
    - 在 `README.mbt.md` 增补覆盖网格寻路/网络路由/任务调度/最大流/匹配五类、每类 ≥1、共 ≥20 个用例，每例含可执行命令与预期输出，三后端均成功
    - _Requirements: 21.1, 21.2, 21.5_
  - [-] 29.4 实现 `scripts/doc_api_guard.ps1`
    - 扩展 `audit_doc.ps1`：扫描全部 `pub` API 的 `///` 注释，非空注释行 <5 即门禁失败并报告 API 标识与实际行数
    - _Requirements: 21.3, 21.4_
  - [-] 29.5 落地 `scripts/examples_guard.ps1` 文档即测试校验
    - 运行 `moon test README.mbt.md`：示例编译失败或结果不符即构建失败并输出定位诊断；Cookbook 输出与预期不符即可重现性校验失败并报告差异位置
    - _Requirements: 20.4, 20.5, 21.6_

- [~] 30. 最终收尾校验（全量门禁）
  - 运行 `moon info`（`.mbti` 只增不减）、`moon fmt`（零差异）、`moon test`（三后端一致）
  - 依次运行 `wasm_size_guard` / `regression_guard` / `proof_pipeline` / `coverage_guard` / `doc_api_guard` / `examples_guard` 全部门禁
  - grep 全量扫描确认无 `abort`/`todo!`/`panic` 占位、无循环内字符串 `+` 拼接、无字符串模拟结构化数据
  - 确认既有测试无一回归、`.mbti` 既有条目零删除零修改
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 22.1, 22.2, 22.3, 22.4, 22.5, 22.6, 22.7, 22.8, 22.9, 22.10_

## Notes

- 标记 `*` 的子任务为测试类（属性/单元/集成），可在 MVP 阶段跳过；父任务与核心实现任务从不标 `*`。
- 每个任务都引用具体需求编号以保证可追溯；属性测试任务显式引用 design.md 的 Property 编号并落实属性→测试文件映射（P1–P32）。
- 32 条正确性属性全部覆盖：P1–P4（@playground）、P5/P6/P8（@infra_bench）、P7/P26/P27/P28（@infra_fuzz）、
  P9（stress）、P10（@advanced）、P11–P16（@proofs）、P17–P25（@graph）、P29–P32（@docgen）。
- 不可属性化的验收标准（wasm 体积、`.mbti` 冻结、文档行数、覆盖率阈值、Pages 部署、CI 时限、UI 帧率/时延）由门禁脚本与
  收尾校验任务承载（SMOKE/INTEGRATION），不强加 PBT。
- 横切约束 R22（API 冻结+bypass、无 O(n²) 拼接、无占位、类型安全、三后端一致）在每个方向收尾校验任务中逐项强制检查。
- 每完成一个方向（任务 9/14/18/23/28/30）执行「`moon info && moon fmt && moon test` + 三后端验证」收尾校验。

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1", "3.1", "4.1", "6.1", "7.1", "7.3", "8.1", "8.5"] },
    { "id": 2, "tasks": ["2.2", "3.2", "3.3", "4.2", "4.3", "6.2", "6.3", "7.2", "7.4", "8.2", "8.3", "8.4", "8.6"] },
    { "id": 3, "tasks": ["2.3", "2.4", "2.5", "5.1", "6.4", "6.5", "7.5"] },
    { "id": 4, "tasks": ["5.2", "6.6"] },
    { "id": 5, "tasks": ["10.1"] },
    { "id": 6, "tasks": ["10.2", "10.3", "10.4", "10.5", "11.1", "11.2", "11.3", "11.4", "12.1", "13.1"] },
    { "id": 7, "tasks": ["11.5", "12.2", "13.2", "13.3"] },
    { "id": 8, "tasks": ["15.1", "16.1"] },
    { "id": 9, "tasks": ["15.2", "16.2", "17.1"] },
    { "id": 10, "tasks": ["19.1", "19.2", "21.1"] },
    { "id": 11, "tasks": ["19.3", "20.1", "21.2", "22.1"] },
    { "id": 12, "tasks": ["20.2"] },
    { "id": 13, "tasks": ["24.1"] },
    { "id": 14, "tasks": ["24.2", "24.3", "25.1"] },
    { "id": 15, "tasks": ["25.2", "25.3", "26.1"] },
    { "id": 16, "tasks": ["26.2", "27.1", "27.2", "27.3"] },
    { "id": 17, "tasks": ["29.1", "29.2", "29.3"] },
    { "id": 18, "tasks": ["29.4", "29.5"] }
  ]
}
```
