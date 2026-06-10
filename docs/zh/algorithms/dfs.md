# DFS · 深度优先搜索

## 背景

DFS（Depth-First Search）是与 BFS 对偶的搜索框架，早在 19 世纪末就被
Trémaux 用于迷宫求解；Tarjan 在 1972 年将它工程化为图算法的基石，后续的
SCC、桥割、拓扑排序都基于 DFS 结构。

## 核心思想

维护一个显式 LIFO 栈（避免 MoonBit 递归深度限制），每次弹出栈顶节点 `u`，
**立刻**将其所有未访问邻居压栈；这样算法会"一路钻到底"，碰到死路才回溯。

> 注意：本库使用**显式栈**而非递归，确保在深度为 10 万级的路网 / 棋盘
> 上不会栈溢出。

## 算法步骤

```
stack ← [start]
visited ← {}
while stack 非空:
  u ← stack.pop()
  if u ∈ visited: continue
  visited.add(u)
  if goal(u): 返回回溯路径
  for v in successors(u): stack.push(v)
return None
```

## 时间复杂度

- **时间** O(V + E)
- **空间** O(V) 栈 + `visited`

## 典型场景

1. **判断可达性**：不关心最短，只问"是否存在路径"
2. **回溯枚举**：全排列 / N 皇后 / 数独
3. **拓扑排序辅助**：逆后序即拓扑序（本库 `topo_sort.mbt` 用 Kahn 替代）
4. **强连通分量**：Tarjan SCC 基于 DFS 的 `index / lowlink` 双栈

## MoonBit API 示例

```moonbit
let adj : Array[Array[Int]] = [[1, 3], [2, 3], [0], []]
let path = @directed.dfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
// path 可能是 [0, 3] 或 [0, 1, 3]（DFS 不保证最短）
```

## 与 BFS 的取舍

| 指标 | BFS | DFS |
|------|-----|-----|
| 最短路（无权）| ✅ 保证 | ❌ 不保证 |
| 内存占用 | O(b^d) | O(d) |
| 适合场景 | 浅解 | 深/回溯 |

## 参考文献

- Tarjan, R. E. (1972). "Depth-first search and linear graph algorithms."
  *SIAM Journal on Computing*, 1(2), 146–160.
- CLRS 22.3（深度优先搜索）
