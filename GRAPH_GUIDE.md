# Graph Guide · 图输入惯用写法

> 🌐 Language: **English + 简体中文（双语）** · [纯中文版](./GRAPH_GUIDE.zh-CN.md)

> **English body + 中文批注** · 目标读者 / Target audience:
> 从其他 pathfinding 库（Rust `pathfinding`、Python `networkx`、C++ `boost::graph`）迁移过来的用户。
> Users migrating from other pathfinding libraries who are looking for
> the idiomatic way to feed a graph into `moonbit-pathfinding`.

---

## Why no `Graph` struct? · 为什么不提供通用图结构？

`moonbit-pathfinding` deliberately ships **no built-in `Graph` type**. Instead,
every algorithm accepts a **successor function** of one of the two shapes:

```moonbit skip
(N) -> Array[N]         // unweighted   · 无权
(N) -> Array[(N, W)]    // weighted     · 带权
```

本库刻意**不**提供通用 `Graph` 结构体，而是让每个算法接收一个"邻居函数"。
好处有三：

1. **零耦合** · Zero coupling — 你原有的数据结构（SQL 行、HTTP 客户端、文件句柄）不必拷贝一份进"图对象"再丢给算法。
2. **极简类型** · Minimal types — 节点 `N` 只需满足 `Eq + Hash`；权重 `W` 只需实现 `Weight` trait（内置 `Int` / `Double`）。
3. **惰性友好** · Lazy-friendly — 棋盘、八数码等无限状态空间本来就**无法**整体建图；纯函数恰好是它们的天然形式。

The four idioms below are all **30-second conversions** to the `successors`
function. Pick whichever matches your data source.
下列四种惯用写法都能在 30 秒内转成 `successors`，按数据来源挑一种即可。

---

## 1. Adjacency Map · 邻接 Map

**Type signature / 类型签名**

```moonbit skip
Map[N, Array[N]]           // unweighted · 无权
Map[N, Array[(N, W)]]      // weighted   · 带权
```

**When to use · 何时使用**

- Nodes are strings, tuples, or custom structs (`derive(Eq, Hash)`).
  节点是字符串、元组或自定义结构体。
- Sparse graph, unknown node count up-front. 稀疏图，节点数事先未知。
- You already hold the graph in a `Map` (e.g. JSON imported). 已有 `Map` 数据。

**Example 1 · BFS on a city graph (String nodes)**

```moonbit skip
// Cities and their direct flight connections · 城市与直飞航线
let adj : Map[String, Array[String]] = Map::new()
adj["BJ"] = ["SH", "GZ"]      // Beijing   → Shanghai, Guangzhou
adj["SH"] = ["GZ", "HK"]      // Shanghai  → Guangzhou, Hong Kong
adj["GZ"] = ["HK"]
adj["HK"] = []
let path = @unweighted.bfs(
  "BJ",
  fn(n) { adj.get(n).or([]) },   // Map → successor function · 转适配器
  fn(n) { n == "HK" },
)
// path == Some(["BJ", "SH", "HK"])   // 2 hops · 2 跳即达
```


**Example 2 · Dijkstra on a weighted Map (struct nodes)**

```moonbit skip
struct Pos { x : Int; y : Int } derive(Eq, Hash)
let adj : Map[Pos, Array[(Pos, Int)]] = Map::new()
adj[Pos::{x:0,y:0}] = [(Pos::{x:1,y:0}, 3), (Pos::{x:0,y:1}, 5)]
adj[Pos::{x:1,y:0}] = [(Pos::{x:0,y:1}, 1)]
adj[Pos::{x:0,y:1}] = []
let r = @directed.dijkstra(
  Pos::{x:0,y:0},
  fn(n) { adj.get(n).or([]) },
  fn(n) { n == Pos::{x:0,y:1} },
)
// r == Some(([Pos{x:0,y:0}, Pos{x:1,y:0}, Pos{x:0,y:1}], 4))
```

