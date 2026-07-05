# 核心寻路快路径 · indexed（CSR + 扁平数组 + 编码堆） vs 泛型 Map 版 — native

- 日期：2026-07-05 · 后端：native · 命令：`moon bench -p benches/dijkstra_bench --target native`
- 实现：`src/unweighted/bfs_indexed.mbt`、`src/directed/dijkstra_indexed.mbt`
  ——稠密整数节点（0..n-1）图的快路径：CSR 邻接（offsets/targets/weights
  扁平数组）、visited/dist/parent 全扁平数组、(dist << 21 | node) Int64
  编码二叉堆（懒删除、无装箱无哈希）；`astar_indexed` 支持可采纳启发式。
  与通用 Map 泛型版语义一致（同图同查询最短代价/边数相同），差分 PBT 守卫。

## Rust 对比矩阵同款负载（n=1000、平均出度 16、100 查询/次）

| 算法 | indexed | 泛型 Map 版 | 倍率 |
|---|---|---|---|
| BFS | 592.12 µs ± 17.70 µs | 8.10 ms ± 215.35 µs | **13.7×** |
| Dijkstra | 9.62 ms ± 275.71 µs | 38.80 ms ± 1.24 ms | **4.0×** |

- 参照 2026-06-21 Rust `pathfinding` crate 对比（benches/results/
  latest-rust-comparison.md，同负载 n=1000/deg=16/100 查询）：Rust BFS
  中位 1.82 ms、Dijkstra 14.30 ms——indexed 快路径把本库从 0.19-0.30×
  劣势翻转为 BFS ≈3.1×、Dijkstra ≈1.5× **优于 Rust 泛型 API**（跨机器
  参考口径，正式对比需同机重跑 rust_comparison 采集）。

## 验证

- 三后端（native / wasm-gc / js）全绿、`moon check` 0 告警。
- 差分 PBT：`bfs_indexed` vs 泛型 `bfs` 150 迭代（最短边数一致 + 路径
  合法性逐边验证）；`dijkstra_indexed` vs 泛型 `dijkstra` 150 迭代
  （最短代价一致 + 路径真实边/代价复核）；`astar_indexed`（零启发式）
  vs `dijkstra_indexed` 80 迭代等价；自身/不可达/越界定向锁定。
- 适用域：节点数 < 2^21（≈2M）、总代价 < 2^42；超出走通用泛型版。
