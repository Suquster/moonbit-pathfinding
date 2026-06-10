# Kuhn-Munkres（匈牙利算法）· 二分图最小权完美匹配

## 背景

匈牙利算法（Hungarian Algorithm）由 Harold Kuhn 在 1955 年 *Naval Research
Logistics Quarterly* 的经典论文 *The Hungarian Method for the Assignment
Problem* 中提出，并归功于匈牙利数学家 Dénes Kőnig 与 Jenő Egerváry 的
早期工作。James Munkres 在 1957 年完善了时间复杂度分析，因此也称
**Kuhn-Munkres 算法**。

此算法是"**带权二分图完美匹配**"的标准解法——对于 n × n 的代价矩阵 `cost`，
找到一个置换 `σ` 使 **总代价最小**：

```
minimize  Σ_i cost[i][σ(i)]
subject to  σ 是 {0, 1, ..., n-1} 的一个排列
```

## 核心思想

**对偶变量（势函数）+ 增广路径**：维护两组标签 `u[0..n]`（行势）与
`v[0..n]`（列势），使得对所有 `(i, j)` 有 `u[i] + v[j] ≤ cost[i][j]`。
定义"紧边"为 `u[i] + v[j] == cost[i][j]`，只在紧边上做匹配。

- 若紧边上能找到覆盖所有行的匹配 ⇒ 它就是最优解（对偶紧致性定理）；
- 若不能，调整 `u`、`v` 使得**至少一条新紧边出现**、已有紧边不破坏，
  重复直至完美匹配。

现代实现（本库采用）使用"最小交替树 + 势函数更新"的 **Jonker-Volgenant
优化**，保证 O(n³) 的严格上界。

## 算法骨架

```
u[0..n] ← 0; v[0..n] ← 0
p[0..n] ← 0                 // p[j] = 当前匹配给列 j 的行 (0 = 未匹配)
for i in 1..=n:
  p[0] ← i                  // 把行 i 视作"虚拟源"
  j0 ← 0; minv[] ← ∞; used[] ← false
  repeat:
    used[j0] ← true; i0 ← p[j0]
    // 扫描所有未用列，找到最便宜的可用列 j1
    (delta, j1) ← 找使得 cost[i0-1][j-1] - u[i0] - v[j] 最小的未用 j
    // 更新势函数使新的紧边出现
    for j in 0..=n:
      if used[j]:  u[p[j]] += delta;  v[j] -= delta
      else:        minv[j] -= delta
    j0 ← j1
  until p[j0] == 0          // 到达自由列，增广路径找到
  // 沿 way 数组反向增广，把匹配挪一格
  while j0 != 0:
    j1 ← way[j0]; p[j0] ← p[j1]; j0 ← j1
// 输出：assignment[i] ← j 使得 p[j] == i
```

## 时间复杂度

- **时间 O(n³)**：外层 n 次循环 × 内层 O(n²)；
- **空间 O(n²)**：代价矩阵 + 势 / minv / used / way 辅助数组。

对 n ≤ 500 毫秒级，n ≤ 2000 秒级；更大规模需启发式或近似。

## 典型场景

1. **任务分配**：n 个员工 × n 个任务的最优排班；
2. **图像匹配 / 点集配准**：LiDAR 点云与 3D 模型对齐；
3. **目标追踪**：多目标 Kalman 滤波器与新观测的关联（多传感器融合）；
4. **拍卖机制设计**：VCG 机制的胜出者分配；
5. **体育联盟抽签**：最小化"队伍 × 主客场冲突"总分。

**与 Edmonds-Karp 的区别**：本库 `edmonds_karp` 也能求"无权二分图最大匹配
数"（拆点建图即可），但 Kuhn-Munkres 直接接受**带权**代价矩阵，两者
互补。

## MoonBit API 示例

```moonbit
// 3 × 3 代价矩阵，Kuhn-Munkres 最小化总代价
let cost : Array[Array[Double]] = [
  [4.0, 1.0, 3.0],
  [2.0, 0.0, 5.0],
  [3.0, 2.0, 2.0],
]
match @undirected.kuhn_munkres(cost) {
  Ok((assignment, total)) => {
    // 最优分配 total == 5.0，例如 0→1(1) + 1→0(2) + 2→2(2)
    println("total = \{total}")
  }
  Err(@core.InvalidInput(msg)) => println(msg)  // 非方阵时触发
}
```

**whitebox 用例**：`n == 0` 空矩阵直接返回 `Ok(([], 0.0))`，覆盖源文件
开头的 `if n == 0 { return Ok(([], 0.0)) }` 分支；测试中还用"**4 × 4 矩阵
vs 暴力枚举 4! = 24 置换**"交叉验证一致性。

## 参考文献

- Kuhn, H. W. (1955). "The Hungarian method for the assignment problem."
  *Naval Research Logistics Quarterly*, 2(1–2), 83–97.
- Munkres, J. (1957). "Algorithms for the Assignment and Transportation Problems."
  *SIAM Journal*, 5(1), 32–38.
- Jonker, R., & Volgenant, A. (1987). "A shortest augmenting path algorithm
  for dense and sparse linear assignment problems." *Computing*, 38, 325–340.