> **Pitfall · 注意**: `adj.get(n)` 返回 `Option[Array[...]]`。
> 用 `.or([])` 兜底，否则遇到孤立节点会 panic。
> Always use `.or([])` to handle nodes missing from the map (isolated nodes).

---

## 2. Adjacency Array · 邻接数组

**Type signature / 类型签名**

```moonbit skip
Array[Array[Int]]             // unweighted · 无权 (节点编号 0..n-1)
Array[Array[(Int, W)]]        // weighted   · 带权
```

**When to use · 何时使用**

- Node IDs are contiguous integers `0..n-1`. 节点可压缩为 `0..n-1` 整数。
- Dense graph or performance-critical path. 稠密图或追求极致性能。
- You parsed `stdin` / CSV into a vector of vectors already. 已经从 stdin / CSV 解析成二维数组。

**Example 1 · BFS on a 4-node chain (shape used in our internal test suite)**

```moonbit skip
// 0 → 1 → 2 → 3    · chain graph
let adj : Array[Array[Int]] = [[1], [2], [3], []]
let path = @unweighted.bfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
// path == Some([0, 1, 2, 3])
```

**Example 2 · Dijkstra with `Double` weights**

```moonbit skip
// 0 --(1.5)--> 1 --(2.5)--> 2     shorter than direct 0 -(5.0)-> 2
let adj : Array[Array[(Int, Double)]] =
  [[(1, 1.5), (2, 5.0)], [(2, 2.5)], []]
let r = @directed.dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 2 })
// r == Some(([0, 1, 2], 4.0))    // 1.5 + 2.5 = 4.0
```

> **Pitfall · 注意**: `adj[n]` 越界会 panic. 请先保证 `successors` 仅在合法下标上被调用。
> `adj[n]` panics on out-of-bounds; constrain your graph so the algorithm never queries invalid indices.


---

## 3. Edge List · 边列表

**Type signature / 类型签名**

```moonbit skip
Array[(N, N, W)]             // (u, v, weight) triples
```

**When to use · 何时使用**

- Imported from a CSV file, SQL rows, or a network protocol. 来自 CSV、SQL 行或网络协议的原始数据。
- Feeding **Kruskal's MST** (accepts edge list natively).
  用于 Kruskal 最小生成树算法（原生接受边列表）。
- Edges are the primary objects; adjacency is not needed. 只关心边本身。

**Example 1 · Kruskal MST directly on an edge list**

```moonbit skip
// Undirected weighted graph · 无向加权图
let nodes : Array[Int] = [0, 1, 2, 3]
let edges : Array[(Int, Int, Int)] =
  [(0, 1, 1), (1, 2, 2), (2, 3, 3), (0, 3, 10)]
let mst = @undirected.kruskal_mst(nodes, edges)
// mst == [(0, 1, 1), (1, 2, 2), (2, 3, 3)]   // 3 条边,总权 6
```

**Example 2 · Edge list → adjacency → BFS (one-shot converter)**

```moonbit skip
// Build an adjacency map in one pass · 一次遍历建邻接表
let edges = [(0, 1), (1, 2), (2, 3), (0, 3)]
let adj : Map[Int, Array[Int]] = Map::new()
for e in edges { let (u, v) = e
  adj[u] = adj.get(u).or([]) + [v]
}
let path = @unweighted.bfs(0, fn(n) { adj.get(n).or([]) }, fn(n) { n == 3 })
// path == Some([0, 3])    // BFS picks the shortcut · BFS 自动走最短
```

> **Tip · 提示**: For **undirected** graphs, push each edge twice: `adj[u] += [v]` **和** `adj[v] += [u]`.
> 无向图需把每条边双向插入邻接表。

---

## 4. Lazy / On-the-fly Generator · 惰性生成

**Type signature / 类型签名**

