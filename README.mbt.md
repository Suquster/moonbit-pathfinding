# moonbit-pathfinding · 可执行文档

> **严谨工程化的 MoonBit 路径规划库** — 15+ 图算法 · WASM 原生 · 三后端一致 · 可执行文档。
>
> 本文件既是项目 README,**也是**一份可执行测试脚本: 每段 ` ```mbt check ` 代码块都会被
> `moon test README.mbt.md` 编译 + 运行 + 快照校验。文档永不过时,过时即构建失败。

---

## 为什么是这份 README?

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性: 放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box
test 编译执行。对应需求 **R24 (可执行文档)** 与 tasks.md **M2 任务 19.1**。

与传统 README 相比,这里的每一行算法调用都:

- 通过 `moon check` 的静态类型检查
- 被 `moon test README.mbt.md` 实际执行
- 通过 `inspect(value, content="...")` 做快照断言
- 在 CI 里作为一道硬性门禁(tasks.md 19.2)

下面 6 段示例分别覆盖 **BFS / Dijkstra / A\* / Kruskal MST / 形式化证明片段 / 复杂度表**,每段都可独立
复制到你的项目里使用。其后的 **Cookbook** 再以 22 个真实用例覆盖网格寻路 / 网络路由 /
任务调度 / 最大流 / 匹配五类场景。

> **关于代码围栏**: 本文件的可执行代码块均以 ` ```mbt check ` 开头,这是 MoonBit toolchain
> 识别可运行代码块的标记; 块首的 `///|` 是 MoonBit 的 top-level marker,用于声明该段为一个
> 独立条目。如需在 README 里展示**不**被执行的片段,把围栏改为 ` ```moonbit skip ` (本文件
> 示例 5 中展示)。

---

## 示例 1 · BFS 在邻接数组上求 4 步最短路

BFS (Breadth-First Search) 是**无权图最短路径**的标准答案。给定一张用 `Array[Array[Int]]`
表示的邻接表 (节点 `0..3` 链成 `0 → 1 → 2 → 3`),下面 5 行代码就能拿到长度为 4 的最短路径。

对应 **R1-AC1 (MVP 算法集)** 与 tasks.md **5.x (BFS 巩固)**。

```mbt check
///|
test "README · BFS finds 4-node path on linear adjacency array" {
  // 节点 0..3 串成一条链; successors 直接在邻接数组上查询。
  let adj : Array[Array[Int]] = [[1], [2], [3], []]
  let path = @uw.bfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  // path[0] == start, goal(path[-1]), 相邻节点均在 successors 中 (R13.2)
  match path {
    Some(p) => {
      assert_true(p.length() == 4)
      assert_true(p[0] == 0 && p[1] == 1 && p[2] == 2 && p[3] == 3)
    }
    None => assert_true(false)
  }
}
```

---

## 示例 2 · Dijkstra 在带权图上求最小代价

Dijkstra 算法处理**非负权有向图**的最短路径。考虑 4 节点图:

```
0 ─(1)─▶ 1      0 ─(4)─▶ 2
1 ─(2)─▶ 2      1 ─(5)─▶ 3
2 ─(1)─▶ 3
```

两条候选 0→3: `0→1→2→3` 代价 `1+2+1=4`, `0→2→3` 代价 `4+1=5`, `0→1→3` 代价 `1+5=6`。
Dijkstra 应返回代价 **4** 的最短路径。

对应 **R1-AC1** 与 tasks.md **6.x (Dijkstra 实现)**。

```mbt check
///|
test "README · Dijkstra picks cheapest of three candidate paths" {
  // 每个元素是 (邻居索引, 边权)
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 1), (2, 4)], //  0: 0->1(1), 0->2(4)
    [(2, 2), (3, 5)], //  1: 1->2(2), 1->3(5)
    [(3, 1)], //          2: 2->3(1)
    [], //                3: 目标,无出边
  ]
  let result = @dir.dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  match result {
    Some((path, cost)) => {
      inspect(cost, content="4")
      inspect(path, content="[0, 1, 2, 3]")
    }
    None => inspect("unreachable", content="should have found a path")
  }
}
```

---

## 示例 3 · A\* 在网格图上用曼哈顿启发式

A\* 算法在 Dijkstra 基础上加一个启发式函数 `heuristic : (N) -> W`,在满足 **Admissible**
(不高估真实代价) 的前提下依然能求得最优解,但扩展节点数远少于 Dijkstra。

下面在 3×3 网格图上用**曼哈顿距离** `|dx| + |dy|` 作为启发式,4 向移动每步代价 1,
从 `(0,0)` 走到 `(2,2)` 的最短代价应为 4 (曼哈顿下界)。

对应 **R1-AC1 / R13-AC8 (Admissible → astar == dijkstra 距离)** 与 tasks.md **7.x**。

```mbt check
///|
test "README · A-star on 3x3 grid with manhattan heuristic" {
  // 4-方向移动, 每步代价 1
  let successors = fn(pos : (Int, Int)) -> Array[((Int, Int), Int)] {
    let (x, y) = pos
    let neighbors = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    let filtered : Array[((Int, Int), Int)] = []
    for p in neighbors {
      let (nx, ny) = p
      if nx >= 0 && nx < 3 && ny >= 0 && ny < 3 {
        filtered.push((p, 1))
      }
    }
    filtered
  }
  // Admissible heuristic: 到 (2,2) 的曼哈顿距离
  let heuristic = fn(pos : (Int, Int)) -> Int {
    let (x, y) = pos
    (2 - x).abs() + (2 - y).abs()
  }
  let result = @dir.astar((0, 0), successors, heuristic, fn(p) { p == (2, 2) })
  match result {
    Some((_path, cost)) => inspect(cost, content="4")
    None => inspect("unreachable", content="goal should be reachable")
  }
}
```

---

## 示例 4 · Kruskal 最小生成树

Kruskal 算法求**连通无向图的最小生成树 (MST)**: 把所有边按权升序排,用并查集 (DSU)
检测是否形成环,非环则加入 MST。下图是一个 4 节点环 + 内部对角线,最小生成树应包含
3 条边,总权重为 `1 + 2 + 3 = 6`。

```
0 ─(1)─ 1
│       │
(4)    (2)
│       │
3 ─(3)─ 2
```

对应 **R1-AC1 / R13.4 (MST 结构不变式)** 与 tasks.md **15.x (Kruskal)**。

```mbt check
///|
test "README · Kruskal MST picks 3 edges with total weight 6" {
  let nodes = [0, 1, 2, 3]
  // 边列表: (u, v, w), 无向图按无序对解读
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (1, 2, 2),
    (2, 3, 3),
    (3, 0, 4),
  ]
  let mst = @und.kruskal_mst(nodes, edges)
  // MST 应恰好有 |V| - 1 = 3 条边 (R13.4)
  inspect(mst.length(), content="3")
  // 总权重: 1 + 2 + 3 = 6
  let total = mst.fold(init=0, fn(acc, e) {
    let (_, _, w) = e
    acc + w
  })
  inspect(total, content="6")
}
```

---

## 示例 5 · 可执行 proof predicates

> **状态**: runtime-checked today; static `moon prove` discharge remains
> toolchain-dependent.
>
> `src/proofs/*_proof.mbt` already encodes the proof vocabulary as ordinary
> MoonBit predicates and runtime tests. The same predicates are intended to be
> referenced by future stable `moon prove` annotations.

下面这段可执行测试直接调用 BFS 的聚合后置条件。它覆盖 start/end/edge-validity、
minimality 与 None-witness 这组合约，而不是只展示未来语法。

```mbt check
///|
test "README · BFS proof predicate accepts shortest witness" {
  let adj : Array[Array[Int]] = [[1], [2], [3], []]
  let result : Array[Int]? = Some([0, 1, 2, 3])
  inspect(
    @proofs.bfs_post(result, 0, fn(n) { adj[n] }, fn(n) { n == 3 }, [0, 1, 2, 3]),
    content="true",
  )
}
```

下面这段代码展示**未来版本**里 Dijkstra 源码会带上的 Loop Invariant 注释; 围栏标 `skip`
让 `moon test README.mbt.md` **跳过执行** (避免引用尚未实现的 `moon prove` 语法)。

对应需求 **R8 (形式化证明撒手锏)**、**R8-AC4 (显式 invariant 注释)**、tasks.md **33.3 / 34.x**。

```moonbit skip
///|
/// Dijkstra shortest paths on non-negative weighted graphs.
///
/// # Invariants (R8-AC4)
/// - For every v with dist[v] < infinity, dist[v] is the cost of some valid
///   path from start to v.
/// - For every v popped from pq (and not dropped as a stale entry), dist[v]
///   is already the final shortest distance.
/// - All edge weights are non-negative => dist[v] >= Weight::zero() for
///   every reachable v.
pub fn[N : Eq + Hash, W : Weight] dijkstra(
  start : N,
  successors : (N) -> Array[(N, W)],
  goal : (N) -> Bool,
) -> (Array[N], W)? {
  let pq = PQueue::new()
  let dist : Map[N, W] = Map::new()
  let parents : Map[N, N] = Map::new()
  dist[start] = Weight::zero()
  pq.push(Weight::zero(), start)
  /// invariant: forall v popped from pq (non-stale), dist[v] is final
  /// invariant: forall v with dist[v] < infinity, exists valid path start->v
  /// invariant: all edge weights >= zero => dist[v] >= Weight::zero()
  while pq.pop() is Some((d, u)) {
    if goal(u) {
      return Some((reconstruct(parents, u), d))
    }
    // ... 松弛 successors(u) ...
  }
  None
}
```

当本地工具链提供稳定证明语法后,上面的 `/// invariant:` 行将被替换成真实的
`moon prove` 前后置条件 (见 design.md §7.3):

```moonbit skip
#requires(/* successors is total */)
#ensures(forall v : N. reachable(v) -> dist[v] >= Weight::zero())
#decreases(nodes.length() - visited.length())
pub fn[N : Eq + Hash, W : Weight] dijkstra(...) -> ... { ... }
```

届时 `moon prove` 会静态验证:

1. **非负距离性质**: 所有可达节点的 `dist[v] >= 0` (R8.2(a))
2. **终止性**: 每次迭代 `|V| - |visited|` 严格递减 (R8.2(b))
3. **首末节点合法**: `path[0] == start /\ goal(path[-1])` (R8.1)

> 💡 只有 ` ```mbt check ` 围栏的代码块会参与测试；` ```moonbit skip ` 仍用于展示
> 尚未稳定的未来 `moon prove` 语法。

---

## 示例 6 · 自动生成算法复杂度表（文档即数据）

本库的算法复杂度表不是手写维护的静态文本，而是由 `@docgen` 从**结构化元数据**
（精确结构体 `AlgoMeta`，而非字符串模拟结构）自动生成的 Markdown 表格。
`@docgen.algorithm_metadata()` 返回恰好 33 条元数据：30 种经典图/路径算法
（与上文「算法目录」编号 1–30 一一对应）外加 Contraction Hierarchies、
Jump Point Search 与 ALT 三种旗舰高级算法；`@docgen.complexity_table()` 以
`TextBuilder` 顺序追加片段、O(n) 线性物化，**绝不在循环内做字符串 `+` 拼接**。

对应需求 **R19 (自动生成算法复杂度表)** — R19.1 (五个非空字段)、
R19.2 (恰好 33 行、唯一对应、无重复无遗漏)、R19.3 (元数据变更后逐字段重新生成)。

下面这段可执行测试调用同一对 API，断言其生成的复杂度表恰好覆盖 33 种算法、
表头与对齐行齐备，并验证「同一元数据重复生成结果逐字符相等」的可重复性。

```mbt check
///|
test "README · docgen 复杂度表覆盖 33 种算法且可重复生成" {
  // 元数据数组恰好 33 条：30 种经典算法 + CH / JPS / ALT（R19.2）。
  let metas = @docgen.algorithm_metadata()
  inspect(metas.length(), content="33")
  inspect(@docgen.algorithm_count, content="33")
  // R19.3：同一元数据重复生成 → 复杂度表逐字段完全相等（确定性、可重复）。
  let r1 = @docgen.complexity_table(metas)
  let r2 = @docgen.complexity_table(@docgen.algorithm_metadata())
  assert_true(r1 == r2)
  // 从元数据 O(n) 线性生成 Markdown 复杂度表（R19.1）。
  match r1 {
    Ok(table) => {
      // 表格 = 表头行 + 对齐分隔行 + 33 条数据行；每行以换行结尾，故共 35 个 '\n'。
      let mut newlines = 0
      for ch in table.iter().to_array() {
        if ch == '\n' {
          newlines = newlines + 1
        }
      }
      inspect(newlines, content="35")
      // 数据行数 = 总行数 - 表头 2 行 = 33（R19.2：唯一对应、无重复无遗漏）。
      inspect(newlines - 2, content="33")
      // 五列表头与 GFM 对齐分隔行齐备（R19.1）。
      assert_true(
        table.contains(
          "| 算法 | 最坏时间复杂度 | 平均时间复杂度 | 空间复杂度 | 适用条件 |",
        ),
      )
      assert_true(table.contains("| --- | --- | --- | --- | --- |"))
      // 经典算法首行五字段非空（R19.1）。
      assert_true(table.contains("| BFS | O(V + E) | O(V + E) | O(V) |"))
      // 三种旗舰高级算法各占唯一一行（R19.2）。
      assert_true(table.contains("| Contraction Hierarchies |"))
      assert_true(table.contains("| Jump Point Search |"))
      assert_true(table.contains("| ALT |"))
    }
    Err(_) => assert_true(false)
  }
}
```

---

## Cookbook · 22 个真实可运行用例

> 对应需求 **R21 (Cookbook 与公开 API 文档完整性)** — R21.1 (≥20 用例,覆盖
> 网格寻路 / 网络路由 / 任务调度 / 最大流 / 匹配五类,每类 ≥1)、R21.2 (每个用例在
> `wasm-gc` / `js` / `native` 三后端均成功)、R21.5 (每个用例提供可执行命令与预期输出)。

本手册收录 **22 个**可直接复制使用的用例,按五类真实场景分组。每个用例都是一段
` ```mbt check ` 可执行测试,统一用下面这一条命令运行,任一用例输出与 `inspect`
快照不符即构建失败:

