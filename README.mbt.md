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

下面 5 段示例分别覆盖 **BFS / Dijkstra / A\* / Kruskal MST / 形式化证明片段**,每段都可独立
复制到你的项目里使用。

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

## 验证方式

```bash
# 编码修正 + 在项目根目录执行
chcp 65001
moon test README.mbt.md
```

预期看到:

```
Total tests: 5, passed: 5, failed: 0.
```

(示例 1~5 的 5 段可执行测试全部通过；未来 `moon prove` 语法展示因 `moonbit skip`
被跳过,不计入总数。)

一旦你修改某个算法使其输出与 README 里的 `inspect(..., content="...")` 快照不符,
`moon test README.mbt.md` 会立刻报错并以**最小化差异**提示你同步更新文档 — 这就是
MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 taoyouce. See [LICENSE](./LICENSE).
