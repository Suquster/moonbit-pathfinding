# Proof Report

- Generated at: 2026-06-21T10:35:08Z
- Script: scripts/proof_pipeline.ps1
- Package: src/proofs
- MoonBit: moon 0.1.20260608 (60bc8c3 2026-06-08)  Feature flags enabled: rr_moon_mod,rr_moon_pkg
- Backends: wasm-gc
- moon prove status: blocked-missing-why3
- Why3 available: False
- any_failed: false

## 各后端谓词测试汇总

| 后端 | 退出码 | 总数 | 通过 | 失败 | 状态 |
| --- | ---: | ---: | ---: | ---: | --- |
| wasm-gc | 0 | 99 | 99 | 0 | passed |

## 证明条目（算法 / 性质 / 结果 / 证据）

| 算法 | 性质 | 结果 | 证据 |
| --- | --- | --- | --- |
| BFS | 无权最短路后置条件（合法性/可达/最小性） | 通过 | src/proofs/bfs_proof.mbt::bfs_post · moon test src/proofs (wasm-gc) 通过 |
| BFS-All | 多源/全分量 BFS 后置条件 | 通过 | src/proofs/unweighted_family_proof.mbt::bfs_all_post · moon test src/proofs (wasm-gc) 通过 |
| DFS | DFS 路径合法性与可达一致 | 通过 | src/proofs/unweighted_family_proof.mbt::dfs_post · moon test src/proofs (wasm-gc) 通过 |
| Bidirectional-BFS | 双向 BFS 与单向 BFS 等价 | 通过 | src/proofs/unweighted_family_proof.mbt::bidirectional_bfs_post · moon test src/proofs (wasm-gc) 通过 |
| Dijkstra | 非负权最短路后置条件（合法/代价一致/非负） | 通过 | src/proofs/dijkstra_proof.mbt::dijkstra_post · moon test src/proofs (wasm-gc) 通过 |
| A-Star | A* 最短路后置条件 | 通过 | src/proofs/shortest_path_family_proof.mbt::astar_post · moon test src/proofs (wasm-gc) 通过 |
| Bellman-Ford | 含负权最短路后置条件 | 通过 | src/proofs/shortest_path_family_proof.mbt::bellman_ford_post · moon test src/proofs (wasm-gc) 通过 |
| DAG-SP | DAG 最短路后置条件 | 通过 | src/proofs/shortest_path_family_proof.mbt::dag_sp_post · moon test src/proofs (wasm-gc) 通过 |
| Bidirectional-Dijkstra | 双向 Dijkstra 与单向等价 | 通过 | src/proofs/shortest_path_family_proof.mbt::bidirectional_dijkstra_post · moon test src/proofs (wasm-gc) 通过 |
| IDA-Star | IDA* 最短路后置条件 | 通过 | src/proofs/shortest_path_family_proof.mbt::ida_star_post · moon test src/proofs (wasm-gc) 通过 |
| Yen | K 最短路逐条合法且非降序 | 通过 | src/proofs/shortest_path_family_proof.mbt::yen_post · moon test src/proofs (wasm-gc) 通过 |
| Johnson | 全对最短路（Johnson）后置条件 | 通过 | src/proofs/shortest_path_family_proof.mbt::johnson_post · moon test src/proofs (wasm-gc) 通过 |
| Floyd-Warshall | 全对最短路矩阵后置条件 | 通过 | src/proofs/shortest_path_family_proof.mbt::floyd_warshall_post · moon test src/proofs (wasm-gc) 通过 |
| Kruskal | 最小生成树不变量与最小性 | 通过 | src/proofs/spanning_connectivity_proof.mbt::mst_post · moon test src/proofs (wasm-gc) 通过 |
| Prim | 最小生成树不变量 | 通过 | src/proofs/spanning_connectivity_proof.mbt::mst_post · moon test src/proofs (wasm-gc) 通过 |
| Connected-Components | 连通分量等价类划分正确 | 通过 | src/proofs/spanning_connectivity_proof.mbt::components_partition_post · moon test src/proofs (wasm-gc) 通过 |
| Tarjan-SCC | 强连通分量划分正确 | 通过 | src/proofs/spanning_connectivity_proof.mbt::scc_partition_post · moon test src/proofs (wasm-gc) 通过 |
| Bridges | 报告的每条桥确为桥（删后两端不连通） | 通过 | src/proofs/spanning_connectivity_proof.mbt::bridges_post · moon test src/proofs (wasm-gc) 通过 |
| Condensation | 缩点后必为 DAG | 通过 | src/proofs/spanning_connectivity_proof.mbt::condensation_is_dag · moon test src/proofs (wasm-gc) 通过 |
| Edmonds-Karp | 最大流合法（守恒/容量约束） | 通过 | src/proofs/flow_matching_proof.mbt::max_flow_valid · moon test src/proofs (wasm-gc) 通过 |
| Dinic | 最大流合法（守恒/容量约束） | 通过 | src/proofs/flow_matching_proof.mbt::max_flow_valid · moon test src/proofs (wasm-gc) 通过 |
| Min-Cut | 最大流 = 最小割 | 通过 | src/proofs/flow_matching_proof.mbt::max_flow_equals_min_cut · moon test src/proofs (wasm-gc) 通过 |
| Min-Cost-Flow | 最小费用流合法且费用一致 | 通过 | src/proofs/flow_matching_proof.mbt::min_cost_flow_valid · moon test src/proofs (wasm-gc) 通过 |
| Hopcroft-Karp | 匹配合法（无公共端点） | 通过 | src/proofs/flow_matching_proof.mbt::matching_valid · moon test src/proofs (wasm-gc) 通过 |
| Kuhn-Munkres | 完美匹配权重一致 | 通过 | src/proofs/flow_matching_proof.mbt::perfect_matching_weight · moon test src/proofs (wasm-gc) 通过 |
| Eulerian | 欧拉迹合法（逐边消耗、含重边） | 通过 | src/proofs/flow_matching_proof.mbt::eulerian_trail_valid · moon test src/proofs (wasm-gc) 通过 |
| Topo-Sort | 拓扑序合法（无重复、边方向一致） | 通过 | src/proofs/flow_matching_proof.mbt::topo_order_post · moon test src/proofs (wasm-gc) 通过 |
| Dijkstra-Loop | 弹出键单调不减不变式 | 通过 | src/proofs/loop_invariants.mbt::dijkstra_pop_monotonic · moon test src/proofs (wasm-gc) 通过 |
| BFS-Loop | 层级单调（相邻层差 ≤ 1）不变式 | 通过 | src/proofs/loop_invariants.mbt::bfs_level_invariant · moon test src/proofs (wasm-gc) 通过 |

## 环境限制（R11.6）

- moon prove 存在但 Why3 不在 PATH，静态证明无法在本机执行；仅输出运行时谓词结果。

## Interpretation

全部运行时证明谓词在所选后端通过；官方 moon prove 静态验证受本机环境限制无法执行（已记录环境限制，不影响门禁）。