```bash
moon test README.mbt.md
```

各用例的「预期输出」即代码块内 `inspect(value, content="...")` 的快照值,或
`assert_true(...)` 断言;它们在三后端上结果一致。

### 一 · 网格寻路 (5 例)

栅格地图上 4 向 / 8 向移动的最短路径,常用于游戏寻路与机器人导航。

**用例 1 — BFS 在 5×5 空网格求最短步数。** 无权图最短路用 BFS;从 `(0,0)` 到 `(4,4)`
的曼哈顿下界为 8 步,故最短路径恰含 9 个格子。

```mbt check
///|
test "Cookbook 网格寻路 1 · BFS 在 5x5 空网格最短步数" {
  let w = 5
  let h = 5
  let succ = fn(pos : (Int, Int)) -> Array[(Int, Int)] {
    let (x, y) = pos
    let cand = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    let out : Array[(Int, Int)] = []
    for p in cand {
      let (nx, ny) = p
      if nx >= 0 && nx < w && ny >= 0 && ny < h {
        out.push(p)
      }
    }
    out
  }
  let path = @uw.bfs((0, 0), succ, fn(p) { p == (4, 4) })
  match path {
    // 路径含 9 个格子 (8 步 + 起点)。
    Some(p) => inspect(p.length(), content="9")
    None => assert_true(false)
  }
}
```

