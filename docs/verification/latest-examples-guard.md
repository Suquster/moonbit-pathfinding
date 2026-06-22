# Examples Guard Report

- Generated at: 2026-06-22T05:20:50Z
- Script: scripts/examples_guard.ps1
- Doc file: README.mbt.md（文档即测试 · R20.4/R20.5/R21.6）
- MoonBit: moon 0.1.20260608 (60bc8c3 2026-06-08)  Feature flags enabled: rr_moon_mod,rr_moon_pkg
- Backends: wasm-gc
- Expected total tests: 28（示例 6 段 + Cookbook 22 例）
- Status: PASSED

## 各后端文档测试汇总

| 后端 | 退出码 | 总数 | 通过 | 失败 | 状态 |
| --- | ---: | ---: | ---: | ---: | --- |
| wasm-gc | 0 | 28 | 28 | 0 | passed |

## 覆盖范围说明

- 示例 1~6：BFS / Dijkstra / A* / Kruskal / proof predicates / 复杂度表，含 ASCII 可视化（R20.1/R20.4）。
- Cookbook 22 例：网格寻路 / 网络路由 / 任务调度 / 最大流 / 匹配 五类，每例含可执行命令与 inspect 预期输出（R21.1/R21.5）。
- 任一示例编译失败或结果不符 → 门禁失败并定位（R20.5）；Cookbook 输出与预期不符 → 可重现性校验失败（R21.6）。