```moonbit skip
fn(N) -> Array[N]            // pure function · 纯函数,无需显式存图
fn(N) -> Array[(N, W)]
```

**When to use · 何时使用**

- **Infinite or astronomically large** state spaces (chess, 8-puzzle, Rubik's cube).
  状态空间无限或天文级大（棋类、八数码、魔方）。
- Neighbors are derived by a rule, not stored. 邻居由规则推导，不预存。
- Want to decouple algorithm from storage entirely. 想把算法与存储完全解耦。


**Example 1 · Knight's tour on an infinite board (BFS)**

```moonbit skip
// 8 legal knight moves, computed on demand · 8 种马走日,按需生成
let successors = fn(p : (Int, Int)) -> Array[(Int, Int)] {
  let (x, y) = p
  [(x+1, y+2), (x+1, y-2), (x-1, y+2), (x-1, y-2),
   (x+2, y+1), (x+2, y-1), (x-2, y+1), (x-2, y-1)]
}
let path = @unweighted.bfs((1, 1), successors, fn(p) { p == (4, 6) })
// path.unwrap().length() == 5   // classic Rust-pathfinding example
```

**Example 2 · A\* on a grid with Manhattan heuristic (weighted, lazy)**

```moonbit skip
// 4-direction grid, each step cost 1; heuristic = Manhattan distance
let goal_pt = (5, 5)
let succ = fn(p : (Int, Int)) -> Array[((Int, Int), Int)] {
  let (x, y) = p
  [((x+1, y), 1), ((x-1, y), 1), ((x, y+1), 1), ((x, y-1), 1)]
}
let h = fn(p : (Int, Int)) -> Int {
  let (x, y) = p; (x - 5).abs() + (y - 5).abs()
}
let r = @directed.astar((0, 0), succ, h, fn(p) { p == goal_pt })
// r == Some((<path of 11 points>, 10))
```

> **Pitfall · 注意**: Lazy successors can return **already-visited** nodes —
> the algorithm's `visited` map filters them out, but keep the `successors`
> pure so repeated calls yield the same list.
> 惰性生成器可能返回已访问节点，算法内部的 visited 表会过滤；请保持纯函数性（同输入同输出）。

---

## Quick Picker · 快速选型表

| Your data is... · 你的数据是...           | Pick this · 选                | Jump to · 跳到 |
|--------------------------------------------|------------------------------|---------------|
| `Map` already loaded from JSON / YAML      | Adjacency Map · 邻接 Map     | §1            |
| Integer IDs `0..n-1`, dense                | Adjacency Array · 邻接数组    | §2            |
| Raw CSV rows, or MST problem               | Edge List · 边列表            | §3            |
| Game state, infinite board, logical rule   | Lazy generator · 惰性生成     | §4            |

---

## Inter-conversion Cheatsheet · 互相转换速查

```moonbit skip
// Edge list → Adjacency Map
let adj : Map[Int, Array[Int]] = Map::new()
for e in edges { let (u, v) = e; adj[u] = adj.get(u).or([]) + [v] }

// Adjacency Array → successors function (just index) · 直接索引
let succ = fn(n : Int) { adj_array[n] }

// Adjacency Map → successors function · 配默认空数组
let succ = fn(n : N) { adj_map.get(n).or([]) }

// Lazy generator → anything else? · 不必转换,它本身就是 successors
```

---

## See also · 延伸阅读

- `README.md` — 1-minute quickstart and algorithm menu · 一分钟上手与算法菜单
- `examples/maze_solver/` — BFS on a 2-D maze using the lazy-generator idiom
- `examples/network_routing/` — Dijkstra on an edge-list-imported topology
- `examples/eight_puzzle/` — A\* on an infinite state space (lazy)
- `src/directed/` / `src/undirected/` / `src/unweighted/` — 完整 API 签名

---

<!-- Document version: v0.2.0 · maps to design.md §4.3 · Requirements R9.2 -->