**用例 2 — BFS 绕过障碍墙。** 3×3 网格中 `(1,0)`、`(1,1)` 是墙,从 `(0,0)` 到 `(2,0)`
的直线被封死,BFS 自动绕行,最短路径含 7 个格子。

```mbt check
///|
test "Cookbook 网格寻路 2 · BFS 绕过障碍墙" {
  let w = 3
  let h = 3
  let blocked = fn(p : (Int, Int)) -> Bool { p == (1, 0) || p == (1, 1) }
  let succ = fn(pos : (Int, Int)) -> Array[(Int, Int)] {
    let (x, y) = pos
    let cand = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    let out : Array[(Int, Int)] = []
    for p in cand {
      let (nx, ny) = p
      if nx >= 0 && nx < w && ny >= 0 && ny < h && !blocked(p) {
        out.push(p)
      }
    }
    out
  }
  let path = @uw.bfs((0, 0), succ, fn(p) { p == (2, 0) })
  match path {
    // 绕墙后最短路径含 7 个格子。
    Some(p) => inspect(p.length(), content="7")
    None => assert_true(false)
  }
}
```

**用例 3 — A\* 在 5×5 网格用曼哈顿启发式。** 4 向每步代价 1,曼哈顿启发式可采纳
(不高估),从 `(0,0)` 到 `(4,4)` 的最优代价为 8。

