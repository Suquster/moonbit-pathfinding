# moonbit-pathfinding · 答辩 PPT 大纲

> 对应 tasks.md 45.1 / Requirement R12.3, R25.3
>
> 格式：Marp Markdown -> PDF（`npx @marp-team/marp-cli slides.md -o slides.pdf`）
> 口径：所有结论必须能被仓库里的命令、源码或文档路径证明；未交付能力只放在路线图。

---
marp: true
theme: default
paginate: true
---

<!-- slide 1 -->
# moonbit-pathfinding

**MoonBit 原生路径规划与图算法库**

可执行文档 · 运行时 proof predicates · 多后端验收门禁

Suquster · OSC 2026

---

<!-- slide 2 -->
## 一句话定位

MoonBit 生态缺少一个可以直接拿来做路径规划、图算法教学、AI Agent 调用和多后端验证的工程化库。

本项目的竞争力不是喊概念，而是把四件事接在一起：

- 算法 API 简洁：successor function，不强绑定图结构
- 测试可复现：`moon test`、README doctest、覆盖率与文档审计
- 合约可执行：BFS/Dijkstra proof predicates 已作为普通 MoonBit 函数测试
- 交付可答辩：中英文 README、算法文档、验收脚本、答辩材料同口径

---

<!-- slide 3 -->
## 当前已验证证据

| 证据 | 命令或路径 |
|------|------------|
| 类型检查 | `moon check` |
| 格式检查 | `moon fmt --check` |
| 单元 / 属性 / fuzz 测试 | `moon test` |
| README 可执行示例 | `moon test README.mbt.md` |
| API 文档构建 | `moon doc` |
| 公共 API 注释审计 | `scripts/audit_doc.ps1` |
| 本地总验收入口 | `scripts/acceptance.ps1` |

---

<!-- slide 4 -->
## 架构总览

```
src/core/        Weight trait · PQueue · DSU
src/unweighted/  BFS
src/directed/    Dijkstra · A* · Bellman-Ford · Floyd-Warshall
                 DFS · IDA* · Bidirectional BFS · Yen
                 Tarjan SCC · Topo Sort · Edmonds-Karp
src/undirected/  Kruskal · Connected Components · Kuhn-Munkres
src/advanced/    CH · JPS · ALT
src/proofs/      predicates · bfs_proof · dijkstra_proof
```

---

<!-- slide 5 -->
## 核心设计：Successor Function API

```moonbit
// 无权图
pub fn bfs[N : Eq + Hash](start, successors: (N) -> Array[N], goal) -> Array[N]?

// 带权图
pub fn dijkstra[N, W](start, successors: (N) -> Array[(N, W)], goal) -> (Array[N], W)?
```

- 不绑定 `Graph` 类，调用方可以用数组、Map、生成函数或外部数据源
- 节点只需 `Eq + Hash`
- 权重通过 `Weight` trait 统一 `Int` 与 `Double`

---

<!-- slide 6 -->
## 算法覆盖面

| 层级 | 算法 | 当前定位 |
|------|------|----------|
| 基础路径 | BFS / DFS / Dijkstra / A* / Bellman-Ford / Floyd-Warshall | 已实现并测试 |
| 图结构 | Kruskal / Connected Components / Tarjan SCC / Topo Sort | 已实现并测试 |
| 流与匹配 | Edmonds-Karp / Kuhn-Munkres | 已实现并测试 |
| 组合路径 | Bidirectional BFS / IDA* / Yen | 已实现并测试 |
| 前沿方向 | CH / JPS / ALT / Hub Labeling / PHAST / RPHAST / many-to-many / CCH | 生产级实现 + OSM 真实路网实测（北京：CH 46×、HL 14304×、CCH 换权 13.4×）+ 论文追踪 |

---

<!-- slide 7 -->
## Proof Predicates · BFS

```
POST-1: path[0] == start
POST-2: goal(path[-1])
POST-3: is_valid_path(path, start, successors)
POST-4: minimality via runtime bounded BFS witness
POST-5: None iff not reachable under provided oracle nodes
```

当前状态：

- 谓词是可执行 MoonBit 函数，不是注释
- `src/proofs/bfs_proof_test.mbt` 覆盖最短路、非最短路、非法路径
- 静态 `moon prove` 已通过 `scripts/proof_evidence.ps1` 记录为 environment-gated

---

<!-- slide 8 -->
## Proof Predicates · Dijkstra

```
PRE-1:  all_edges_non_negative(edges, edge_weight)
POST-1: is_non_negative(cost)
POST-2: check_termination_measure
POST-3: check_edges_valid_weighted
POST-4: check_cost_matches_path
```

价值：

- 把评委会追问的“你怎么知道最短路合法”变成可运行检查
- 为未来稳定的 `moon prove` 注解准备同一套合约词汇
- 和 README doctest 一起形成“文档、代码、测试”一致闭环

---

<!-- slide 9 -->
## Jump Point Search · 网格方向

- 8 向网格 + Octile 启发式
- 强制邻居与对角线分量递归
- 当前已进入 `src/advanced/jps.mbt` 与测试
- 当前基准：native guard 记录回归证据；下一步补扩展节点数和输入地图

```moonbit
let grid = JPSGrid::new(32, 32, blocked)
let result = jps(grid, (0, 0), (31, 31))
```

---

<!-- slide 10 -->
## Contraction Hierarchies · 路网方向

