# moonbit-pathfinding

> 🌐 Language: **English** · [简体中文](./README.zh-CN.md)

<!-- Tier-1 6 badges (per tasks.md 10.1): License / CI / Version / mooncakes.io / Playground / Formally verified -->
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](./LICENSE)
[![CI](https://github.com/Suquster/moonbit-pathfinding/actions/workflows/ci.yml/badge.svg)](https://github.com/Suquster/moonbit-pathfinding/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-v0.0.1-blue)](./CHANGELOG.md)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-Suquster%2Fmoonbit--pathfinding-orange)](https://mooncakes.io/docs/Suquster/moonbit-pathfinding)
[![Playground](https://img.shields.io/badge/Playground-planned-lightgrey)](#playground)
[![Executable contracts](https://img.shields.io/badge/proof_predicates-runtime_checked-yellow)](#formal-verification)

[![OSC 2026](https://img.shields.io/badge/OSC_2026-participant-brightgreen)](https://moonbitlang.github.io/OSC2026/)

> ⚠️ **This is the static README.** The canonical, always-up-to-date README is
> [**README.mbt.md**](./README.mbt.md), which runs as executable tests
> via `moon test README.mbt.md` — every code example is verified on every CI run.
> 本文件仅为静态副本，最新权威版本请查看 [README.mbt.md](./README.mbt.md)（可执行文档，示例即测试）。

> **A MoonBit-native pathfinding and graph algorithms library built for rigorous engineering.**
>
> A production-grade pathfinding and graph algorithms library for **MoonBit**,
> built to compete with Rust's `pathfinding` crate on the axes that matter:
> **executable proof predicates**, **executable Markdown documentation**,
> **multi-backend consistency** (wasm-gc / native / js), and
> reproducible validation scripts.

---

## Ported from

本库 **API 哲学** 参考自 Rust 社区的
[`pathfinding` crate](https://github.com/evenfurther/pathfinding)（v4.15.0，
双许可 MIT OR Apache-2.0）。核心借鉴:

- **"Successor function" 极简设计** — 算法不强制图数据结构,用户通过
  `fn(N) -> Array[N]` 或 `fn(N) -> Array[(N, W)]` 定义邻居关系。
- **泛型节点类型** — `N : Eq + Hash` 足够,无需 `Ord` 约束。
- **返回类型风格** — `Option[(Array[N], W)]` 表示"可能无解的带权最短路"。

但**所有算法实现均独立派生自原始论文**,不是逐行移植。本库在此基础上**原
创贡献**:

1. **Executable proof predicates** for BFS/Dijkstra contracts, with runtime
   regression tests today and a clear `moon prove` upgrade path.
2. **Executable README examples** via `moon test README.mbt.md`, so examples
   are compiled and snapshot-checked instead of drifting.
3. **三后端一致性** — wasm-gc / native / js 差分测试 CI 门禁。
4. **AI-agent-friendly successor-function APIs** and graph input guides that
   keep callers free from a forced graph data structure.

---

## Quick Start

### 1. 安装依赖

在你的 MoonBit 项目根目录执行:

```powershell
moon add Suquster/moonbit-pathfinding
```

在需要调用算法的包的 `moon.pkg` 里声明导入:

```moonbit
import {
  "Suquster/moonbit-pathfinding/src/directed" @directed,
}
```

> More copy-ready import patterns are in [AI_AGENT_USAGE.md](./docs/AI_AGENT_USAGE.md).

### 2. Dijkstra 最短路 · 5 节点小图

考虑下面的有向带权图 (节点 `A..E` 对应索引 `0..4`):

```
边列表 (起点 → 终点, 权重):
  A(0) → B(1) : 1
  A(0) → C(2) : 4
  B(1) → C(2) : 2
  B(1) → E(4) : 3
  C(2) → D(3) : 1
  E(4) → D(3) : 2

目标: 求 A → D 的最短路径。
```

三条候选路径:

| # | 路径          | 代价计算         | 总代价 |
|---|---------------|------------------|-------:|
| 1 | A → B → C → D | `1 + 2 + 1`      | **4** ✅ |
| 2 | A → C → D     | `4 + 1`          | 5 |
| 3 | A → B → E → D | `1 + 3 + 2`      | 6 |

完整可运行示例 (`cmd/main/main.mbt`):

```moonbit
fn main {
  // 邻接表: 索引 0..4 对应节点 A..E
  // 每个元素为 (邻居节点, 边权)
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 1), (2, 4)], // A: A->B(1), A->C(4)
    [(2, 2), (4, 3)], // B: B->C(2), B->E(3)
    [(3, 1)],         // C: C->D(1)
    [],               // D: 目标,无出边
    [(3, 2)],         // E: E->D(2)
  ]
  let start = 0 // A
  let goal = 3 // D
  match @directed.dijkstra(start, fn(n) { adj[n] }, fn(n) { n == goal }) {
    Some((path, cost)) => {
      println("cost = \{cost}")
      println("path = \{path}")
    }
    None => println("unreachable")
  }
}
```

运行:

```bash
moon run cmd/main
```

预期输出:

```
cost = 4
path = [0, 1, 2, 3]
```

即最短路径为 `A → B → C → D`, 总代价 `4`,与上方表格第 1 行结果吻合。

> 💡 **小贴士**: `dijkstra` 的签名是
> `fn[N : Eq + Hash, W : @core.Weight + Compare + Eq](N, (N) -> Array[(N, W)], (N) -> Bool) -> (Array[N], W)?`
> — 节点类型 `N` 可用 `Int` / `String` / 任意实现了 `Eq + Hash` 的自定义类型;
> 权重类型 `W` 可用内置的 `Int` / `Double`(见 `src/core/prelude.mbt` 的 `Weight` 实现)。

---

## Example Workflows

The repository ships three runnable workflows that exercise different user
stories instead of isolated snippets:

| Example | Command | Algorithm | What it proves |
|---|---|---|---|
| Maze solver | `moon run examples\maze_solver` | BFS | ASCII maze shortest paths, including an unreachable goal |
| Network routing | `moon run examples\network_routing` | Dijkstra | Minimum-latency routes over routers A..J, including asymmetric unreachable routing |
| Eight puzzle | `moon run examples\eight_puzzle` | A* | Sliding-tile solution traces with Manhattan heuristic and a 20-move scenario |

Verify all example outputs with checked markers:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\examples_guard.ps1
```

Latest evidence:
[`docs/examples/latest-examples-run.md`](./docs/examples/latest-examples-run.md)
and
[`docs/examples/latest-examples-run.json`](./docs/examples/latest-examples-run.json).

---

## Release Readiness

Package metadata is checked against mooncakes.io publishing expectations:
SemVer version, SPDX license, repository, homepage, keywords, README, changelog,
and package artifact generation.

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\release_guard.ps1
```

Latest evidence:
[`docs/release/latest-release-readiness.md`](./docs/release/latest-release-readiness.md)
and
[`docs/release/latest-release-readiness.json`](./docs/release/latest-release-readiness.json).
The current local guard passes with one environment warning: `moon publish
--dry-run` needs mooncakes credentials from `moon login` or CI secrets.

---

## Algorithm Catalog

当前 **v0.0.1** 已落地 **15 种经典图/路径算法** 与 **3 种实验性前沿算法**。
CH / JPS / ALT 已有源码和测试，仍需要真实路网基准、论文到代码追踪和性能调优后
再升级为稳定 API。

| # | Algorithm | Module | Status | Paper |
|---|-----------|--------|--------|-------|
| 1  | BFS                           | [`src/unweighted/bfs.mbt`](./src/unweighted/bfs.mbt)                         | ✅ v0.0.1   | — (folklore / Moore 1959)                                                                                                    |
| 2  | DFS                           | [`src/directed/dfs.mbt`](./src/directed/dfs.mbt)                             | ✅ v0.0.1   | — (folklore / Tarjan 1972)                                                                                                   |
| 3  | Dijkstra                      | [`src/directed/dijkstra.mbt`](./src/directed/dijkstra.mbt)                   | ✅ v0.0.1   | [Dijkstra 1959](https://doi.org/10.1007/BF01386390)                                                                          |
| 4  | A\*                           | [`src/directed/astar.mbt`](./src/directed/astar.mbt)                         | ✅ v0.0.1   | [Hart, Nilsson & Raphael 1968](https://doi.org/10.1109/TSSC.1968.300136)                                                     |
| 5  | Bellman-Ford                  | [`src/directed/bellman_ford.mbt`](./src/directed/bellman_ford.mbt)           | ✅ v0.0.1   | [Bellman 1958](https://doi.org/10.1090/qam/102435)                                                                           |
| 6  | Floyd-Warshall                | [`src/directed/floyd_warshall.mbt`](./src/directed/floyd_warshall.mbt)       | ✅ v0.0.1   | [Floyd 1962](https://doi.org/10.1145/367766.368168)                                                                          |
| 7  | Kruskal MST                   | [`src/undirected/kruskal.mbt`](./src/undirected/kruskal.mbt)                 | ✅ v0.0.1   | [Kruskal 1956](https://doi.org/10.1090/S0002-9939-1956-0078686-7)                                                            |
| 8  | Connected Components          | [`src/undirected/connected_components.mbt`](./src/undirected/connected_components.mbt) | ✅ v0.0.1 | — (Hopcroft & Tarjan 1973)                                                                                                   |
| 9  | Bidirectional BFS             | [`src/directed/bidirectional_bfs.mbt`](./src/directed/bidirectional_bfs.mbt) | ✅ v0.0.1   | [Pohl 1971](https://exhibits.stanford.edu/ai/catalog/wv122vt6924)                                                            |
| 10 | Topological Sort              | [`src/directed/topo_sort.mbt`](./src/directed/topo_sort.mbt)                 | ✅ v0.0.1   | [Kahn 1962](https://doi.org/10.1145/368996.369025)                                                                           |
| 11 | Tarjan SCC                    | [`src/directed/tarjan_scc.mbt`](./src/directed/tarjan_scc.mbt)               | ✅ v0.0.1   | [Tarjan 1972](https://doi.org/10.1137/0201010)                                                                               |
| 12 | Edmonds-Karp (Max-Flow)       | [`src/directed/edmonds_karp.mbt`](./src/directed/edmonds_karp.mbt)           | ✅ v0.0.1   | [Edmonds & Karp 1972](https://doi.org/10.1145/321694.321699)                                                                 |
| 13 | IDA\*                         | [`src/directed/ida_star.mbt`](./src/directed/ida_star.mbt)                   | ✅ v0.0.1   | [Korf 1985](https://doi.org/10.1016/0004-3702%2885%2990084-0)                                                                |
| 14 | Yen K-Shortest Paths          | [`src/directed/yen.mbt`](./src/directed/yen.mbt)                             | ✅ v0.0.1   | [Yen 1971](https://doi.org/10.1287/mnsc.17.11.712)                                                                           |
| 15 | Kuhn-Munkres (Hungarian)      | [`src/undirected/kuhn_munkres.mbt`](./src/undirected/kuhn_munkres.mbt)       | ✅ v0.0.1   | [Kuhn 1955](https://doi.org/10.1002/nav.3800020109)                                                                          |
| 16 | 🔥 Contraction Hierarchies    | `src/advanced/ch.mbt`                                                        | 🧪 experimental | [Geisberger, Sanders, Schultes & Delling 2008](https://doi.org/10.1007/978-3-540-68552-4_24)                                 |
| 17 | 🔥 Jump Point Search          | `src/advanced/jps.mbt`                                                       | 🧪 experimental | [Harabor & Grastien 2011](https://ojs.aaai.org/index.php/AAAI/article/view/7994)                                             |
| 18 | 🔥 ALT (A\* + Landmarks + Δ)  | `src/advanced/alt.mbt`                                                       | 🧪 experimental | [Goldberg & Harrelson 2005 (SODA)](https://dl.acm.org/doi/10.5555/1070432.1070455)                                           |

> ✅ v0.0.1 = 源码 + 单元测试 + PBT 已合入主干
> 🧪 experimental = source + tests exist, but API/performance evidence is not yet frozen
> 🔥 = **Rust `pathfinding` crate 未实现的独家算法** (对应 R18 前沿算法撒手锏)

---

## Playground

> **状态**: planned, not yet part of the verified acceptance surface.

The current repository ships examples and executable documentation, but not a
browser playground yet. The planned playground acceptance target is:

- `moon build --target wasm-gc` 产出 ≤ 100 KB 的 `.wasm` 模块
- 鼠标拖拽起点/终点，并记录实际帧率、输入规模和浏览器环境
- 逐帧动画展示 BFS / DFS / Dijkstra / A* / JPS 的扩展过程
- 部署到 GitHub Pages: `https://Suquster.github.io/moonbit-pathfinding/`

对应需求: R16 (WASM Playground) · R26 (实时 JPS Playground 杀手锏)。

---

## Formal verification

> **状态**: executable runtime predicates exist today; `src/proofs` is
> `proof-enabled`, and `scripts/proof_evidence.ps1` records the current
> `moon prove` result or the exact local toolchain blocker.

The `src/proofs/` package encodes post-condition predicates as ordinary
MoonBit functions and tests them in CI. These predicates are the contract
vocabulary that `moon prove` annotations can reference as the verifier surface
settles. Official MoonBit documentation currently describes `moon prove` as
experimental, backed by Why3 and SMT solvers.

| 算法 | 证明性质 | 状态 |
|------|---------|------|
| `bfs` | start/end/edge-validity/minimality/None-witness post-conditions, including bad-witness rejection | ✅ runtime-checked |
| `dijkstra` | non-negative outputs, weighted path-validity, cost consistency, including bad-witness rejection | ✅ runtime-checked |
| `moon prove` static discharge | proof-enabled package, Why3-backed verifier invocation | environment-gated |

Run the current evidence chain with:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\proof_evidence.ps1
```

Latest local evidence is stored in
[`docs/verification/latest-proof-evidence.md`](./docs/verification/latest-proof-evidence.md).
On this machine, runtime proof predicates passed, `moon prove --help` is
available, and static discharge is blocked because Why3 is not on `PATH`.

对应需求: R8 (形式化证明撒手锏) · R25 (答辩故事张力)。

---

## Benchmarks

> 对应 tasks.md 29.x · Requirements R14.1 / R14.2 · design.md §15.4

`moonbit-pathfinding` 以 `benches/` 目录承载**可复现、可 CI 回归的性能证据**：
`moon test` smoke guards 验证工作负载正确性，`moon bench` 原生 `@bench.T`
块记录更低噪声的算法级时间。当前基准覆盖 4 个 MVP 算法：

| 算法 | 基准文件 | 输入规模 | 图形 | 期望 |
|------|----------|---------|------|------|
| BFS | [`benches/bfs_bench/bfs_bench.mbt`](./benches/bfs_bench/bfs_bench.mbt) | 1k 节点 × ~10k 边 | 随机稀疏有向图 (density 1%) | 求 0 → 999 最短路径 |
| Dijkstra | [`benches/dijkstra_bench/dijkstra_bench.mbt`](./benches/dijkstra_bench/dijkstra_bench.mbt) | 1k 节点 × ~10k 带权边 | 权值 ∈ [1, 10] | 求 0 → 999 最小代价 |
| A\* | [`benches/astar_bench/astar_bench.mbt`](./benches/astar_bench/astar_bench.mbt) | 32×32 = 1024 节点 | 开放网格 4-向 | (0,0) → (31,31)，cost = 62 |
| Kruskal MST | [`benches/kruskal_bench/kruskal_bench.mbt`](./benches/kruskal_bench/kruskal_bench.mbt) | 1k 节点 × 10k 无向带权边 | 权值 ∈ [1, 100] | MST 包含 ≤ 999 条边 |

### 运行

```powershell
chcp 65001
moon test
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_native.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_native_guard.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_smoke.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_guard.ps1
```

每个基准文件都有 `test "smoke: ..."` 和 `test "bench: ..." (b : @bench.T)`
两层入口：前者进入普通测试，后者由 `moon bench` 采样。
`scripts/benchmark_native.ps1` 会生成算法级结果：
[`benches/results/latest-native.md`](./benches/results/latest-native.md) 与
[`benches/results/latest-native.json`](./benches/results/latest-native.json)。
`scripts/benchmark_native_guard.ps1` 会把当前 native run 写入
`_build/native-benchmark-guard/` 临时目录，并和 checked-in baseline 比较
median `moon bench` mean timing，生成
[`benches/results/latest-native-guard.md`](./benches/results/latest-native-guard.md) 与
[`benches/results/latest-native-guard.json`](./benches/results/latest-native-guard.json)。
`scripts/benchmark_smoke.ps1` 会额外生成可审计结果：
[`benches/results/latest-smoke.md`](./benches/results/latest-smoke.md) 与
[`benches/results/latest-smoke.json`](./benches/results/latest-smoke.json)。
`scripts/benchmark_guard.ps1` 会把当前 smoke run 写入 `_build/benchmark-guard/`
临时目录，并和 checked-in baseline 比较 median，生成
[`benches/results/latest-guard.md`](./benches/results/latest-guard.md) 与
[`benches/results/latest-guard.json`](./benches/results/latest-guard.json)。

### 对标 Rust `pathfinding` crate

Current benchmark tests and checked-in `benches/results/*.json` artifacts are
local regression evidence, not a published Rust comparison yet. Native artifacts
record `moon bench` statistics from `@bench.T` blocks; smoke artifacts record
end-to-end package timing. Both include machine, backend, input size, command
output, and methodology so regressions can be discussed with concrete data,
while avoiding unsupported speedup claims.

The native guard defaults to a 25% regression tolerance. The smoke guard remains
available with a deliberately loose 50% default because it times end-to-end
`moon test -p ...` package execution.

### OSM 真实路网（planned · Tier-3）

M4 里程碑将加入 OSM 路网基准（见 `benches/osm/`），同时引入
CH / ALT / JPS 三种前沿算法的可复现对照。任何加速比都必须来自
`benches/results/` 中记录的机器、backend、输入和原始计时。

---

## Multi-backend consistency · 三后端一致性

> 对应 tasks.md 39.x · Requirement R17 · design.md §15.1

This library is built to **compile and run identically on all three MoonBit
backends**: `wasm-gc`, `js`, and `native`. Every push to `main` and every PR
triggers the `ci` workflow's **3-backend matrix**, which executes the full
test suite (currently 97 blackbox + whitebox cases) on each backend. Any
output divergence — including snapshot mismatches from `inspect(..., content=...)`
— fails the entire build, giving us a **differential test** of algorithmic
behaviour across backends for free.

### Backend × Algorithm matrix

| Algorithm | wasm-gc | js | native | Notes |
|-----------|:-------:|:--:|:------:|-------|
| BFS, DFS, Dijkstra, A\*, Bellman-Ford, Floyd-Warshall | ✅ | ✅ | ✅ | MVP, uniform |
| Kruskal, Connected Components, Bidirectional BFS | ✅ | ✅ | ✅ | |
| Topological Sort, Tarjan SCC, Edmonds-Karp | ✅ | ✅ | ✅ | |
| IDA\*, Yen K-shortest, Kuhn-Munkres | ✅ | ✅ | ✅ | |
| Contraction Hierarchies (CH) | ✅ | ✅ | ✅ | correctness-first implementation |
| Jump Point Search (JPS) | ✅ | ✅ | ✅ | v1.0.0 ship |
| ALT (A\* + Landmarks) | ✅ | ✅ | ✅ | v1.0.0 ship |

### Performance evidence

Current benchmark tests are smoke gates, not a published backend comparison.
The repository now includes reproducible smoke artifacts under
[`benches/results/`](./benches/results/) with:

| Required field | Why it matters |
|----------------|----------------|
| MoonBit version and target backend | Toolchain performance changes over time |
| Machine / OS / CPU | Makes local numbers interpretable |
| Input generator and seed | Allows exact reruns |
| Algorithm, graph size, edge count, query count | Prevents vague benchmark claims |
| Raw timing and summary statistics | Keeps release notes auditable |

Native and smoke regression guards are available through
`scripts/benchmark_native_guard.ps1`, `scripts/benchmark_guard.ps1`, and optional
local acceptance:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\acceptance.ps1 -SkipCoverage -RunNativeBenchmarkGuard -RunBenchmarkGuard
```

The native guard is the lower-noise gate; the smoke guard remains useful for
package-level harness regressions.

### Target restrictions

Currently **no algorithm is backend-restricted**. Future additions that rely
on backend-specific features (e.g. SIMD intrinsics on native) will declare
`supported_targets` in their `moon.pkg.json`. Template follows design.md §15.1.

---

---

## Acknowledgements · 致谢

This project stands on the shoulders of three communities:

1. **MoonBit Team & Community** — for the toolchain, Discourse feedback, and
   the hard work behind `moon prove`, Markdown-oriented programming, and the
   three-backend ecosystem that makes this library possible.
2. **Rust `pathfinding` crate authors (evenfurther & contributors)** — for
   the minimalist "successor function" API philosophy that we ported into
   MoonBit. Thank you for a decade of principled design in open source.
3. **OSC 2026 mentors & reviewers** — for the spec-driven methodology and
   continuous, candid feedback during Milestones 0–3.

External code reviewers and discussion participants who shaped this library
(alphabetical, by GitHub handle) are recorded in `docs/community/` as the
project grows. Pull requests are warmly welcomed — see
[CONTRIBUTING.md](./CONTRIBUTING.md).

For code agents and scripted integrations, see
[AI_AGENT_USAGE.md](./docs/AI_AGENT_USAGE.md).

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](./LICENSE).
