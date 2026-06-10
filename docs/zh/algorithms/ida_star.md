# IDA\* · 迭代加深 A\*

## 背景

Richard Korf 在 1985 年 AAAI 获奖论文 *Depth-First Iterative-Deepening: An
Optimal Admissible Tree Search* 中提出 IDA\*，首次在 RAM 资源受限的嵌入式
环境里给出**保最优 + 省内存**的最优搜索方案，并用它首次求解了**15 拼图
（4×4 滑块拼图）**的最优解——这在当时是人工智能领域的里程碑事件。

## 核心思想

A\* 的痛点是**内存爆炸**：`O(b^d)` 的 open list 在 15 拼图、魔方等大状态
空间里几秒就能耗尽上 GB 内存。IDA\* 用"**迭代加深**"把 A\* 的宽度优先换
成深度优先：

1. 初始阈值 `threshold ← h(start)`；
2. 以 DFS 方式搜索，当某节点 `f = g + h > threshold` 时**立即剪枝**，但
   记录其 `f` 值；
3. 本轮 DFS 没找到目标？把阈值提升为**所有被剪枝节点的最小 f**，重跑 DFS；
4. 重复直到找到目标或阈值达到 ∞（目标不可达）。

**关键性质**：每轮 DFS 用 O(d) 栈深度内存；阈值单调不降，所以不会遗漏
最优解；启发式可采纳时，返回的第一个目标解就是最优解。

## 算法步骤（对应 `src/directed/ida_star.mbt`）

```
bound ← h(start)
path ← [start]
loop:
  t ← search(start, 0, bound)
  if t == NOT_FOUND: break   // 不可能到达
  if t == FOUND: return 重建路径与总代价
  bound ← t                   // 阈值抬升为剪枝中最小 f

fn search(node, g, bound):
  f ← g + h(node)
  if f > bound: return f      // 剪枝，带回"最小超出值"
  if goal(node): return FOUND
  min_exceeded ← ∞
  for (next, w) in successors(node):
    if next ∈ path: continue  // 避免当前路径上的环
    path.push(next)
    t ← search(next, g + w, bound)
    if t == FOUND: return FOUND
    if t < min_exceeded: min_exceeded ← t
    path.pop()
  return min_exceeded
```

本库实现用**显式栈**代替 MoonBit 深递归，以支持深度 1000+ 的搜索而不爆栈。

## 时间复杂度

- **空间 O(d)**：只需当前路径栈，是 IDA\* 的杀手锏；
- **时间 O(b^d)**：最坏情况与 A\* 相同，但 Korf 证明在**单位代价网格**里
  节点重访不超过 O(b^d / (b−1))——常数因子温和；
- 当代价不均匀时 IDA\* 会因阈值离散跳变而**重复搜索**，此时 SMA\*
  （Simplified Memory-Bounded A\*）或 IDA\*CR 是更合适的选择。

## 典型场景

1. **经典拼图 AI**：8-puzzle (3×3)、15-puzzle (4×4)、Rubik's cube
   （本库 `examples/eight_puzzle/` 目前用 A\*，未来可切 IDA\* 证明等价性）；
2. **嵌入式 / WASM 内存受限环境**：IoT 设备路径规划、小内存浏览器游戏；
3. **教学示例**：对比 A\* 的空间换时间策略，理解 "迭代加深" 的巧思。

## MoonBit API 示例

```moonbit
let adj : Array[Array[(Int, Int)]] = [[(1, 10), (2, 1)], [(3, 10)], [(3, 1)], []]
let r = @directed.ida_star(
  0,
  fn(n) { adj[n] },
  fn(_n) { 0 },                  // 零启发式，退化为 IDDFS
  fn(n) { n == 3 })
// r == Some(([0, 2, 3], 2))     // 与 Dijkstra 结果一致
```

本库**whitebox 用例**覆盖：2 节点自环 `0 ↔ 1`，目标 2 不可达时，
`on_path` 过滤使 `min_exceeded` 保持 ∞，触发主循环的 `t == inf → None`
分支，证明 IDA\* 能对"搜索空间有限却目标不可达"的情况及时终止。

## IDA\* vs A\*

| 维度 | A\* | IDA\* |
|------|-----|-------|
| 空间 | O(b^d) ❌ | **O(d)** ✅ |
| 时间 | 理想 | 可能多轮重复 |
| 适合规模 | 中小 | 大（15 拼图级） |
| 启发式 | 任意可采纳 | 同 A\* |
| 实现 | 堆 + 哈希 | 递归/栈 |

## 参考文献

- Korf, R. E. (1985). "Depth-first iterative-deepening: An optimal admissible
  tree search." *Artificial Intelligence*, 27(1), 97–109.
- Russell & Norvig, *AIMA* 第 4 版 3.5.3。