```mbt check
///|
test "Cookbook 网格寻路 3 · A-star 曼哈顿启发式" {
  let w = 5
  let h = 5
  let succ = fn(pos : (Int, Int)) -> Array[((Int, Int), Int)] {
    let (x, y) = pos
    let cand = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    let out : Array[((Int, Int), Int)] = []
    for p in cand {
      let (nx, ny) = p
      if nx >= 0 && nx < w && ny >= 0 && ny < h {
        out.push((p, 1))
      }
    }
    out
  }
  let heuristic = fn(pos : (Int, Int)) -> Int {
    let (x, y) = pos
    (4 - x).abs() + (4 - y).abs()
  }
  let result = @dir.astar((0, 0), succ, heuristic, fn(p) { p == (4, 4) })
  match result {
    Some((_path, cost)) => inspect(cost, content="8")
    None => assert_true(false)
  }
}
```

**用例 4 — A\* 绕过障碍的最优代价。** 3×3 网格中 `(1,0)`、`(1,1)` 为墙,从 `(0,0)`
到 `(2,0)` 绕行最优代价为 6(7 个格子 6 条边)。

```mbt check
///|
test "Cookbook 网格寻路 4 · A-star 绕障碍最优代价" {
  let w = 3
  let h = 3
  let blocked = fn(p : (Int, Int)) -> Bool { p == (1, 0) || p == (1, 1) }
  let succ = fn(pos : (Int, Int)) -> Array[((Int, Int), Int)] {
    let (x, y) = pos
    let cand = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    let out : Array[((Int, Int), Int)] = []
    for p in cand {
      let (nx, ny) = p
      if nx >= 0 && nx < w && ny >= 0 && ny < h && !blocked(p) {
        out.push((p, 1))
      }
    }
    out
  }
  let heuristic = fn(pos : (Int, Int)) -> Int {
    let (x, y) = pos
    (2 - x).abs() + (0 - y).abs()
  }
  let result = @dir.astar((0, 0), succ, heuristic, fn(p) { p == (2, 0) })
  match result {
    Some((_path, cost)) => inspect(cost, content="6")
    None => assert_true(false)
  }
}
```

