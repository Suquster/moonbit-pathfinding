# Connected Components · 连通分量

## 背景

连通分量是图论最基础的结构性质之一：一张无向图 `G = (V, E)` 的一个**连通
分量**是 `V` 的一个极大子集，使得子集内任意两点之间都存在路径。对"无向图
的强连通分量"这一朴素版本，Hopcroft 与 Tarjan（1973）给出了线性时间的
DFS 标准方案；本库采用更易形式化的 **BFS 多源遍历** 变体。

## 核心思想

**"对每个尚未访问的节点做一次 BFS，把遍历到的节点归为同一分量"**。
每个节点最多被访问一次，总代价 O(V + E)。

## 算法步骤

```
visited ← {}
components ← []
for s in nodes:
  if s ∈ visited: continue
  // 以 s 为起点做 BFS，收集所有可达节点
  queue ← [s]
  comp ← []
  visited.add(s)
  while queue 非空:
    u ← queue.dequeue()
    comp.push(u)
    for v in successors(u):
      if v ∉ visited:
        visited.add(v)
        queue.enqueue(v)
  components.push(comp)
return components
```

本库在无向图上使用；输入方的 `successors` 需满足"若 v 在 successors(u) 中，
则 u 也在 successors(v) 中"。**有向图**的"强连通分量"应使用 Tarjan SCC
（见 `tarjan_scc.md`），语义完全不同。

## 时间复杂度

- **时间** O(V + E)：每个节点出队一次，每条边被扫描一次；
- **空间** O(V)：`visited`、`queue`、`components`。

## 典型场景

1. **预处理图**：先求连通分量，再对每个分量独立跑单源最短路、MST 等；
2. **社交网络分析**：朋友网络的"朋友圈"识别；
3. **图形学**：像素级 Flood Fill 用 4-邻接或 8-邻接的连通分量；
4. **依赖管理**：判断模块依赖图是否分裂成多个独立闭包；
5. **PBT 辅助**：本库用它做"可达性的可解释答案"，与 BFS 的可达性断言
   交叉验证。

## MoonBit API 示例

```moonbit
let nodes = [0, 1, 2, 3]
let adj : Array[Array[Int]] = [[1], [0], [3], [2]]     // {0,1} 与 {2,3}
let comps = @undirected.connected_components(nodes, fn(n) { adj[n] })
// comps.length() == 2
```

测试中还覆盖了"单节点图返回 [[0]]"、"全孤立节点返回 n 个单点分量"等
边界（见 `cc_test.mbt` 与本库 whitebox 用例）。

## 与强连通分量（SCC）区分

| 维度 | Connected Components | Strongly Connected Components |
|------|---------------------|-------------------------------|
| 适用 | **无向**图 | **有向**图 |
| 定义 | 任意两点间有路径 | 任意两点**双向**可达 |
| 算法 | BFS/DFS + 标记 | Tarjan / Kosaraju |
| 复杂度 | O(V + E) | O(V + E) |

## 参考文献

- Hopcroft, J., & Tarjan, R. (1973). "Algorithm 447: Efficient algorithms for
  graph manipulation." *CACM*, 16(6), 372–378.
- CLRS 22.3。
