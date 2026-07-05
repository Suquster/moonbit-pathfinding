# moonbit-pathfinding · 中文版

> 🌐 Language: **简体中文** · [English](./README.md)

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](./LICENSE)
[![CI](https://github.com/Suquster/moonbit-pathfinding/actions/workflows/ci.yml/badge.svg)](https://github.com/Suquster/moonbit-pathfinding/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-v0.0.1-blue)](./CHANGELOG.md)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-Suquster%2Fmoonbit--pathfinding-orange)](https://mooncakes.io/docs/Suquster/moonbit-pathfinding)
[![Playground](https://img.shields.io/badge/Playground-live-brightgreen)](#playground)
[![Executable contracts](https://img.shields.io/badge/proof_predicates-runtime_checked-yellow)](#formal-verification)
[![OSC 2026](https://img.shields.io/badge/OSC_2026-participant-brightgreen)](https://moonbitlang.github.io/OSC2026/)

> **面向 MoonBit 的严谨工程化路径规划与图算法库。**
>
> 面向 **MoonBit** 的生产级路径规划与图算法库，核心亮点：
> **可执行 proof predicates**、**可执行 Markdown 文档**、
> **三后端一致性** (wasm-gc / native / js)、**一键验收脚本**。

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
3. **三后端一致性** — wasm-gc / native / js 差分测试作为 CI 硬门禁
4. **AI Agent 友好的后继函数 API**：不强制绑定图结构，便于生成、组合和验证调用代码

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

仓库提供 3 个可直接运行、可检查输出的完整工作流，而不是孤立片段：

| 示例 | 命令 | 算法 | 覆盖点 |
|---|---|---|---|
| 迷宫求解 | `moon run examples\maze_solver` | BFS | ASCII 迷宫最短路、不可达目标 |
| 网络路由 | `moon run examples\network_routing` | Dijkstra | A..J 路由器最小延迟路径、非对称不可达路由 |
| 八数码 | `moon run examples\eight_puzzle` | A* | Manhattan 启发式、解题轨迹、20 步挑战局面 |

一键验证示例输出 marker：

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\examples_guard.ps1
```

最新证据：
[`docs/examples/latest-examples-run.md`](./docs/examples/latest-examples-run.md)
与
[`docs/examples/latest-examples-run.json`](./docs/examples/latest-examples-run.json)。

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

当前 v0.0.1 已实现 **15 个经典图 / 路径算法** 与 **3 个实验性前沿算法**。
CH / JPS / ALT 已有源码和测试，仍需真实路网基准、论文到代码追踪与性能调优后
再升级为稳定 API：

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
| 16 | 🔥 Contraction Hierarchies | `src/advanced/ch.mbt` | 🧪 experimental | Geisberger 2008 |
| 17 | 🔥 Jump Point Search | `src/advanced/jps.mbt` | 🧪 experimental | Harabor & Grastien 2011 |
| 18 | 🔥 ALT (A\* + Landmarks) | `src/advanced/alt.mbt` | 🧪 experimental | Goldberg & Harrelson 2005 |

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

后续将追加 **10 万节点级** OSM 真实路网基准（`benches/osm/`），
并引入 CH / ALT / JPS 加速比对照；在真实路网结果工件落库前，不把加速比作为已测声明。

---

## 开发约定

| 主题 | 要点 |
|------|------|
| 代码风格 | `moon fmt --check` 硬门禁；100 列软限制；`snake_case` / `PascalCase` |
| 测试 | `moon test` 全绿 + `moon test README.mbt.md` 可执行文档门禁 |
| 覆盖率 | src/ 核心库行覆盖率 ≥ 85%（CI 硬门禁，当前 91.62%） |
| 文档 | 每个 `pub` 项 ≥ 3 行 `///` Doc_Comment，`scripts/audit_doc.ps1` 审计 |
| 本地验收 | `pwsh -File scripts/acceptance.ps1` 一键运行 check / fmt / test / README / doc / coverage；加 `-RunNativeBenchmarkGuard` / `-RunBenchmarkGuard` 可跑 native / smoke 基准回归守门 |
| 提交 | Conventional Commits（`feat` / `fix` / `docs` / `test` / `proof` 等） |
| PR | 使用 `.github/PULL_REQUEST_TEMPLATE.md`；4 个必填字段 |

完整贡献指南：[CONTRIBUTING.zh-CN.md](./CONTRIBUTING.zh-CN.md) /
[CONTRIBUTING.md](./CONTRIBUTING.md)。

---

## 延伸阅读

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
