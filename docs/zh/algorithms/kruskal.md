# Kruskal · 最小生成树（MST）

## 背景

Joseph Kruskal 在 1956 年的论文 *On the shortest spanning subtree of a graph
and the traveling salesman problem* 中提出此算法，与 Prim 算法（1957）并称
最小生成树的两大经典解法。由于 Kruskal 对**边**而非**顶点**排序，它在
**稀疏图**上通常比 Prim 更快，也更贴合"只有边列表"的输入形态（CSV / SQL
行 / 网络抓包）。

## 核心思想

**"按边权升序贪心 + 并查集避环"**：

1. 把所有边按权**升序**排序；
2. 初始化并查集 DSU，每个节点自成一个集合；
3. 依次遍历排序后的边 `(u, v, w)`：若 `u` 与 `v` 不在同一集合，就把这条边
   选入 MST 并合并集合，否则跳过（跳过的边必会形成环）；
4. 直到选够 V−1 条边即止（连通图必然在此时结束；非连通图则输出最小生成
   森林，边数少于 V−1）。

**正确性证明**（切分引理 Cut Property）：对于任何切分 (S, V\S)，**横跨
该切分的最小权边必属于某棵 MST**。Kruskal 的每次选择都对应某个切分下的
最小横跨边，因此最终结果就是 MST。

## 算法步骤

```
edges.sort_by_weight_ascending()
dsu ← DSU::new()
for v in nodes: dsu.make_set(v)
mst ← []
for (u, v, w) in edges:
  if dsu.find(u) != dsu.find(v):
    dsu.union(u, v)
    mst.push((u, v, w))
    if len(mst) == V − 1: break
return mst
```

## 时间复杂度

- **时间** O(E log E) + O(α(V) · E) ≈ **O(E log E)**：排序主导，DSU 近似
  常数摊销；
- **空间** O(V + E)：DSU 与排序边列表各 V、E。

## 典型场景

1. **网络布线**：电网 / 光纤铺设最小成本骨架；
2. **聚类**：Single-Link Hierarchical Clustering 的效率版（砍掉最重的
   K−1 条边 = K 簇聚类）；
3. **近似 TSP**：2× 近似算法以 MST 为起点构造欧拉环路；
4. **交叉验证**：本库与 DSU `tests/core/` 的 PBT 做结构不变式检查
   （|MST| = V−1、无环、覆盖所有顶点，对应 R13.4）。

## MoonBit API 示例

```moonbit
let nodes = [0, 1, 2, 3]
let edges : Array[(Int, Int, Int)] = [
  (0, 1, 1), (1, 2, 2), (2, 3, 3), (3, 0, 4),
]
let mst = @undirected.kruskal_mst(nodes, edges)
// mst 含 3 条边 (V−1), 总权 = 1 + 2 + 3 = 6
```

**注意**：本库 `kruskal_mst` 的 `edges` 视作**无向**（每条边只需列一次）；
若输入是有向边列表，请自行去重或在外层加无向化层。

## 参考文献

- Kruskal, J. B. (1956). "On the shortest spanning subtree of a graph and
  the traveling salesman problem." *Proc. AMS*, 7(1), 48–50.
- CLRS 23.2。
- DSU（并查集）实现见 `src/core/dsu.mbt`；这是 Kruskal 高效的基石。
