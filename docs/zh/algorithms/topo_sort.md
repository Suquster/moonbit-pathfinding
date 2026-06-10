# Topological Sort · 拓扑排序（Kahn 算法）

## 背景

拓扑排序回答的问题是："给定一张有向无环图 DAG，能否找到一个节点顺序，
使得**所有边都指向后方**？"这个问题由 Arthur Kahn 在 1962 年给出第一个
线性时间算法，被 Unix `make`、Rust `cargo`、MoonBit `moon` 等构建系统，
以及课程先修关系、任务调度、电路综合等领域广泛使用。

## 核心思想

**"循环地找入度为 0 的节点并移除"**：

- 若图有环，则环上任何节点都永远不会变成入度 0 — 算法因此**天然检测环**；
- 若图是 DAG，则每次"入度 0"节点集合非空，依次取出即可得到一个合法拓扑序。

不同实现的差异在于**选哪个节点**：Kahn 用 BFS 队列（按入度 0 先进先出，
结果稳定可复现），Tarjan 的 DFS 版本用逆后序遍历（不易回溯，但能同时
检测环的强连通分量）。

## 算法步骤（Kahn，本库实现）

```
in_degree[v] ← 0 for all v
for u in nodes:
  for v in successors(u):
    in_degree[v] += 1
queue ← [ v | in_degree[v] == 0 ]
result ← []
while queue 非空:
  u ← queue.dequeue()
  result.push(u)
  for v in successors(u):
    in_degree[v] -= 1
    if in_degree[v] == 0: queue.enqueue(v)
if len(result) != len(nodes): return Err(CycleDetected)
else:                         return Ok(result)
```

## 时间复杂度

- **时间** O(V + E)：每节点入队出队各一次，每边被扫描两次（一次算入度、
  一次递减）；
- **空间** O(V)：入度数组 + 队列 + 结果数组。

## 典型场景

1. **编译系统依赖排序**：Unix `make` 判断源文件编译次序，MoonBit `moon`
   判断包编译次序——这正是 `moon check` 内部使用拓扑排序的场景。
2. **课程先修关系**：给定"数据结构 → 算法 → 分布式系统"链条，找一条合法
   学习顺序。
3. **电路综合 / 信号流**：数字电路中"门电路 A 的输出 = 门电路 B 的输入"
   构成 DAG，拓扑序等价于信号逐级传播的顺序。
4. **数据库批处理**：ETL 流水线的依赖图展开为一次一次的 batch job 顺序。
5. **Spreadsheets 公式重算**：Excel 单元格公式依赖图必须拓扑排序才能逐个
   计算。

## 环检测能力

若输入图有环，则一定存在节点的入度永远大于 0，无法进入 `queue`。最终
`result` 数组长度会**少于** `nodes` 长度——这个差异正是 Kahn 算法的
"环指纹"，本库用它返回 `Err(@core.CycleDetected)`。

## MoonBit API 示例

```moonbit
// DAG: 0 → {1, 2}；1 → 3；2 → 3
let nodes = [0, 1, 2, 3]
let adj : Array[Array[Int]] = [[1, 2], [3], [3], []]
match @directed.topological_sort(nodes, fn(n) { adj[n] }) {
  Ok(order) => println(order)       // [0, 1, 2, 3] 或 [0, 2, 1, 3]
  Err(_)    => println("环")
}
```

## Kahn vs DFS 逆后序

| 维度 | Kahn (BFS) | DFS 逆后序 |
|------|-----------|-----------|
| 易理解 | ✅ 迭代、入度直观 | 略绕（需"后序"思想）|
| 环检测 | `len(result) < V` | 显式栈 `on_stack` 判断 |
| 并行化 | 天然（每一层入度 0 节点可并发）| 串行 DFS |
| 本库选择 | ✅ | — |

## 参考文献

- Kahn, A. B. (1962). "Topological sorting of large networks." *CACM*, 5(11), 558–562.
- Tarjan, R. (1972). *SIAM Journal on Computing*, 1(2), 146–160.
- CLRS 22.4。