**用例 5 — JPS 跳点搜索走对角线。** 8 向均匀代价网格上,JPS 沿对角线跳跃;5×5 空网格
从 `(0,0)` 到 `(4,4)` 走 4 步对角线,每步代价 √2,总代价约 5.6569。

```mbt check
///|
test "Cookbook 网格寻路 5 · JPS 对角线跳点搜索" {
  let blocked : Array[Bool] = Array::make(25, false)
  let grid = @advanced.JPSGrid::new(5, 5, blocked).unwrap()
  let result = @advanced.jps(grid, (0, 0), (4, 4))
  match result {
    Some((path, cost)) => {
      // 4 步对角线,每步 √2 ≈ 1.4142135。
      assert_true((cost - 4.0 * 1.4142135).abs() < 1.0e-6)
      // 路径首尾分别为起点与终点。
      assert_true(path[0] == (0, 0))
      assert_true(path[path.length() - 1] == (4, 4))
    }
    None => assert_true(false)
  }
}
```

### 二 · 网络路由 (5 例)

带权有向图上的最小代价路由,常用于通信网络、地图导航与延迟优化。

**用例 6 — Dijkstra 选最便宜路由。** 5 节点网络中存在唯一最短路 `0→1→2→3→4`,
总代价 8。

```mbt check
///|
test "Cookbook 网络路由 1 · Dijkstra 最便宜路由" {
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 2), (2, 5)],
    [(2, 1), (3, 7)],
    [(3, 3), (4, 8)],
    [(4, 2)],
    [],
  ]
  let result = @dir.dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 4 })
  match result {
    Some((path, cost)) => {
      inspect(cost, content="8")
      inspect(path, content="[0, 1, 2, 3, 4]")
    }
    None => assert_true(false)
  }
}
```

