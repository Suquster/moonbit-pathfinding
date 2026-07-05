# E4 · O(1) 位图优先级就绪队列 vs 朴素线性扫描 — native

- 日期：2026-07-05 · 后端：native · 命令：`moon bench -p benches/infra_timer_bench --target native`
- 实现：`src/infra_timer/priority_sched.mbt`——对标 Linux O(1) 调度器
  （Molnar 2002）就绪队列：64 级优先级各一条环形 FIFO + 64 位占用位图，
  `pick_next` 用 de Bruijn 乘法 find-first-set（Leiserson/Prokop/Randall 1998）
  常数步定位最高非空优先级；enqueue/pick_next 均严格 O(1)。

## 稳态高 churn（live ≈ 2048 就绪任务，2:1 enqueue/pick 交替，n 次操作）

| n | 位图调度（O(1)/操作） | 朴素线性扫描（O(live)/pick） | 倍率 |
|---|---|---|---|
| 32000 | 386.72 µs ± 22.14 µs | 30.50 ms ± 1.82 ms | **78.9×** |
| 128000 | 1.46 ms ± 59.97 µs | 119.72 ms ± 6.42 ms | **82.0×** |

- 朴素参照每次 pick 扫描全部就绪任务挑最小 (prio, seq)——正确但 O(live)；
  位图调度与就绪规模无关，churn 越大差距越稳。

## 验证

- 三后端（native / wasm-gc / js）全绿、`moon check` 0 告警。
- 差分 PBT：与朴素参照（最小 prio、级内最早 seq）逐操作等价 200 迭代
  （enqueue/pick_next/peek_priority/len）；确定性 trace 重放逐位一致；
  级内 FIFO、0/63 边界与夹取、位图翻转/环形回绕定向锁定。
