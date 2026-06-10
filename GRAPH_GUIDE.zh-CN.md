# 图输入惯用写法指南

> 🌐 Language: **简体中文** · [English](./GRAPH_GUIDE.md)

本指南面向从其他路径规划库（Rust `pathfinding`、Python `networkx`、C++
`boost::graph`）迁移到 `moonbit-pathfinding` 的用户，介绍如何把你已有的
图数据喂给本库的算法。

---

## 为什么不提供通用 `Graph` 结构？

`moonbit-pathfinding` 刻意**不**内置通用图结构。每个算法都接收一个
"后继函数"（successor function），签名是下面两种之一：

```moonbit skip
(N) -> Array[N]         // 无权图
(N) -> Array[(N, W)]    // 带权图
```

这么设计有三大好处：

1. **零耦合**：你原有的 SQL 行、HTTP 响应、文件句柄不必先拷贝进"图对象"
   再交给算法。
2. **极简类型**：节点 `N` 仅要求 `Eq + Hash`；权重 `W` 仅要求 `Weight`
   trait（内置 `Int` / `Double` 实现）。
3. **惰性友好**：棋盘、八数码、魔方等无限状态空间根本无法整体建图，纯函数
   正是它们的天然形式。

下面四种写法都可以 30 秒内转成 `successors`，按你的数据来源挑一种即可。

---

## 1. 邻接 Map · Adjacency Map

**类型签名**：

```moonbit skip
Map[N, Array[N]]           // 无权
Map[N, Array[(N, W)]]      // 带权
```

**适用场景**：节点是字符串、元组或自定义结构体；稀疏图；已从 JSON / YAML
导入成 `Map`。

**示例（字符串节点 + BFS）**：

```moonbit skip
let adj : Map[String, Array[String]] = Map::new()
adj["BJ"] = ["SH", "GZ"]
adj["SH"] = ["GZ", "HK"]
adj["GZ"] = ["HK"]
adj["HK"] = []
let path = @unweighted.bfs(
  "BJ",
  fn(n) { adj.get(n).or([]) },   // 兜底空数组避免 None 崩溃
  fn(n) { n == "HK" },
)
```

> **注意**：`adj.get(n)` 返回 `Option`，用 `.or([])` 兜底，防止孤立节点
> 触发 panic。

---

## 2. 邻接数组 · Adjacency Array

**类型签名**：

```moonbit skip
Array[Array[Int]]             // 无权（节点 0..n-1）
Array[Array[(Int, W)]]        // 带权
```

**适用场景**：节点 ID 连续整数 0..n-1；稠密图；从 stdin / CSV 解析好的
二维数组。

**示例（`Double` 权 Dijkstra）**：

```moonbit skip
let adj : Array[Array[(Int, Double)]] =
  [[(1, 1.5), (2, 5.0)], [(2, 2.5)], []]
let r = @directed.dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 2 })
// r == Some(([0, 1, 2], 4.0))
```

> **注意**：`adj[n]` 越界会 panic，请确保 `successors` 只在合法下标上调用。

---

## 3. 边列表 · Edge List

**类型签名**：

```moonbit skip
Array[(N, N, W)]             // (起点, 终点, 权重) 三元组
```

**适用场景**：原始 CSV 行、SQL 查询结果、网络协议；喂给 Kruskal MST
（边列表是它的原生输入）。

**示例（Kruskal MST）**：

```moonbit skip
let nodes = [0, 1, 2, 3]
let edges : Array[(Int, Int, Int)] =
  [(0, 1, 1), (1, 2, 2), (2, 3, 3), (0, 3, 10)]
let mst = @undirected.kruskal_mst(nodes, edges)
// mst == [(0, 1, 1), (1, 2, 2), (2, 3, 3)]  (3 条边, 总权 6)
```

> **提示**：无向图需要把每条边**双向**插入邻接表：
> `adj[u] += [v]` **和** `adj[v] += [u]`。

---

## 4. 惰性生成 · Lazy Generator

**类型签名**：

```moonbit skip
fn(N) -> Array[N]            // 纯函数，无需存图
fn(N) -> Array[(N, W)]
```

**适用场景**：**无限或天文级大**的状态空间（棋类、八数码、魔方）；
邻居由规则推导、不预存。

**示例（马走日 BFS）**：

```moonbit skip
let successors = fn(p : (Int, Int)) -> Array[(Int, Int)] {
  let (x, y) = p
  [(x+1, y+2), (x+1, y-2), (x-1, y+2), (x-1, y-2),
   (x+2, y+1), (x+2, y-1), (x-2, y+1), (x-2, y-1)]
}
let path = @unweighted.bfs((1, 1), successors, fn(p) { p == (4, 6) })
```

> **注意**：惰性生成器可能返回已访问节点，算法内部的 `visited` 表会
> 过滤；请保持纯函数性（同输入 ⇒ 同输出）。

---

## 速查表

| 你的数据是...                    | 选              | 跳到 |
|---------------------------------|----------------|-----|
| 已加载的 `Map`（JSON / YAML 来） | 邻接 Map        | §1  |
| 连续整数 ID `0..n-1`，稠密       | 邻接数组        | §2  |
| 原始 CSV 行，或 MST 问题         | 边列表          | §3  |
| 游戏局面、无限棋盘、逻辑规则     | 惰性生成        | §4  |

---

## 延伸阅读

- 完整英文双语版：[GRAPH_GUIDE.md](./GRAPH_GUIDE.md)
- 一分钟上手：[README.zh-CN.md](./README.zh-CN.md)
- 示例程序：[examples/maze_solver/](./examples/maze_solver/)、[examples/eight_puzzle/](./examples/eight_puzzle/)、[examples/network_routing/](./examples/network_routing/)