**用例 7 — Dijkstra 多跳优于直连。** 直连 `0→3` 代价 10,而多跳 `0→1→2→3` 仅 3,
Dijkstra 选多跳。

```mbt check
///|
test "Cookbook 网络路由 2 · Dijkstra 多跳优于直连" {
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 1), (3, 10)],
    [(2, 1)],
    [(3, 1)],
    [],
  ]
  let result = @dir.dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 3 })
  match result {
    Some((path, cost)) => {
      inspect(cost, content="3")
      inspect(path, content="[0, 1, 2, 3]")
    }
    None => assert_true(false)
  }
}
```

**用例 8 — Bellman-Ford 处理负权边。** 含负权边 `1→2 (-3)` 时 Dijkstra 失效,
Bellman-Ford 仍能求得正确距离:`dist[2]=1`、`dist[3]=3`。

```mbt check
///|
test "Cookbook 网络路由 3 · Bellman-Ford 负权边距离" {
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 4),
    (0, 2, 5),
    (1, 2, -3),
    (2, 3, 2),
  ]
  let result = @dir.bellman_ford(nodes, edges, 0)
  match result {
    Ok(dist) => {
      inspect(dist.get(2), content="Some(1)")
      inspect(dist.get(3), content="Some(3)")
    }
    Err(_) => assert_true(false)
  }
}
```

**用例 9 — Bellman-Ford 检测负环。** 环 `1→2→1` 总权 `-3+1=-2` 为负环,
Bellman-Ford 返回 `Err`。

```mbt check
///|
test "Cookbook 网络路由 4 · Bellman-Ford 检测负环" {
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (1, 2, -3), (2, 1, 1)]
  let result = @dir.bellman_ford(nodes, edges, 0)
  // 存在可达负环 → 返回结构化错误。
  inspect(result is Err(_), content="true")
}
```

**用例 10 — Dijkstra 单源最短路树。** `dijkstra_all` 一次性算出从源到所有节点的
最短距离与路径,可重复查询任意目标。

```mbt check
///|
test "Cookbook 网络路由 5 · Dijkstra 单源最短路树" {
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 2), (2, 5)],
    [(2, 1), (3, 7)],
    [(3, 3), (4, 8)],
    [(4, 2)],
    [],
  ]
  let tree = @dir.dijkstra_all(0, fn(n) { adj[n] })
  inspect(tree.distance_to(4), content="Some(8)")
  inspect(tree.path_to(4), content="Some([0, 1, 2, 3, 4])")
}
```

### 三 · 任务调度 (4 例)

DAG 上的拓扑排序与最短/关键路径,常用于构建系统、工作流编排与项目计划。

**用例 11 — 拓扑排序得到合法执行顺序。** 5 个任务的依赖 DAG,拓扑排序给出
满足全部先后约束的执行序。

```mbt check
///|
test "Cookbook 任务调度 1 · 拓扑排序合法执行顺序" {
  let adj : Array[Array[Int]] = [[1, 2], [3], [3], [4], []]
  let result = @dir.topological_sort([0, 1, 2, 3, 4], fn(n) { adj[n] })
  match result {
    Ok(order) => {
      inspect(order.length(), content="5")
      // 校验拓扑性:每条依赖边 u→v 满足 pos[u] < pos[v]。
      let pos : Map[Int, Int] = Map([])
      for i, n in order {
        pos[n] = i
      }
      let edges = [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)]
      let mut valid = true
      for e in edges {
        let (u, v) = e
        if pos.get(u).unwrap() >= pos.get(v).unwrap() {
          valid = false
        }
      }
      inspect(valid, content="true")
    }
    Err(_) => assert_true(false)
  }
}
```

**用例 12 — 拓扑排序检测循环依赖。** 环 `0→1→2→0` 不是 DAG,拓扑排序返回 `Err`。

```mbt check
///|
test "Cookbook 任务调度 2 · 拓扑排序检测循环依赖" {
  let adj : Array[Array[Int]] = [[1], [2], [0]]
  let result = @dir.topological_sort([0, 1, 2], fn(n) { adj[n] })
  // 存在环 → 返回结构化错误。
  inspect(result is Err(_), content="true")
}
```

