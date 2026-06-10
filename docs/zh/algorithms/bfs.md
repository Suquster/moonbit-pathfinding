# BFS · 广度优先搜索

## 背景

BFS（Breadth-First Search）是图算法中最基本的搜索框架，由 Moore 在 1959 年
研究迷宫求解时正式提出。它按"距离由近及远"的次序遍历图，因此在**无权图**
上天然给出**最短路径**（以边数为度量）。

## 核心思想

维护一个 FIFO 队列与一个 `visited` 集合。每次从队首取出节点 `u`，扩展它
所有尚未访问的邻居并入队。由于队列保持"先入先出"，所有第 1 层节点会在
第 2 层之前出队，从而保证**第一次**访问目标节点时，到达它的路径就是最短的。

## 算法步骤

```
queue ← [start]
visited ← {start}
parents ← {}
while queue 非空:
  u ← queue.dequeue()
  if goal(u): 回溯 parents 构造路径并返回
  for v in successors(u):
    if v ∉ visited:
      visited.add(v)
      parents[v] ← u
      queue.enqueue(v)
return None
```

## 时间复杂度

- **时间** O(V + E)：每个节点出队恰一次，每条边被检查恰一次。
- **空间** O(V)：`visited` / `parents` / `queue` 最多各 V 项。

## 典型场景

1. **迷宫最短路径**：字符网格 `#` 墙 / `.` 通 / `S` 起点 / `G` 终点
2. **社交关系 N 度人脉**：朋友的朋友的朋友
3. **棋盘状态空间搜索**：国际象棋"马走日"最短步数（本库 `tests/pbt/gen.mbt`
   与 `examples/maze_solver/` 都使用这个范式）
4. **网页爬虫**：按层次爬取避免无限深度

## MoonBit API 示例

```moonbit
let adj : Array[Array[Int]] = [[1], [2], [3], []]
let path = @unweighted.bfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
// path == Some([0, 1, 2, 3])
```

泛型节点类型 `N` 只需 `Eq + Hash`，既可用 `Int` / `String`，也可用自定义
`struct Pos derive(Eq, Hash)`（见 `bfs_test.mbt` 的用例 5、6）。

## 参考文献

- Moore, E. F. (1959). "The shortest path through a maze."
  *Proc. Int. Symp. Switching Theory*, Harvard University.
- CLRS 22.2（广度优先搜索）
