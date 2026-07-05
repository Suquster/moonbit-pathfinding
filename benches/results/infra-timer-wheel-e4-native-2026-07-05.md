# E4 · 层级定时器轮 vs 朴素每 tick O(n) 扫描 — native

- 日期：2026-07-05 · 后端：native · 命令：`moon bench -p benches/infra_timer_bench --target native`
- 实现：`src/infra_timer/timer_wheel.mbt`——Varghese & Lauck 1987，5 级 × 64 槽
  层级轮 + 回绕 cascade 降级；schedule/cancel/expire 摊销 O(1)，cancel O(1) 打标记。
- 负载：n 个定时器随机延迟 ∈ [1, 4096]（跨多层 cascade），推进 4096 tick 至全部触发。

| n | timer wheel（摊销 O(1)/定时器） | 朴素扫描（O(n)/tick） | 倍率 |
|---|---|---|---|
| 1000 | 155.01 µs ± 4.63 | 9.17 ms ± 0.25 | 59× |
| 4000 | 329.32 µs ± 10.22 | 47.25 ms ± 1.20 | 143× |
| 16000 | 703.24 µs ± 21.56 | 197.92 ms ± 3.79 | 281× |

- wheel 侧每 tick 只碰当前槽（+ 回绕时一次 cascade），总量 O(T + n)；朴素 O(n·T)——
  倍率随 n 线性拉大，数量级优势稳定。

## 正确性证据

`src/infra_timer/timer_wheel_test.mbt`：
- 定向：第 0 层内精确触发、延迟 64/65/200 跨层 cascade 精确落点、取消
  （触发前/跨 cascade/幂等/已触发不可取消）、pending 计数。
- 差分 PBT **200 迭代**：随机 schedule（延迟 1..5000 覆盖多层）/cancel/advance
  操作序列，与朴素 O(n) 扫描定时器**逐 tick 到期集合**（排序比较）、时钟、
  pending 全部一致。
- 单线程确定性：`advance` 显式返回到期 id 序列，同操作序列逐 tick 可复现（DST 前提）。
- 三后端（native/wasm-gc/js）全绿。
