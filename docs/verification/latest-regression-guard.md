# Regression Guard Report

- Generated at: 2026-06-22T05:18:45Z
- Script: scripts/regression_guard.ps1
- Baseline: `/home/ubuntu/repos/moonbit-pathfinding/benches/results/latest-native.json` （schema: `moonbit-pathfinding.benchmark-native.v1`）
- Current: `/home/ubuntu/repos/moonbit-pathfinding/benches/results/latest-native.json` （schema: `moonbit-pathfinding.benchmark-native.v1`）
- Tolerance: 10.00% （中位回归严格大于即失败）
- Status: PASSED
- Compared algorithms: 4
- Regressed algorithms: 0

## 逐算法回归判定（算法 / 基线中位 / 当前中位 / 回归百分比）

| 算法 | 基线中位 | 当前中位 | 回归百分比 | 中位加速比 | 判定 |
| --- | ---: | ---: | ---: | ---: | :--: |
| BFS | 131.6 | 131.6 | 0.00% | 1x | 通过 ✅ |
| Dijkstra | 648 | 648 | 0.00% | 1x | 通过 ✅ |
| A* | 360.69 | 360.69 | 0.00% | 1x | 通过 ✅ |
| Kruskal MST | 3520 | 3520 | 0.00% | 1x | 通过 ✅ |

