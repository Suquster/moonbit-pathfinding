# 算法中文讲解索引

> 每篇约 400 字，按难度与交付里程碑分组；英文对照版位于
> [`docs/algorithms/`](../../algorithms/)（筹备中，暂由 `src/**/*.mbt` 的
> Doc_Comment 兜底）。

## MVP (v0.1.0 / v0.2.0) — 8 个算法

| # | 算法 | 文档 | 源码 |
|---|------|------|------|
| 1 | BFS（广度优先搜索）             | [bfs.md](./bfs.md)                                      | `src/unweighted/bfs.mbt`                      |
| 2 | DFS（深度优先搜索）             | [dfs.md](./dfs.md)                                      | `src/directed/dfs.mbt`                        |
| 3 | Dijkstra 最短路                 | [dijkstra.md](./dijkstra.md)                            | `src/directed/dijkstra.mbt`                   |
| 4 | A\* 启发式搜索                  | [astar.md](./astar.md)                                  | `src/directed/astar.mbt`                      |
| 5 | Bellman-Ford 负权最短路         | [bellman_ford.md](./bellman_ford.md)                    | `src/directed/bellman_ford.mbt`               |
| 6 | Floyd-Warshall 全源最短路       | [floyd_warshall.md](./floyd_warshall.md)                | `src/directed/floyd_warshall.mbt`             |
| 7 | Kruskal 最小生成树              | [kruskal.md](./kruskal.md)                              | `src/undirected/kruskal.mbt`                  |
| 8 | 连通分量                        | [connected_components.md](./connected_components.md)   | `src/undirected/connected_components.mbt`     |

## 进阶 (v0.3.0) — 7 个算法

| # | 算法 | 文档 | 源码 |
|---|------|------|------|
|  9 | 双向 BFS                      | [bidirectional_bfs.md](./bidirectional_bfs.md) | `src/directed/bidirectional_bfs.mbt` |
| 10 | 拓扑排序（Kahn）              | [topo_sort.md](./topo_sort.md)                 | `src/directed/topo_sort.mbt`         |
| 11 | Tarjan 强连通分量             | [tarjan_scc.md](./tarjan_scc.md)               | `src/directed/tarjan_scc.mbt`        |
| 12 | Edmonds-Karp 最大流           | [edmonds_karp.md](./edmonds_karp.md)           | `src/directed/edmonds_karp.mbt`      |
| 13 | IDA\*                         | [ida_star.md](./ida_star.md)                   | `src/directed/ida_star.mbt`          |
| 14 | Yen's K 最短路                | [yen.md](./yen.md)                             | `src/directed/yen.mbt`               |
| 15 | Kuhn-Munkres（匈牙利算法）    | [kuhn_munkres.md](./kuhn_munkres.md)           | `src/undirected/kuhn_munkres.mbt`    |

## 前沿 (v1.0.0) — 3 个算法 🚧

| # | 算法 | 文档 | 源码 |
|---|------|------|------|
| 16 | Contraction Hierarchies | 🚧 筹备中 | `src/advanced/ch.mbt`   |
| 17 | Jump Point Search       | 🚧 筹备中 | `src/advanced/jps.mbt`  |
| 18 | ALT (A\* + Landmarks)   | 🚧 筹备中 | `src/advanced/alt.mbt`  |

---

每篇文档结构统一为：**背景 / 核心思想 / 算法步骤 / 时间复杂度 /
典型场景 / API 示例 / 参考文献**，方便快速查阅与答辩引用。
