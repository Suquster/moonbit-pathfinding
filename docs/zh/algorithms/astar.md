# A\* · 启发式最优搜索

## 背景

A\*（读作 "A star"）由斯坦福研究所的 Peter Hart、Nils Nilsson 与 Bertram
Raphael 于 **1968 年**在论文 *A Formal Basis for the Heuristic Determination
of Minimum Cost Paths* 中提出，是人工智能与机器人学的里程碑——它第一次
为"带启发式的最优搜索"给出了**形式化的可采纳性（admissibility）与一致性
（consistency）定理**。

今天的导航 APP、RTS 单位寻路、棋类 AI、自动规划系统几乎都以 A\* 的变体
作为底层骨架。

## 核心思想

A\* 把每个节点 `n` 的"总代价估计"定义为：

```
f(n) = g(n) + h(n)
```

- `g(n)`：从 `start` 到 `n` 的**已知最短代价**（与 Dijkstra 中的 `dist` 同义）。
- `h(n)`：启发式函数给出的"从 `n` 到目标的估计代价"，必须**永不高估**真实代价
  （即 `h(n) ≤ h*(n)`），这一性质称作 **可采纳性**。

算法用优先队列按 `f` 值从小到大扩展节点。若 `h` 还满足"三角不等式"
（`h(u) ≤ w(u, v) + h(v)`），即 **一致性**，那么 A\* 每个节点最多出队一次，
退化为一个 `g` 同 Dijkstra、但被启发式"剪枝"的精明 Dijkstra。

当 `h ≡ 0`，A\* **完全等价于 Dijkstra**；当 `h` 高估，A\* 可能丢掉最优解
但速度更快；当 `h` 可采纳，A\* **保证返回最优路径**。

## 算法步骤

```
g_cost[start] ← 0, parents ← {}, pq.push(h(start), start)
while pq 非空:
  (_, u) ← pq.pop()
  if goal(u): 回溯 parents 返回路径
  for (v, w) in successors(u):
    tentative ← g_cost[u] + w
    if v ∉ g_cost 或 tentative < g_cost[v]:
      g_cost[v] ← tentative
      parents[v] ← u
      pq.push(tentative + h(v), v)   // 注意以 f 入堆，g 单独保存
return None
```

关键工程细节：`g_cost` 用来判定是否需要继续松弛，`pq` 以 `f` 为 key。
两者分离可以让"启发式变化不误杀更优 g"，这是本库对 `pathfinding` crate
API 的一处工程加固。

## 时间复杂度

最坏 **O((V + E) log V)**，与 Dijkstra 同级；但启发式优秀时实际扩展节点
数远小于 V，在 32×32 开放网格上从 `(0,0)` 走到 `(31,31)` 只需扩展几十个
节点（见 `benches/astar_bench/`）。

## 典型场景与启发式选择

| 场景 | 启发式 | 可采纳性证明 |
|------|--------|-------------|
| 网格 4 向 | 曼哈顿距离 `|dx| + |dy|` | 每一步至少推进 1 |
| 网格 8 向 | Octile 距离 | 对角线费用 √2 ≤ 欧氏距离 |
| 路网导航 | 欧氏/球面距离 | 物理上直线最短 |
| 八数码 / 15 拼图 | 瓦片错位数 或 曼哈顿距离之和 | 每瓦片至少需要这么多步归位 |
| 地图地标预处理 | ALT `max_l |d(l, n) − d(l, t)|` | 三角不等式（见 `src/advanced/alt.mbt`） |

## MoonBit API 示例

```moonbit
// 3×3 网格, 4 向, 曼哈顿启发式
let succ = fn(p : (Int, Int)) -> Array[((Int, Int), Int)] {
  let (x, y) = p
  [((x+1, y), 1), ((x-1, y), 1), ((x, y+1), 1), ((x, y-1), 1)]
    .filter(fn(pw) { let (q, _) = pw; q.0 >= 0 && q.0 < 3 && q.1 >= 0 && q.1 < 3 })
}
let h = fn(p : (Int, Int)) -> Int { (2 - p.0).abs() + (2 - p.1).abs() }
let r = @directed.astar((0, 0), succ, h, fn(p) { p == (2, 2) })
// r == Some(([...], 4))
```

## 参考文献

- Hart, P. E., Nilsson, N. J., & Raphael, B. (1968). "A Formal Basis for the
  Heuristic Determination of Minimum Cost Paths." *IEEE TSSC*, 4(2), 100–107.
- Russell & Norvig, *AIMA* 第 4 版 第 3 章。
- 本库 `benches/astar_bench/` 有 32×32 网格基准。