**用例 13 — DAG 最短完工路径(双等价路径)。** 两条路径 `0→1→3` 与 `0→2→3`
代价均为 7,`dag_shortest_path` 取最小完工代价 7。

```mbt check
///|
test "Cookbook 任务调度 3 · DAG 最短完工路径" {
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 3), (2, 2)],
    [(3, 4)],
    [(3, 5)],
    [],
  ]
  let result = @dir.dag_shortest_path([0, 1, 2, 3], 0, fn(n) { adj[n] }, fn(n) {
    n == 3
  })
  match result {
    Ok(Some((path, cost))) => {
      inspect(cost, content="7")
      inspect(path.length(), content="3")
    }
    Ok(None) => assert_true(false)
    Err(_) => assert_true(false)
  }
}
```

**用例 14 — DAG 唯一关键路径。** 分层 DAG 中唯一最短路 `0→1→2→3→4` 代价 5。

```mbt check
///|
test "Cookbook 任务调度 4 · DAG 唯一关键路径" {
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 1), (2, 4)],
    [(2, 1), (3, 5)],
    [(3, 1)],
    [(4, 2)],
    [],
  ]
  let result = @dir.dag_shortest_path([0, 1, 2, 3, 4], 0, fn(n) { adj[n] }, fn(
    n,
  ) {
    n == 4
  })
  match result {
    Ok(Some((path, cost))) => {
      inspect(cost, content="5")
      inspect(path, content="[0, 1, 2, 3, 4]")
    }
    Ok(None) => assert_true(false)
    Err(_) => assert_true(false)
  }
}
```

### 四 · 最大流 (4 例)

容量网络上的最大流与最小割,常用于带宽分配、运输调度与项目选择。

**用例 15 — Edmonds-Karp 经典网络最大流。** CLRS 经典 6 节点网络,源 0 到汇 5 的
最大流为 23。

```mbt check
///|
test "Cookbook 最大流 1 · Edmonds-Karp 经典网络" {
  let nodes = [0, 1, 2, 3, 4, 5]
  let cap : Map[(Int, Int), Int] = Map([])
  cap[(0, 1)] = 16
  cap[(0, 2)] = 13
  cap[(1, 2)] = 10
  cap[(2, 1)] = 4
  cap[(1, 3)] = 12
  cap[(3, 2)] = 9
  cap[(2, 4)] = 14
  cap[(4, 3)] = 7
  cap[(3, 5)] = 20
  cap[(4, 5)] = 4
  let flow = @dir.edmonds_karp(nodes, cap, 0, 5)
  inspect(flow, content="23")
}
```

**用例 16 — Dinic 求同一网络最大流。** 不同算法(Dinic 阻塞流)对同一网络应给出
相同的最大流 23。

```mbt check
///|
test "Cookbook 最大流 2 · Dinic 与 Edmonds-Karp 一致" {
  let nodes = [0, 1, 2, 3, 4, 5]
  let cap : Map[(Int, Int), Int] = Map([])
  cap[(0, 1)] = 16
  cap[(0, 2)] = 13
  cap[(1, 2)] = 10
  cap[(2, 1)] = 4
  cap[(1, 3)] = 12
  cap[(3, 2)] = 9
  cap[(2, 4)] = 14
  cap[(4, 3)] = 7
  cap[(3, 5)] = 20
  cap[(4, 5)] = 4
  let flow = @dir.dinic(nodes, cap, 0, 5)
  inspect(flow, content="23")
}
```

**用例 17 — 最小割等于最大流。** 由最大流最小割定理,同一网络的最小割容量恰等于
最大流 23。

```mbt check
///|
test "Cookbook 最大流 3 · 最小割等于最大流" {
  let nodes = [0, 1, 2, 3, 4, 5]
  let cap : Map[(Int, Int), Int] = Map([])
  cap[(0, 1)] = 16
  cap[(0, 2)] = 13
  cap[(1, 2)] = 10
  cap[(2, 1)] = 4
  cap[(1, 3)] = 12
  cap[(3, 2)] = 9
  cap[(2, 4)] = 14
  cap[(4, 3)] = 7
  cap[(3, 5)] = 20
  cap[(4, 5)] = 4
  let (cut, _edges, _side) = @dir.min_cut(nodes, cap, 0, 5)
  inspect(cut, content="23")
}
```

