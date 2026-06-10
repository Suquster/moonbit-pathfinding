# Jump Point Search · 跳点搜索（🚧 v1.0.0）

> **状态**：🧪 experimental — `src/advanced/jps.mbt` 与 `jps_test.mbt` 已落地；仍需大规模网格基准、可视化示例和边界场景强化后升级为稳定 API。

## 背景

Daniel Harabor 与 Alban Grastien 在 2011 年 AAAI 论文 *Online Graph Pruning
for Pathfinding on Grid Maps* 中提出 JPS，用网格对称性减少 A\* 在
统一权网格上的冗余扩展。它是游戏寻路与实时机器人导航领域的重要工作之一；
本库只在记录本地 benchmark artifact 后声明具体扩展节点数或耗时收益。

## 核心思想

**"利用网格对称性，跳过等价状态"**：在 8 向网格里，对**同一步数**可达
的多条路径是**等价**的。A\* 一个不落地扩展所有等价节点，浪费极大。JPS
通过"**跳跃规则**"一步直达那些"真正不同的决策点"（称作**跳点**），
用**局部递归跳跃**代替中间节点的逐格扩展。

跳点的形式化定义：从 `p` 沿方向 `d` 递归跳跃，返回：
- 网格边界或障碍 ⇒ 放弃该方向；
- **找到目标**或含**强制邻居**（forced neighbor，障碍约束下不可绕过的邻居）
  的节点；
- 对角线方向需先尝试两个分量方向再回归对角线。

然后用 A\* 外壳 + **Octile 启发式**（`d = max(dx, dy) + (√2 − 1) · min(dx, dy)`）
驱动跳跃扩展。

## 算法骨架

```
open ← { start }
while open 非空:
  n ← open.pop_min_f()
  if n == goal: 回溯路径
  for successor in identify_successors(n, parent(n)):
    j ← jump(successor, direction(n, successor), goal)
    if j exists:
      更新 g, f, parent，push into open

fn jump(node, direction, goal):
  if node 越界 或 阻挡: return None
  if node == goal: return node
  if node 有强制邻居: return node    // 这里是"跳点"
  if direction 是对角线:
    // 先尝试两个分量方向，任一有跳点即返回
    if jump(node + (dx, 0), (dx, 0), goal) exists: return node
    if jump(node + (0, dy), (0, dy), goal) exists: return node
  return jump(node + direction, direction, goal)
```

## 典型场景

1. **实时策略游戏**：单位批量寻路（10 万单位级别），CPU 预算有限；
2. **机器人实时导航**：Roomba 式扫地机器人、仓储 AGV；
3. **VR / AR 场景**：头显响应延迟要求毫秒级；
4. **WASM Playground 候选场景**：若浏览器演示进入交付面，JPS 将作为
   网格寻路核心算法之一；届时必须记录地图规模、浏览器、backend、帧率和
   与 A* 的扩展节点对比，不能只用主观动画效果证明性能。

## 限制与前提

- **仅适用于统一代价网格**（每格移动代价相同）；
- **需要 4 向或 8 向移动模型**；
- 非网格图请用 A\* / ALT / CH；
- 含不规则障碍时仍高效，但需正确实现"强制邻居"规则（实现错误会导致
  算法返回非最优解，是 JPS 的第 1 号坑）。

## 当前 API

```moonbit skip
// 构造网格：blocked[i] == true 表示第 i 个格子是障碍
let grid = @advanced.JPSGrid::new(width, height, blocked)
let result = @advanced.jps(grid, (start_x, start_y), (goal_x, goal_y))
// result: Option[(Array[(Int, Int)], Double)]
```

## 性能对比计划

JPS 的性能叙事必须以本库可复现数据为准。计划记录：

- 地图尺寸、障碍比例和随机种子；
- A\* 与 JPS 的扩展节点数；
- MoonBit 版本、backend、机器信息；
- 原始计时和汇总统计。

本库 M4 将在真实或生成网格数据上实测并发布对比图。

## 参考文献

- Harabor, D., & Grastien, A. (2011). "Online Graph Pruning for Pathfinding
  on Grid Maps." *AAAI 2011*.
- Harabor, D., & Grastien, A. (2014). "Improving Jump Point Search."
  *ICAPS 2014*.
