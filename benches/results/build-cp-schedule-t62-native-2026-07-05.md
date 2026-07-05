# Build_Tool T6.2 关键路径优先调度基准（native, 2026-07-05）

环境：`moon bench -p benches/build_tool_bench --target native`（Ubuntu，`LIBRARY_PATH=/usr/lib64:/usr/lib`）。

## makespan（批次数）对比 —— guard 用例锁定

「长链 + 独立扇出」混合图（链 64 节点 + 64 个独立目标，`jobs = 2`）：

| 调度器 | makespan（波数） | 说明 |
|---|---:|---|
| FIFO 分层切块 `schedule` | > 64（首层 65 目标按原序切 33 波 + 链尾 63 波 ≈ 96） | 宽首层槽位浪费在独立目标上 |
| **CP 优先 `schedule_critical_path`** | **64（= 关键路径下界）** | 每波链目标先行、独立目标填充剩余槽位 |

守护测试 `guard: critical-path schedule shortens makespan vs FIFO` 断言
`cp.length() == 64 && fifo.length() > cp.length() && cp.length() >= critical_path_length(g)`。

属性测试（`prop_cp_schedule_test.mbt`，100 iters × jobs ∈ {1,2,3}）：
拓扑不变量 / 完整性 / 波宽 ≤ jobs / `critical_path_length ≤ len(cp) ≤ len(fifo)` /
`jobs<=0` 退化一致 全部成立。

## 调度耗时（时间，非 makespan）

| 基准 | 耗时（mean ± σ） |
|---|---:|
| `bt_topo_order_800`（邻接表预建后） | 2.28 ms ± 0.11 ms |
| `bt_schedule_800_j8`（FIFO） | 2.66 ms |
| `bt_cp_schedule_800_j8`（CP 优先，含 rank DP） | 7.16 ms |
| `bt_cp_schedule_mix_512_j2` | 1.17 ms |
| `bt_fifo_schedule_mix_512_j2` | 204 µs |

## 顺带热路径修复（积少成多）

`topo_order` / `detect_cycle` 原对**每个**节点线性扫全边集取后继（O(V·E)）：
800 节点分层网格上 `bt_topo_order_800` 为 **72.2 ms**。预建整图邻接表
（`adjacency_of`，一次 O(V+E)）后降至 **2.28 ms（31.7× 加速）**，
CP 调度（内部两次拓扑）随之从 72.4 ms 降至 7.16 ms。
