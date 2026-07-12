# moonbit-pathfinding · 中文版

> 🌐 Language: **简体中文** · [English](./README.md)

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](./LICENSE)
[![CI](https://github.com/Suquster/moonbit-pathfinding/actions/workflows/ci.yml/badge.svg)](https://github.com/Suquster/moonbit-pathfinding/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-v0.2.0-blue)](./CHANGELOG.md)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-Suquster%2Fmoonbit--pathfinding-orange)](https://mooncakes.io/docs/Suquster/moonbit-pathfinding)
[![Playground](https://img.shields.io/badge/Playground-live-brightgreen)](https://suquster.github.io/moonbit-pathfinding/)
[![Executable contracts](https://img.shields.io/badge/proof_predicates-runtime_checked-yellow)](#formal-verification)
[![OSC 2026](https://img.shields.io/badge/OSC_2026-participant-brightgreen)](https://moonbitlang.github.io/OSC2026/)

> **面向 MoonBit 的严谨工程化路径规划与图算法库。**
>
> 面向 **MoonBit** 的生产级路径规划与图算法库，核心亮点：
> **可执行 proof predicates**、**可执行 Markdown 文档**、
> **四后端一致性** (wasm-gc / native / js / wasm) 与 **WASI 交付门禁**、**一键验收脚本**。

---

## 为什么是这个项目（三个故事）

1. **填补生态空白** — 面向 MoonBit 的生产级寻路 / 图算法库：38+ 算法
   （BFS → A\* → JPS → ALT → CH → Hub Labels → PHAST）+ 20 个 INFRA 方向，
   已发布 [mooncakes.io](https://mooncakes.io/docs/Suquster/moonbit-pathfinding)，
   并提供[打开即玩的浏览器 playground](https://suquster.github.io/moonbit-pathfinding/)。
2. **生态工程标杆** — 3339 个测试跨四后端（wasm-gc / native / js / wasm）、
   可执行 proof predicates、可执行 README（`moon test README.mbt.md`）、
   DST + 差分 PBT、零警告 `--deny-warn` CI 门禁，以及已发布的
   [对标 Rust `pathfinding` crate 正面对比](./benches/results/latest-rust-comparison.md)
   （同算法中位加速 ≈2.7×；双向变体单独列报）。
3. **真实数据端到端** — 真实 OSM 路网（北京 / 厦门）驱动点到点谱系
   （双向 Dijkstra → ALT → CH → HL，最高 13279×），全量对拍一致性校验，
   全部可由入库脚本与 artifact 复现。

**下游使用**：两个独立仓库以常规依赖方式消费已发布的 mooncakes.io 包
（`moon add Suquster/moonbit-pathfinding`），各自自带测试与 CI：
[`Suquster/moonbit-pathfinding-demo`](https://github.com/Suquster/moonbit-pathfinding-demo)
（仓库机器人路径规划器）与
[`Suquster/moonbit-maze`](https://github.com/Suquster/moonbit-maze)
（完美迷宫生成 + A\* 求解 CLI，含 Dijkstra 交叉校验）。

---

## 项目溯源 · Ported from

本库 **API 设计哲学** 参考自 Rust 社区的
[`pathfinding` crate](https://github.com/evenfurther/pathfinding)（v4.15.0，
MIT OR Apache-2.0 双许可）。核心借鉴：

- **"后继函数" 极简设计** — 算法不绑定图结构，用户通过
  `fn(N) -> Array[N]` 或 `fn(N) -> Array[(N, W)]` 定义邻居关系
- **泛型节点类型** — `N : Eq + Hash` 即可，无需 `Ord` 约束
- **返回类型风格** — `Option[(Array[N], W)]` 表达"可能无解的带权最短路"

**所有算法实现均独立派生自原始论文**，而非逐行移植。本库在此基础上
原创贡献：

1. **可执行 proof predicates**：BFS/Dijkstra 合约已有运行时回归测试，后续可升级到稳定 `moon prove`
2. **可执行 README 示例**：`moon test README.mbt.md` 会编译并快照校验文档示例
3. **四后端一致性** — wasm-gc / native / js / wasm 差分测试作为 CI 硬门禁，另有 WASI 交付门禁（wasmtime 运行产物与 js 后端逐字节对拍）与 wasm 组件模型交付门禁（wasm-tools 组件化 + wasmtime 运行对拍）
4. **AI Agent 友好的后继函数 API**：不强制绑定图结构，便于生成、组合和验证调用代码

与 MoonBit 生态内已有同类包（寻路、hash、compress、TOML、diff 等）的
逐领域对照与取舍说明，见
[docs/ECOSYSTEM_COMPARISON.md](docs/ECOSYSTEM_COMPARISON.md)；
项目整体的"六层集合闭包"定位（寻路 ⊂ 图算法 ⊂ 验证基础设施 ⊂ 通用
基础软件 ⊂ 语言工程工具链 ⊂ AI 原生软件工厂），见
[docs/STRATEGY_CLOSURE.md](docs/STRATEGY_CLOSURE.md)。

---

## 快速开始

### 1. 安装依赖

在你的 MoonBit 项目根目录执行：

```powershell
moon add Suquster/moonbit-pathfinding
```

在需要调用算法的包 `moon.pkg` 里声明导入：

```moonbit
import {
  "Suquster/moonbit-pathfinding/src/directed" @directed,
}
```

更多适合代码代理复制的导入方式见 [AI_AGENT_USAGE.md](./docs/AI_AGENT_USAGE.md)。

### 2. Dijkstra 最短路示例

```moonbit
fn main {
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 1), (2, 4)], // A: A->B(1), A->C(4)
    [(2, 2), (4, 3)], // B: B->C(2), B->E(3)
    [(3, 1)],         // C: C->D(1)
    [],               // D: 目标
    [(3, 2)],         // E: E->D(2)
  ]
  match @directed.dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 3 }) {
    Some((path, cost)) => {
      println("cost = \{cost}")
      println("path = \{path}")
    }
    None => println("unreachable")
  }
}
```

运行 `moon run cmd/main` 后输出：

```
cost = 4
path = [0, 1, 2, 3]
```


---

## 示例工作流 · Example Workflows

仓库提供覆盖寻路与 INFRA 各方向的可直接运行、可检查输出的完整工作流，而不是孤立片段：

| 示例 | 命令 | 方向 | 覆盖点 |
|---|---|---|---|
| 迷宫求解 | `moon run examples/maze_solver` | BFS | ASCII 迷宫最短路、不可达目标 |
| 网络路由 | `moon run examples/network_routing` | Dijkstra | A..J 路由器最小延迟路径、非对称不可达路由 |
| 八数码 | `moon run examples/eight_puzzle` | A* | Manhattan 启发式、解题轨迹、20 步挑战局面 |
| 迷你编译器流水线 | `moon run examples/mini_compiler_pipeline` | mini_compiler | mini-ML 全链路：词法 → 语法 → HM 推断 → 优化 → 字节码 VM+TCO、解释器差分、JS 发射 |
| 正则工具箱 | `moon run examples/regex_toolkit` | regex_engine | 日志脱敏：命名捕获、replace_all 遮蔽、split、线性时间抗 ReDoS |
| 日志管线 | `moon run examples/log_pipeline` | logging | trace span + W3C traceparent、JSON/logfmt/pretty 三渲染、PII 脱敏、env-filter |
| Actor 工作池 | `moon run examples/actor_worker_pool` | actor | 监督工作池注错重启、deathwatch、ask 模式、路由策略、有界邮箱背压 |
| 构建流水线 | `moon run examples/build_pipeline` | build_tool | 规则解析、并行波次调度、最小增量重建、缓存执行、auto-bisect |
| 序列化工作台 | `moon run examples/serialization_studio` | serialization | .proto 解析校验、类型化二进制/JSON 往返、规范字节、破坏性变更检测、代码生成 |
| DST 探索器 | `moon run examples/dst_explorer` | dst | 种子确定性重放、分区/崩溃注错、DPOR 探索、缩小最小复现、线性一致性检查 |
| 配置与差分运维 | `moon run examples/config_diff_ops` | infra_config + infra_diff | TOML/INI 解析、统一 diff、补丁应用/回退、diff3 三方合并冲突、semver 门禁 |
| 哈希完整性 | `moon run examples/hash_integrity` | infra_hash | SHA-2/SHA-3/BLAKE2b 摘要（sha256 与 `sha256sum` 一致）、HMAC 防篡改、HKDF/PBKDF2 派生、流式 == 一次性、xxHash 分片 |
| 压缩工作台 | `moon run examples/compress_workbench` | infra_compress | DEFLATE/zlib/gzip/zstd/LZ4 压缩率对比、无损往返、字典压缩、损坏归档拒绝 |
| 时间调度器 | `moon run examples/time_scheduler` | infra_time + infra_timer | RFC 3339/2822 + strftime、公历运算、POSIX TZ 夏令时、时长往返、时间轮、工作窃取调度（真实 steal 计数） |
| 韧性网关 | `moon run examples/resilience_gateway` | infra_resilience | 封顶退避重试、熔断器状态机、令牌桶 vs 滑动窗口、隔板、AIMD、对冲请求 |
| CLI 开发工具 | `moon run examples/cli_devtool` | infra_cli | 子命令解析与默认值、带 choices 的类型化校验、拼写建议、短参展开、生成 help + bash 补全 |
| 观测套件 | `moon run examples/observability_kit` | infra_metrics | HDR 直方图尾部分位数、可合并 DDSketch 分位数、span 追踪 total vs self 时间 |
| 文本编辑器内核 | `moon run examples/text_editor_core` | infra_text + infra_ds | Rope 与 piece table 编辑收敛、字素/显示宽度、Myers 差分、LRU 淘汰、布隆过滤器、roaring 位图求交 |
| 解析器演练场 | `moon run examples/parser_playground` | parser_combinator | 优先级正确的表达式求值、JSON 精确错误位置渲染、错误恢复诊断、增量分块解析 |
| PBT 与 fuzz 实验室 | `moon run examples/pbt_fuzz_lab` | infra_pbt + infra_fuzz | 属性检查、缩小到边界反例（500）、分布统计、往返律、种子化图 fuzz 与结构缩小 |

一键验证示例输出 marker：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\examples_guard.ps1
```

最新证据：
[`docs/examples/latest-examples-run.md`](./docs/examples/latest-examples-run.md)
与
[`docs/examples/latest-examples-run.json`](./docs/examples/latest-examples-run.json)。

各方向上手教程（关键 API + 最小片段 + 对应 demo）：
[`docs/zh/tutorials.md`](./docs/zh/tutorials.md)（英文完整版
[`docs/tutorials/README.md`](./docs/tutorials/README.md)）。

---

## 发布就绪 · Release Readiness

包元数据已按 mooncakes.io 发布预期检查：SemVer 版本、SPDX license、repository、
homepage、keywords、README、CHANGELOG 与 package artifact。

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\release_guard.ps1
```

最新证据：
[`docs/release/latest-release-readiness.md`](./docs/release/latest-release-readiness.md)
与
[`docs/release/latest-release-readiness.json`](./docs/release/latest-release-readiness.json)。
当前本地 guard 为 `pass-with-warnings`：除 `moon publish --dry-run` 需要
`moon login` 或 CI secrets 提供 mooncakes 凭证外，其余发布就绪检查均通过。

---

## 算法目录

当前已落地 **30 种经典图 / 路径算法** 与 **8 种前沿算法**。
CH / ALT / Hub Labeling 已有生产级稠密快路径变体（`src/directed/`）；
ALT 的 farthest-first 地标选择会优先为尚未覆盖的非连通分量播种，
避免重复地标削弱启发式；三者均附真实 OSM 路网基准证据（北京驾车网：
CH 相对双向 Dijkstra
**46.7×**，HL 距离查询 **0.47 µs（13279×）**，PHAST 一到全 SSSP
相对全量 Dijkstra **6.27×**，many-to-many 64×64 距离表相对逐对
CH **16–27×**，RPHAST 目标子集限定再提 **7.2–9.4×**，见
`benches/results/osm-real-networks-ch-native-2026-07-08.md`；
2026-07-12 异机复测同量级可复现，见
`benches/results/osm-suite-native-2026-07-12.md`）。HL 支持路径还原
（`query_via` / `query_path`）：

| # | 算法 | 模块 | 状态 | 参考论文 |
|---|------|------|------|---------|
| 1  | BFS | `src/unweighted/bfs.mbt` | ✅ | Moore 1959 |
| 2  | DFS | `src/directed/dfs.mbt` | ✅ | Tarjan 1972 |
| 3  | Dijkstra | `src/directed/dijkstra.mbt` | ✅ | Dijkstra 1959 |
| 4  | A\* | `src/directed/astar.mbt` | ✅ | Hart, Nilsson & Raphael 1968 |
| 5  | Bellman-Ford | `src/directed/bellman_ford.mbt` | ✅ | Bellman 1958 |
| 6  | Floyd-Warshall | `src/directed/floyd_warshall.mbt` | ✅ | Floyd 1962 |
| 7  | Kruskal MST | `src/undirected/kruskal.mbt` | ✅ | Kruskal 1956 |
| 8  | 连通分量 | `src/undirected/connected_components.mbt` | ✅ | Hopcroft & Tarjan 1973 |
| 9  | 双向 BFS | `src/directed/bidirectional_bfs.mbt` | ✅ | Pohl 1971 |
| 10 | 拓扑排序 | `src/directed/topo_sort.mbt` | ✅ | Kahn 1962 |
| 11 | Tarjan SCC | `src/directed/tarjan_scc.mbt` | ✅ | Tarjan 1972 |
| 12 | Edmonds-Karp 最大流 | `src/directed/edmonds_karp.mbt` | ✅ | Edmonds & Karp 1972 |
| 13 | IDA\* | `src/directed/ida_star.mbt` | ✅ | Korf 1985 |
| 14 | Yen K 最短路 | `src/directed/yen.mbt` | ✅ | Yen 1971 |
| 15 | Kuhn-Munkres | `src/undirected/kuhn_munkres.mbt` | ✅ | Kuhn 1955 |
| 16 | Prim MST | `src/undirected/prim.mbt` | ✅ | Prim 1957 |
| 17 | DAG 最短路 | `src/directed/dag_shortest_path.mbt` | ✅ | CLRS §24.2（支持负权） |
| 18 | 桥与割点 | `src/undirected/bridges.mbt` | ✅ | Tarjan 1974 |
| 19 | 双向 Dijkstra | `src/directed/bidirectional_dijkstra.mbt` | ✅ | Pohl 1971 |
| 20 | Dijkstra 全源树 | `src/directed/dijkstra_all.mbt` | ✅ | Dijkstra 1959 |
| 21 | BFS 全源树 | `src/unweighted/bfs_all.mbt` | ✅ | Moore 1959 |
| 22 | Bellman-Ford 路径树 | `src/directed/bellman_ford_paths.mbt` | ✅ | Bellman 1958 |
| 23 | Floyd-Warshall 路径重建 | `src/directed/floyd_warshall_paths.mbt` | ✅ | Floyd 1962 |
| 24 | Johnson 全对最短路 | `src/directed/johnson.mbt` | ✅ | Johnson 1977 |
| 25 | Dinic 最大流 | `src/directed/dinic.mbt` | ✅ | Dinitz 1970 |
| 26 | 最小 s-t 割 | `src/directed/min_cut.mbt` | ✅ | Ford & Fulkerson 1956 |
| 27 | 最小费用最大流 | `src/directed/min_cost_flow.mbt` | ✅ | Edmonds & Karp 1972 |
| 28 | Hopcroft-Karp 匹配 | `src/undirected/hopcroft_karp.mbt` | ✅ | Hopcroft & Karp 1973 |
| 29 | 欧拉路径（Hierholzer） | `src/directed/eulerian.mbt` | ✅ | Hierholzer 1873 |
| 30 | SCC 缩点 DAG | `src/directed/condensation.mbt` | ✅ | Tarjan 1972 |
| 31 | 🔥 Contraction Hierarchies | `src/advanced/ch.mbt` · 生产级 `src/directed/ch.mbt` | ✅ OSM 实测 46.7× | Geisberger 2008 |
| 32 | 🔥 Jump Point Search | `src/advanced/jps.mbt` | 🧪 experimental | Harabor & Grastien 2011 |
| 33 | 🔥 ALT (A\* + Landmarks) | `src/advanced/alt.mbt` · 生产级 `src/directed/alt.mbt` | ✅ OSM 实测 6.5× | Goldberg & Harrelson 2005 |
| 34 | 🔥 Hub Labeling (2-hop) | `src/directed/hub_labels.mbt` | ✅ OSM 实测 13279× | Abraham, Delling, Goldberg & Werneck 2011 |
| 35 | 🔥 PHAST（一到全 SSSP） | `src/directed/phast.mbt` | ✅ OSM 实测 6.27× | Delling, Goldberg, Nowatzyk & Werneck 2011 |
| 36 | 🔥 Many-to-many 距离表 | `src/directed/many_to_many.mbt` | ✅ OSM 实测 16–27× | Knopp, Sanders, Schultes, Schulz & Wagner 2007 |
| 37 | 🔥 RPHAST（目标子集限定） | `src/directed/rphast.mbt` | ✅ OSM 实测 7.2–9.4× | Delling, Goldberg, Nowatzyk & Werneck 2011 |
| 38 | 🔥 Customizable CH（CCH） | `src/directed/cch.mbt` | ✅ OSM 实测换权 13–19× | Dibbelt, Strasser & Wagner 2014 |

> 🔥 = **Rust `pathfinding` crate 未实现的独家算法**
> 🧪 experimental = 源码与测试已存在，但 API / 性能证据尚未冻结

---

## Playground · 交互式演示

> **状态**：live — 浏览器内 WASM 实时演示，每次推送 `main` 自动部署到
> GitHub Pages（`.github/workflows/pages.yml`）。

交互式网格寻路可视化，由 `src/` 里同一个算法库编译为 wasm-gc 驱动：

- **在线演示**：<https://Suquster.github.io/moonbit-pathfinding/>
- `moon build --target wasm-gc --release` 将 `src/playground` 导出层链接为
  **≤ 100 KB** 的 `playground.wasm`（CI 中由 `scripts/wasm_size_guard.ps1` 硬门禁）
- 鼠标画墙、拖拽起点/终点，60fps 逐帧动画展示 BFS / DFS / Dijkstra / A* / JPS
  的节点扩展过程，带实时 FPS 计
- 三重回退（wasm-gc → JS glue → 纯 JS），任何环境都能演示，支持完全离线
  （`playground/web/` + 构建好的 `.wasm` 配 `python -m http.server`）
- 桥接正确性受测试门禁：`playground/solver_test.mbt` 与
  `src/playground/*_test.mbt` 断言 Playground 的答案与算法库逐字节一致
- **真实 OSM 路网模式**
  （<https://Suquster.github.io/moonbit-pathfinding/osm.html>）：厦门驾车路网
  （12.5 万节点 / 21.6 万边，OpenStreetMap © 贡献者，ODbL 1.0）通过
  `pg_osm_*` 图模式导出层注入同一个 wasm-gc 引擎；点击地图任意两点自动吸附
  最近路网节点，运行单向 vs 双向 Dijkstra 并实时对比 settle 节点数与耗时
  （每次查询交叉校验两者代价一致）。路网产物可用
  `python3 scripts/build_playground_osm.py` 复现

---

## 形式化证明 · Formal verification

> **状态**：当前已有可执行运行时 predicates；`src/proofs` 已开启
> `proof-enabled`；`scripts/proof_evidence.ps1` 会记录当前 `moon prove`
> 结果或明确的本地工具链阻塞点。

`src/proofs/` 包把前后置条件编码为普通 MoonBit 函数，并通过测试在 CI 中验证。
这些 predicates 是后续 `moon prove` 注解会引用的合约词汇。MoonBit 官方文档
当前仍把形式化验证标为实验能力，`moon prove` 依赖 Why3 与 SMT solver。

| 算法 | 证明性质 | 状态 |
|------|---------|------|
| `bfs` | start/end/edge-validity/minimality/None-witness 后置条件，含坏见证拒绝 | ✅ runtime-checked |
| `dijkstra` | 非负输出、带权路径合法性、代价一致性，含坏见证拒绝 | ✅ runtime-checked |
| `moon prove` 静态证明 | proof-enabled 包 + Why3-backed verifier 调用 | environment-gated |

证明文件位于 `src/proofs/`，与源码一对一隔离：主源码零污染，证明回归
当前硬证据是可执行 predicates 与
[`docs/verification/latest-proof-evidence.md`](./docs/verification/latest-proof-evidence.md)。
本机结果：runtime predicates 通过，`moon prove --help` 可用，静态证明因 Why3
未出现在 `PATH` 中而被环境阻断。


---

## 性能基准 · Benchmarks

`benches/` 目录下提供 4 个基准工作负载，作为 CI 性能回归护栏：每个文件
同时包含 `moon test` smoke guard 和 `moon bench` 原生 `@bench.T` 基准。

| 算法 | 基准文件 | 输入规模 |
|------|----------|---------|
| BFS | `benches/bfs_bench/bfs_bench.mbt` | 1k 节点 × ~10k 稀疏有向边 |
| Dijkstra | `benches/dijkstra_bench/dijkstra_bench.mbt` | 1k 节点 × ~10k 带权边 |
| A\* | `benches/astar_bench/astar_bench.mbt` | 32×32 网格 · Manhattan 启发式 |
| Kruskal MST | `benches/kruskal_bench/kruskal_bench.mbt` | 1k 节点 × 10k 无向带权边 |

运行：

```powershell
chcp 65001
moon test
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_native.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_native_guard.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_smoke.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_guard.ps1
```

`scripts/benchmark_native.ps1` 会生成算法级可审计结果：
[`benches/results/latest-native.md`](./benches/results/latest-native.md) 与
[`benches/results/latest-native.json`](./benches/results/latest-native.json)。
`scripts/benchmark_native_guard.ps1` 会把当前 native run 写到
`_build/native-benchmark-guard/` 临时目录，再与 checked-in baseline 对比
median `moon bench` mean timing，并生成
[`benches/results/latest-native-guard.md`](./benches/results/latest-native-guard.md) 与
[`benches/results/latest-native-guard.json`](./benches/results/latest-native-guard.json)。
`scripts/benchmark_smoke.ps1` 会生成可审计结果：
[`benches/results/latest-smoke.md`](./benches/results/latest-smoke.md) 与
[`benches/results/latest-smoke.json`](./benches/results/latest-smoke.json)。
`scripts/benchmark_guard.ps1` 会把当前 smoke run 写到 `_build/benchmark-guard/`
临时目录，再与 checked-in baseline 对比 median，并生成
[`benches/results/latest-guard.md`](./benches/results/latest-guard.md) 与
[`benches/results/latest-guard.json`](./benches/results/latest-guard.json)。
这些是本地回归证据，不是跨语言加速比声明；native artifact 更接近算法级，
smoke artifact 用于端到端包执行守卫。

### 对标 Rust `pathfinding` crate（✅ 已发布正面对比）

与 Rust `pathfinding` crate（v4.11.0，`cargo --release`）的可复现正面对比
已发布：[`benches/results/latest-rust-comparison.md`](./benches/results/latest-rust-comparison.md)
（`pwsh scripts/rust_comparison.ps1` 生成；native 后端，两侧共享逐位一致的
xorshift64 工作负载并做黄金逐元素交叉校验，每条查询的结果签名两侧逐元素相等）：

![MoonBit vs Rust pathfinding 同算法加速比](./benches/results/rust-comparison-chart.svg)

- **同算法对齐层**（两侧均为单向 BFS / Dijkstra / A\*，18/18 用例全部纳入，
  最大 10 万节点 / 160 万边）：中位加速 **≈2.7×**（区间 2.1–3.6×）。
- **库能力 bonus 层**：本库双向变体（Rust crate 无对应 API）在同一工作负载上
  相对本库单向基线达 **8–68×**，签名逐元素交叉校验；单独列表、**不计入**
  同算法加速比，杜绝不当宣传。

真实 OSM 路网基准已落库（北京 / 厦门驾车网，osmnx 提取）：四档
点到点谱系（双向 Dijkstra → ALT 6.5× → CH 46.7× → HL 13279×）与批量
谱系（PHAST / RPHAST / many-to-many）全部附全量对拍一致性校验与
差分 PBT 守卫，证据见 [`benches/results/osm-real-networks-ch-native-2026-07-08.md`](./benches/results/osm-real-networks-ch-native-2026-07-08.md)
与 [`benches/results/osm-alt-hl-native-2026-07-08.md`](./benches/results/osm-alt-hl-native-2026-07-08.md)。

---

## 开发约定

| 主题 | 要点 |
|------|------|
| 代码风格 | `moon fmt --check` 硬门禁；100 列软限制；`snake_case` / `PascalCase` |
| 测试 | `moon test` 全绿 + `moon test README.mbt.md` 可执行文档门禁 |
| 覆盖率 | src/ 核心库行覆盖率 ≥ 85%（CI 硬门禁，2026-07-12 实测覆盖点 20666/21164 = 97.65%，未覆盖 275 行均为已判定的不可达防御分支） |
| 文档 | 每个 `pub` 项 ≥ 3 行 `///` Doc_Comment，`scripts/audit_doc.ps1` 审计 |
| 本地验收 | `pwsh -File scripts/acceptance.ps1` 一键运行 check / fmt / test / README / doc / coverage；加 `-RunNativeBenchmarkGuard` / `-RunBenchmarkGuard` 可跑 native / smoke 基准回归守门 |
| 提交 | Conventional Commits（`feat` / `fix` / `docs` / `test` / `proof` 等） |
| PR | 使用 `.github/PULL_REQUEST_TEMPLATE.md`；4 个必填字段 |

完整贡献指南：[CONTRIBUTING.zh-CN.md](./CONTRIBUTING.zh-CN.md) /
[CONTRIBUTING.md](./CONTRIBUTING.md)。

---

## 延伸阅读

- [docs/zh/development-article.md](./docs/zh/development-article.md) — **开发实录长文**：从 BFS 到 Hub Labeling 的设计取舍、路网 SOTA 攻坚历程、证伪实验与 AI 协作记录
- [README.md](./README.md) — 英文原版完整文档（含 Quick Start、算法对照表、Benchmarks 全文）
- [README.mbt.md](./README.mbt.md) — 可执行 README（代码即测试）
- [GRAPH_GUIDE.zh-CN.md](./GRAPH_GUIDE.zh-CN.md) — 图输入四种惯用写法
- [AI_AGENT_USAGE.md](./docs/AI_AGENT_USAGE.md) — AI Agent / 脚本集成导入指南
- [CONTRIBUTING.zh-CN.md](./CONTRIBUTING.zh-CN.md) — 贡献指南
- [CHANGELOG.md](./CHANGELOG.md) — 发布历史（Keep a Changelog 格式）
- [docs/zh/algorithms/](./docs/zh/algorithms/) — 15 个算法的中文深度讲解（筹备中）

---

## License · 许可证

Apache License 2.0 © 2026 Suquster. 详见 [LICENSE](./LICENSE)。

`cache/` 下的基准数据来自 [OpenStreetMap](https://www.openstreetmap.org/copyright) 贡献者
（经 Overpass API 获取），按 [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/) 许可再分发。