- 预处理：节点收缩、witness search、shortcut 注入
- 查询：双向上行图搜索、shortcut 展开
- 当前策略：正确性优先，收缩顺序仍需继续优化
- 下一步证据：edge-difference 顺序、真实路网基准、Dijkstra 对照

```moonbit
let graph = ch_preprocess(nodes, successors)
let result = ch_query(graph, source, target)
```

---

<!-- slide 11 -->
## ALT · Landmarks + A*

- farthest-first 选 landmark
- 预处理正向 / 反向距离表
- 用三角不等式构造 admissible heuristic
- 当前状态：实现与测试已存在，native guard 记录回归证据

关键答辩点：ALT 的正确性优先于早停优化；对非 consistent 启发式，不盲目早停。

---

<!-- slide 12 -->
## 质量保障体系

| 层 | 工具 | 作用 |
|----|------|------|
| 静态检查 | `moon check` | 类型与包关系 |
| 格式 | `moon fmt --check` | 风格一致 |
| 测试 | `moon test` | 单元、属性、fuzz、回归 |
| 文档即测试 | `moon test README.mbt.md` | 防 README 过时 |
| 文档构建 | `moon doc` + `audit_doc.ps1` | 公共 API 可解释 |
| 覆盖率 | `moon test --enable-coverage` + gate | 本地与 CI 证据 |

---

<!-- slide 13 -->
## 用户体验

- 英文 README：项目定位、安装、算法表、验收命令
- 中文 README：面向中文评委与开发者的同口径版本
- README.mbt.md：可执行示例，避免“文档写得好但跑不通”
- `GRAPH_GUIDE`：解释 successor function API 如何映射真实图
- `examples/`：网络路由、迷宫、八数码等工作流入口

---

<!-- slide 14 -->
## AI Agent 友好性

为什么适合 AI Agent 调库：

- 调用面小：传 `start`、`successors`、`goal`
- 返回值明确：`Some(path)` / `None`，失败路径不靠异常表达
- 类型约束清楚：节点 `Eq + Hash`，权重 `Weight`
- README doctest 给出可复制最小调用样例

已补充：`docs/AI_AGENT_USAGE.md` 列出 import、常见陷阱、验证命令和可引用证据。

---

<!-- slide 15 -->
## 社区与发布准备

已具备：

- Apache-2.0 License
- CONTRIBUTING / CODE_OF_CONDUCT
- CHANGELOG
- GitHub Actions CI and hard-gated release workflow
- 本地验收脚本
- release readiness artifact

待补强：

- mooncakes 发布 token / credentials 配置
- 真实路网 benchmark artifact
- playground 是否交付为真实本地 demo

---

<!-- slide 16 -->
## 基准现状

当前已做：

- benchmark 测试作为 smoke gate，防止基础路径回归
- README 已不再宣称未记录的 Rust 性能对比

当前已产出：

- `benches/results/*.json`
- 机器信息、MoonBit 版本、backend、输入生成方法
- BFS / Dijkstra / A* / JPS / CH / ALT 的可重复命令
- native benchmark regression guard

---

<!-- slide 17 -->
## 与 Rust pathfinding 对标

| 维度 | Rust pathfinding | 本项目当前证据 |
|------|------------------|----------------|
| 语言生态 | Rust 成熟库 | MoonBit 原生库，填生态空白 |
| API 风格 | successor function | 同类简洁接口，适配 MoonBit |
| 可执行文档 | crate docs / tests | README.mbt.md 可由 `moon test` 执行 |
| 合约验证 | 无内建证明链路 | runtime proof predicates 已测试 |
| 多后端 | Rust native / wasm 需额外链路 | MoonBit wasm-gc / js / native CI 目标 |
| 前沿算法 | 无 CH/HL/PHAST 等路网 SOTA | 8 种已实现（含 CCH 权重换绑），OSM 实测证据归档（benches/results/ch-osm-20260705.md、cch-osm-20260706.md） |

---

<!-- slide 18 -->
## 里程碑回顾

| 阶段 | 交付重点 | 验证标准 |
|------|----------|----------|
| v0.0.x | BFS 与包结构 | `moon test` |
| v0.1.x | 核心路径算法 | 单元测试 + examples |
| v0.2.x | 图算法扩展 | PBT / fuzz |
| v0.3.x | 中文文档与高级算法 | README / docs / advanced tests |
| 当前冲刺 | truthfulness + acceptance + proof predicates | `scripts/acceptance.ps1` |

---

<!-- slide 19 -->
## 下一阶段冲冠路线

1. 补齐负例与边界回归：不可达、空图、单点、重复边、负权、断连
2. 双语 README、AI guide、slides、demo script 保持同一证据口径
3. 为 CH / JPS / ALT 建立论文到代码 traceability
4. 追加 OSM / 真实路网 benchmark artifact 后再讲加速比
5. 决策 playground：要么可本地打开并记录环境，要么继续移出交付承诺

---

<!-- slide 20 -->
## 结尾

moonbit-pathfinding 的目标不是“把算法搬到 MoonBit”，而是交付一个评委能验证、开发者能调用、未来能升级证明链路的 MoonBit 图算法库。

**GitHub**: github.com/Suquster/moonbit-pathfinding

**mooncakes**: mooncakes.io/docs/Suquster/moonbit-pathfinding

> 让路径规划既好用，又能被验证。
