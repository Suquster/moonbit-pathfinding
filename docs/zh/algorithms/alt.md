# ALT · A\* + Landmarks + 三角不等式（🚧 v1.0.0）

> **状态**：🧪 experimental — `src/advanced/alt.mbt` 与 `alt_test.mbt` 已落地；仍需真实路网基准、landmark 选择调优和论文到代码追踪后升级为稳定 API。

## 背景

Andrew Goldberg 与 Chris Harrelson 在 SODA 2005 论文 *Computing the Shortest
Path: A\* Search Meets Graph Theory* 中提出 ALT，是**"实用"**的 A\* 启发式
选择方案：它不需要显式的几何坐标（与欧氏距离启发式不同），只需图结构
本身，因此适用于**任何带权有向图**——铁路网、航班、社交网络、计算机网络
都能跑。

相比 Contraction Hierarchies 的重预处理，ALT 预处理更轻、更新代价更低，
是 **"动态路网 + A\*"** 的经典组合。

## 核心思想

利用**三角不等式**：对任意节点 `l`（称为**地标**，landmark）与任意两点 `n, t`，
有

```
|dist(l, n) − dist(l, t)| ≤ dist(n, t) ≤ dist(l, n) + dist(l, t)
```

左半边给出了**下界估计**——正是 A\* 所需的**可采纳启发式**！

**ALT 做两件事**：

1. **预处理**（一次性）：选 `k` 个地标节点（经典策略：farthest-first 贪心
   地挑，让地标均匀分布在图的"极端"），对每个地标 `l` 用 Dijkstra 计算
   `dist(l, ·)` 与 `dist(·, l)`，存入二维数组；
2. **查询时**：给定 `start → target`，定义启发式

```
h(n) = max_{l ∈ landmarks} |dist(l, n) − dist(l, target)|
```

然后用 A\* 驱动搜索。由于 `max` 下仍满足三角不等式，`h` 可采纳且一致。

## 地标选择策略对比

| 策略 | 质量 | 耗时 | 场景 |
|------|------|------|------|
| **Farthest-first** | 好 | 中 | 教学首选 |
| Planar | 更好（均匀覆盖图空间）| 高 | 地图数据 |
| Random | 差，但省事 | 低 | 原型对比 |
| Avoid | 最好（针对搜索模式优化）| 极高 | 生产级 |

本库计划先实现 **Farthest-first + 默认 16 个地标**，覆盖"`alt_preprocess`
+ `alt_query`" 完整工作流。

## 预处理与查询复杂度

| 阶段 | 复杂度 |
|------|-------|
| 预处理 | O(k · (V + E) log V) |
| 单次查询 | O((V + E) log V) 但启发式剪枝使实际扩展节点大幅减少（常见 2×~10× 加速）|
| 空间 | O(k · V) 预计算距离表 |

**k = 16** 在路网上通常能提供 **10× 以上**加速，且预计算代价可接受
（10 万节点 ≈ 数秒）。

## 典型场景

1. **动态路网**：道路权重（实时交通）每 5 分钟变化时，ALT 只需重算距离
   表（O(k × Dijkstra)），比 CH 的"全图重预处理"便宜；
2. **非几何图**：社交网络、依赖图、语义网等没有欧氏距离可用但需要 A\*
   启发式的场合；
3. **教学示例**：三角不等式下界的最直观应用，适合算法课展示；
4. **本库 M4 PBT 验证**：`Property 11 · ALT 启发式单调下界`（对应
   tasks.md 37.5）将验证 `h ≥ 0 ∧ h ≤ dist(n, t) ∧ h(t, t) == 0`。

## 当前 API

```moonbit skip
let landmarks = @advanced.alt_preprocess(
  nodes, successors, num_landmarks=16)
let result = @advanced.alt_query(
  landmarks, start, goal, successors)
// result: Option[(Array[N], W)]
```

预计算结果可序列化到 JSON（对应 R18.3），实现"部署时预处理、运行时
加载"的工程化流程。

## 启发式不变式

| 性质 | 公式 |
|------|------|
| 非负 | `h(n) ≥ 0` |
| 可采纳 | `h(n) ≤ dist(n, target)` |
| 一致性 | `h(u) ≤ w(u, v) + h(v)` |
| 目标归零 | `h(target) = 0` |

本库 PBT `prop_11_alt_admissible` 随机生成图与查询，用 Dijkstra 计算真实
`dist` 作为 oracle，对每个节点 `n` 检查 `h(n) ≤ dist(n, t)`——一旦失败，
反例将被存档到 `tests/fuzz/corpus/` 并自动建 Issue。

## 参考文献

- Goldberg, A. V., & Harrelson, C. (2005). "Computing the Shortest Path:
  A\* Search Meets Graph Theory." *SODA 2005*, 156–165.
- Goldberg, A. V., & Werneck, R. F. (2005). "Computing point-to-point
  shortest paths from external memory." *ALENEX 2005*.
