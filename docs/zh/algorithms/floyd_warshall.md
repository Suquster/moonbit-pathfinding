# Floyd-Warshall · 全源最短路

## 背景

Floyd-Warshall 的数学基础由 Bernard Roy（1959）与 Stephen Warshall（1962）
独立提出，最后由 Robert Floyd（1962）在 *Communications of the ACM* 上
以 5 行伪代码的优雅形式定稿，成为教科书级经典。它回答的问题不是"单源到
某点"，而是 **"任意两点之间的最短距离"**（All-Pairs Shortest Path, APSP）。

## 核心思想

**动态规划 + 中继节点的逐步放宽**。定义 `D^k[i][j]` 为"**只允许使用
节点 `{0, 1, ..., k}` 作为中继**时 `i → j` 的最短距离"，则状态转移方程：

```
D^k[i][j] = min( D^{k-1}[i][j],              // 不用 k 作中继
                 D^{k-1}[i][k] + D^{k-1}[k][j] ) // 用 k 作中继
```

最终 `D^{n-1}[i][j]` 就是真正的最短距离。由于状态仅依赖上一层，可就地
覆盖，空间从 O(V³) 压到 **O(V²)**。

## 算法步骤（经典三重 for）

```
dist[i][j] ← w(i, j) 若有边，i==j 则 0，否则 ∞
for k in 0..V:
  for i in 0..V:
    for j in 0..V:
      if dist[i][k] != ∞ and dist[k][j] != ∞ and
         dist[i][k] + dist[k][j] < dist[i][j]:
        dist[i][j] ← dist[i][k] + dist[k][j]
return dist
```

注意**必须**检查两半都不是 `∞`，否则 `∞ + w` 在饱和加法下仍是 `∞`，
虽然不会错，但可能产生精度噪声。本库实现也加了这个守卫。

**负环检测**：若某次三重 for 结束后存在 `dist[i][i] < 0`，说明有负环经过
`i`。

## 时间复杂度

- **时间** O(V³)：对 V ≤ 400 可接受；V = 1000 就要 10⁹ 次内层操作（约 10 秒）。
- **空间** O(V²)。

## 典型场景

1. **密集全源路径查询**：小 V（≤ 几百）+ 多次起终点查询，预处理一次后
   O(1) 查询。
2. **传递闭包计算**：权取 0/∞ 变成布尔"可达矩阵"——Floyd 变 Warshall。
3. **图中心度分析**：全源距离矩阵可直接推导 closeness / betweenness 中心度。
4. **正确性 Oracle**：本库在 `floyd_warshall_test.mbt` 用 5 节点图对每对
   `(u, v)` 与 `dijkstra(u, adj, ==v)` 的结果交叉验证一致（见 whitebox 用例）。

## MoonBit API 示例

```moonbit
let nodes = [0, 1, 2]
let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (1, 2, 2)]
let dist = @directed.floyd_warshall(nodes, edges)
// dist.get((0, 2)) == Some(3)    // 通过 k=1 中继松弛出来
// dist.get((2, 0)) == Some(Int::max_value())   // 不可达
```

## 对比 APSP 方案

| 方案 | 时间 | 空间 | 负权 |
|------|------|------|------|
| Floyd-Warshall | O(V³) | O(V²) | ✅（无负环）|
| 逐点 Dijkstra | O(V · (V+E) log V) | O(V+E) | ❌ |
| Johnson 算法 | O(V² log V + V·E) | O(V²) | ✅ |

稠密图或小 V 选 Floyd；稀疏大图 + 非负权选逐点 Dijkstra；负权 + 稀疏
则 Johnson。

## 参考文献

- Floyd, R. W. (1962). "Algorithm 97: Shortest Path." *CACM*, 5(6), 345.
- Warshall, S. (1962). "A theorem on Boolean matrices." *J. ACM*, 9, 11–12.
- CLRS 25.2。
