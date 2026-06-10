# Yen's K-Shortest Loopless Paths · K 最短无环路径

## 背景

单源单汇"最短路径"问题我们已经由 Dijkstra 解决，但工程中常问的是：
"**给我最短的前 3 条路径**"——航空公司卖机票、导航推荐备选路线、网络
路由容错设计。Yen Jin Y. 在 1971 年的论文 *Finding the K Shortest Loopless
Paths in a Network* 中给出了第一个**多项式时间**、**无环**的 K 最短路算法，
至今仍是领域标配。

## 核心思想

**在已确定路径的"每一节点"上尝试绕开**：

1. 先用 Dijkstra 求出第 1 条最短路径 `P₁`，放入已接受集合 `A`；
2. 求第 `k+1` 条（已有 `P₁, ..., Pₖ`）时：对 `Pₖ` 的每个节点 `v`（称作
   **spur node**），临时禁止"已接受路径在这里经过的那些边"与"spur node
   之前的节点"，以保证新生成的路径**与 A 内任何路径都不重合且无环**；
3. 用 Dijkstra 在这张禁忌图上找 `v → t` 的最短路径 `spur`，拼上 `Pₖ[:v]`
   得到"候选" `C`；
4. 所有 `v` 的候选收集进候选池 `B`，挑代价最小的一条放入 `A`；
5. 重复直到 `A` 有 K 条路径，或候选池空（无更多无环路径）。

**核心不变式**：K 条结果按代价**单调非降**排列；相邻两条必不相同；且每条
都无环（节点不重复）。

## 算法步骤（对应 `src/directed/yen.mbt`）

```
A ← [ dijkstra(s, t) ]
B ← []   // 候选池
for k in 1..K:
  last_path ← A[k-1]
  for i in 0..len(last_path)-1:
    spur_node ← last_path[i]
    root_path ← last_path[0..i+1]
    banned_edges ← {
      (p[i], p[i+1]) | p ∈ A, p 的前 i+1 节点 == root_path
    }
    banned_nodes ← root_path \ {spur_node}
    spur ← dijkstra(spur_node, t, successors 去掉 banned_edges/nodes)
    if spur 存在:
      candidate ← root_path + spur
      if candidate ∉ B: B.append((candidate, cost))
  if B 为空: break   // 候选耗尽
  B.sort_by_cost(); chosen ← B.pop_front()
  A.append(chosen)
return A
```

## 时间复杂度

- **时间 O(K · V · (V + E) log V)**：每个 k 要做 V 次 Dijkstra；
- **空间 O(K · L + B)**：L 为平均路径长度，B 为候选池大小。

对 V = 1000, E = 10k, K = 10 的典型查询约 **数秒级**，已覆盖绝大部分工程场景。

## 典型场景

1. **机票推荐**：用户查询 "北京 → 纽约"，展示 5 条最便宜的换乘组合；
2. **网络路由容错**：BGP / MPLS 预计算前 N 条备用路径，主路径失效时秒切；
3. **物流最后一公里**：备选配送路径，规避临时道路封闭；
4. **行程规划**：用户不只想"最短"，想要"不同机场、不同时段"的多样化选项。

**参数约束**：`k ≤ 0` 时本库返回 `Err(@core.InvalidK(k))`，这是显式类型
安全的体现。

## MoonBit API 示例

```moonbit
let edges : Array[(Int, Int, Int)] = [
  (0, 1, 1), (0, 2, 2), (1, 3, 5), (2, 3, 3),
]
match @directed.yen_k_shortest(0, 3, edges, 3) {
  Ok(paths) => {
    // paths[0]: 代价 5 (0→1→3) 或 5 (0→2→3)
    // 保证 paths[i].cost <= paths[i+1].cost
    for p in paths { println(p) }
  }
  Err(@core.InvalidK(k)) => println("k 必须 > 0")
  Err(e) => println(e)
}
```

**whitebox 用例**：图上仅存在 1 条可达路径（`0 → 1 → 2` 无备选）但请求
`k = 3`，Yen 算法第 1 轮 accept 之后发现候选池 `B` 为空，触发
`candidates.length() == 0 { break }` 分支，返回长度 1 的结果数组——
对应 tasks.md 的 `Requirements 2.3` 验收。

## 变种与改进

| 算法 | 适用 | 特点 |
|------|------|------|
| **Yen 1971** | 一般图 | 教科书标配，本库采用 |
| Eppstein 1998 | 允许环 | 渐进更优 `O(E + V log V + K)`，但路径含环 |
| Hershberger 等 | 替代路径 | 更好的"多样性"指标，非严格最短 |

## 参考文献

- Yen, J. Y. (1971). "Finding the K Shortest Loopless Paths in a Network."
  *Management Science*, 17(11), 712–716.
- Eppstein, D. (1998). "Finding the k shortest paths." *SICOMP*, 28(2), 652–673.
