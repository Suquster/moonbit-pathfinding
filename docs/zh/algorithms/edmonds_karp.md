# Edmonds-Karp · 最大流（Max-Flow）

## 背景

Ford 与 Fulkerson 1956 年提出的"增广路径法"奠定了最大流理论基础，但其
最坏情形复杂度依赖于容量，可能指数级。Jack Edmonds 与 Richard Karp 在
1972 年的论文 *Theoretical Improvements in Algorithmic Efficiency for
Network Flow Problems* 中证明：**如果每次都选最短（BFS）增广路径**，整体
复杂度便限制在 `O(V · E²)`——与容量无关。这便是 Edmonds-Karp 算法，至今
是**教材级的最大流入门方案**。

## 核心思想

"最大流"问题：给定有向网络 `G = (V, E)`，每边 `(u, v)` 有容量 `c(u, v) ≥ 0`，
源点 `s`、汇点 `t`，找到从 `s` 到 `t` 的**最大单源单汇流量**。

**Ford-Fulkerson 框架**：在"残量图"上反复找增广路径并把瓶颈容量加进总流，
直到没有增广路径为止。"残量图"的巧妙之处：正向边剩余容量、反向边累计流
既可撤销，使得**局部错误决策**能在后续迭代中自动修正。

**Edmonds-Karp 特化**：增广路径选**BFS 的最短路径（按边数）**，这保证了
多项式复杂度。

## 算法步骤

```
residual[u][v] ← c(u, v) for all edges  // 初始化残量图
for 每对 (u, v): residual[v][u] ← 0        // 反向边初值 0
max_flow ← 0
while 存在从 s 到 t 的增广路径 P (通过 BFS 在残量图上找):
  bottleneck ← min residual[u][v] for (u, v) in P
  for (u, v) in P:
    residual[u][v] -= bottleneck
    residual[v][u] += bottleneck          // 反向边累积流，可用于撤销
  max_flow += bottleneck
return max_flow
```

## 时间复杂度

- **时间** O(V · E²)：BFS 单次 O(E)，增广路径总数上限为 O(V · E)；
- **空间** O(V²)：残量图用邻接矩阵（本库实现）；稀疏图可改邻接表降到 O(V + E)。

现代生产级方案会用 **Dinic 算法**（O(V² · E)，稠密图更优）或
**Push-Relabel**（O(V² · √E)），本库作为教学与**小规模 max-flow**工具首选
Edmonds-Karp。

## 典型场景

1. **二分图最大匹配**：拆点建图后跑 max-flow，得到匹配数（本库另有
   Kuhn-Munkres 处理**带权**匹配）；
2. **最小割**：Max-Flow Min-Cut 定理——最大流值等于最小割容量，可用于
   图像分割、关键路径识别；
3. **任务分配**：车间调度、云资源分配等；
4. **网络设计**：评估骨干网在节点失效后的容量瓶颈。

## MoonBit API 示例

```moonbit
let nodes = [0, 1, 2, 3]
let cap : Map[(Int, Int), Int] = Map::new()
cap[(0, 1)] = 3; cap[(0, 2)] = 2
cap[(1, 2)] = 1; cap[(1, 3)] = 2; cap[(2, 3)] = 3
let flow = @directed.edmonds_karp(nodes, cap, 0, 3)
// flow == 5  (0→1→3 = 2, 0→2→3 = 2, 0→1→2→3 = 1)
```

Min-cut 验证：切分 `S = {0}` 的横跨边 `0→1 (3) + 0→2 (2) = 5`，与 max-flow
值一致，符合 **Max-Flow Min-Cut 定理**。

本库**whitebox 用例**覆盖：`source == sink` 时流值为 0（BFS 立刻命中
`visited[sink]` 触发 `continue`，外层 while 通过 `!found` break）。

## 参考文献

- Edmonds, J., & Karp, R. M. (1972). "Theoretical Improvements in Algorithmic
  Efficiency for Network Flow Problems." *JACM*, 19(2), 248–264.
- Ford, L. R., & Fulkerson, D. R. (1956). "Maximal flow through a network."
  *Canadian J. of Math.*, 8, 399–404.
- CLRS 26.2。
