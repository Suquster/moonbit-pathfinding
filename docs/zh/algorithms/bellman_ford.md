# Bellman-Ford · 含负权最短路 + 负环检测

## 背景

Bellman-Ford 由 Richard Bellman（1958 年）独立于 Lester Ford Jr.（1956 年）
几乎同时提出，最早用于美国海军研究的"最短航程网络"。它的核心意义在于
**突破 Dijkstra 的非负权限制**，能在含**负权边**的有向图上给出正确最短
路径，并且天然地提供**负环检测**机制——这是金融套利识别、货币兑换网络、
最大期望收益路径等应用的必选算法。

## 核心思想

**"松弛 |V|−1 轮"**：对所有 V−1 轮，每轮把图里每条边都松弛一次；若图中
没有负环，V−1 轮之后每个节点的 `dist` 都已收敛到最短值。

**证明直觉**：从 `start` 到任意可达节点 `v` 的最短路径最多经过 V−1 条边
（否则必有重复节点即环；非负环的话删环只会更短，负环情形单独处理）。
第 `k` 轮结束时，所有**最多 `k` 条边**的最短路径都已被找到；V−1 轮后覆盖
一切可能的最短路。

**负环检测**：再跑第 V 轮松弛，若还有 `dist` 能被进一步缩短，说明存在从
`start` 可达的负环；此时"最短路"无下界，返回 `Err(NegativeCycle)`。

## 算法步骤

```
dist[start] ← 0, 其余 ← ∞
for i in 0..V-1:
  for (u, v, w) in edges:
    if dist[u] != ∞ and dist[u] + w < dist[v]:
      dist[v] ← dist[u] + w
// 第 V 轮：能否继续松弛？
for (u, v, w) in edges:
  if dist[u] != ∞ and dist[u] + w < dist[v]:
    return Err(NegativeCycle)
return Ok(dist)
```

本库实现还**额外跳过**不可达节点（`dist.get(u) == None`），这是一处常见
的性能优化与正确性保障（对孤立源避免误把 `∞ + w` 当作改善）。

## 时间复杂度

- **时间** O(V · E)：V−1 轮，每轮扫描全部 E 条边。
- **空间** O(V)。

比 Dijkstra 慢一个 log V 因子，但换来负权支持和负环检测，对金融类问题
值得。

## 典型场景

1. **金融套利检测**：把货币视作节点、汇率取对数的相反数作为边权，寻找
   负环 = 发现套利机会。
2. **路由协议 RIP / BGP 入门**：距离向量协议的教科书模型。
3. **线性规划约束差分**：差分约束系统可转化为 `x_j − x_i ≤ w`，直接跑
   Bellman-Ford 判可行性。
4. **交叉验证 PBT**：本库将 Bellman-Ford 与 Dijkstra 在无负权图上做
   **跨算法共识测试**，作为正确性锚点（tasks.md 27.2）。

## MoonBit API 示例

```moonbit
// 含负权但无负环
let nodes = [0, 1, 2]
let edges : Array[(Int, Int, Int)] = [(0, 1, 4), (1, 2, -2), (0, 2, 5)]
match @directed.bellman_ford(nodes, edges, 0) {
  Ok(dist) => println(dist.get(2))   // Some(2)，因为 0→1→2 = 4-2 = 2 < 5
  Err(@core.NegativeCycle) => println("负环")
  Err(e) => println(e)
}
```

## 与 Dijkstra 对比

| 维度 | Dijkstra | Bellman-Ford |
|------|----------|--------------|
| 权重 | ≥ 0 | 任意（含负） |
| 负环 | 行为未定义 | ✅ 检测 |
| 复杂度 | O((V+E) log V) | O(V·E) |
| 适合 | 路网、地图 | 金融、差分约束 |

## 参考文献

- Bellman, R. (1958). "On a routing problem." *Quarterly of Applied Mathematics*, 16, 87–90.
- Ford, L. R. (1956). RAND Technical Report P-923.
- CLRS 24.1。