**用例 18 — 最小费用最大流。** 两条并行路径(单价 2 与单价 3)各容量 2,推满 4 单位
流的最小费用为 10。

```mbt check
///|
test "Cookbook 最大流 4 · 最小费用最大流" {
  let nodes = [0, 1, 2, 3]
  // (u, v, capacity, unit_cost)
  let edges : Array[(Int, Int, Int, Int)] = [
    (0, 1, 2, 1),
    (0, 2, 2, 2),
    (1, 3, 2, 1),
    (2, 3, 2, 1),
  ]
  let (flow, cost) = @dir.min_cost_max_flow(nodes, edges, 0, 3)
  inspect(flow, content="4")
  inspect(cost, content="10")
}
```

### 五 · 匹配 (4 例)

二分图匹配与指派问题,常用于任务分配、资源调度与稳定配对。

**用例 19 — Hopcroft-Karp 完美匹配。** 3×3 二分图存在完美匹配,匹配规模为 3。

```mbt check
///|
test "Cookbook 匹配 1 · Hopcroft-Karp 完美匹配" {
  let left = [0, 1, 2]
  let right = [10, 11, 12]
  let adj = fn(l : Int) -> Array[Int] {
    if l == 0 {
      [10, 11]
    } else if l == 1 {
      [10]
    } else {
      [11, 12]
    }
  }
  let matching = @und.hopcroft_karp(left, right, adj)
  // 三条边全部匹配成功。
  inspect(matching.length(), content="3")
}
```

**用例 20 — Hopcroft-Karp 非完美匹配。** 右侧只有 2 个节点,最大匹配规模为 2。

```mbt check
///|
test "Cookbook 匹配 2 · Hopcroft-Karp 非完美匹配" {
  let left = [0, 1, 2]
  let right = [10, 11]
  let adj = fn(l : Int) -> Array[Int] {
    if l == 0 {
      [10]
    } else if l == 1 {
      [10]
    } else {
      [11]
    }
  }
  let matching = @und.hopcroft_karp(left, right, adj)
  // 受右侧容量限制,最大匹配规模为 2。
  inspect(matching.length(), content="2")
}
```

**用例 21 — Kuhn-Munkres 最小代价指派(3×3)。** 匈牙利算法求最小总代价指派:
最优为工人 0→工作 1、1→0、2→2,总代价 5。

```mbt check
///|
test "Cookbook 匹配 3 · Kuhn-Munkres 最小代价指派 3x3" {
  let cost : Array[Array[Double]] = [
    [4.0, 1.0, 3.0],
    [2.0, 0.0, 5.0],
    [3.0, 2.0, 2.0],
  ]
  match @und.kuhn_munkres(cost) {
    Ok((assign, total)) => {
      // assign[i] = 分配给工人 i 的工作编号。
      inspect(assign, content="[1, 0, 2]")
      assert_true((total - 5.0).abs() < 1.0e-9)
    }
    Err(_) => assert_true(false)
  }
}
```

**用例 22 — Kuhn-Munkres 最小代价指派(2×2)。** 2 工人 2 工作的最优指派为
0→1、1→0,总代价 3。

```mbt check
///|
test "Cookbook 匹配 4 · Kuhn-Munkres 最小代价指派 2x2" {
  let cost : Array[Array[Double]] = [[3.0, 1.0], [2.0, 4.0]]
  match @und.kuhn_munkres(cost) {
    Ok((assign, total)) => {
      inspect(assign, content="[1, 0]")
      assert_true((total - 3.0).abs() < 1.0e-9)
    }
    Err(_) => assert_true(false)
  }
}
```

---

## 验证方式

```bash
# 编码修正 + 在项目根目录执行
chcp 65001
moon test README.mbt.md
```

预期看到:

```
Total tests: 28, passed: 28, failed: 0.
```

(示例 1~6 的 6 段 + Cookbook 22 个用例,共 28 段可执行测试全部通过;未来 `moon prove`
语法展示因 `moonbit skip` 被跳过,不计入总数。)

一旦你修改某个算法使其输出与 README 里的 `inspect(..., content="...")` 快照不符,
`moon test README.mbt.md` 会立刻报错并以**最小化差异**提示你同步更新文档 — 这就是
MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](./LICENSE).
