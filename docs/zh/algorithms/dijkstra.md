# Dijkstra · 单源最短路（非负权）

## 背景

Dijkstra 算法由荷兰计算机科学家 Edsger Dijkstra 于 1959 年在一次咖啡馆
的 20 分钟思考中发明，是**非负权有向图**单源最短路的标准答案，也是 A*、
ALT、Contraction Hierarchies 等高级算法的基石。

## 核心思想

**贪心 + 优先队列**：维护一个"已知最短距离"集合 `dist`，每次从未处理
节点中挑 `dist` 最小的那个 `u`，声明 `dist[u]` 已是最终值，并用 `u` 的
所有出边去**松弛**邻居。

**正确性**关键：若所有边权非负，则堆顶节点 `u` 的 `dist[u]` 不会再被任何
未访问节点改善（因为从它们出发任意路径都 ≥ `dist[u]`）。

## 算法步骤（含循环不变式，见源码 `/// invariant:` 注释）

```
dist[start] ← 0；其余 ← ∞
pq.push((0, start))
while pq 非空:
  (d, u) ← pq.pop()
  // invariant: u 出队后 dist[u] 为最终最短距离
  if d > dist[u]: continue    // 跳过过期条目
  if goal(u): 回溯路径并返回
  for (v, w) in successors(u):
    if dist[u] + w < dist[v]:
      dist[v] ← dist[u] + w
      parents[v] ← u
      pq.push((dist[v], v))
```

本库使用**惰性删除**：不实现 decrease-key，重复 push 但弹出时比对过期
条目。实测堆常数因子反而更优。

## 时间复杂度

- **二叉堆 PQueue**：O((V + E) log V)
- **空间**：O(V)

## 典型场景

1. **路网导航**：地图 API 求最快路径
2. **网络路由**：OSPF / RIP 协议核心
3. **游戏 AI**：RTS 单位寻路（结合 A*）
4. **基准对比**：与 Bellman-Ford / Floyd-Warshall 做 PBT 交叉验证

## MoonBit API 示例

```moonbit
let adj : Array[Array[(Int, Int)]] = [[(1, 1), (2, 4)], [(2, 2)], []]
match @directed.dijkstra(0, fn(n) { adj[n] }, fn(n) { n == 2 }) {
  Some((path, cost)) => println("cost=\{cost}, path=\{path}")
  None => println("unreachable")
}
```

## 参考文献

- Dijkstra, E. W. (1959). "A note on two problems in connexion with graphs."
  *Numerische Mathematik*, 1(1), 269–271.
- 本库形式化证明预告见 `src/proofs/dijkstra_proof.mbt`（M4 交付）
