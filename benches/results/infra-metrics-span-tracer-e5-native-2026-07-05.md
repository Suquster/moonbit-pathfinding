# E5 · tracing span 树（增量火焰聚合）vs 朴素事件回放 — native

- 日期：2026-07-05 · 后端：native · 命令：`moon bench -p benches/infra_metrics_bench --target native`
- 实现：`src/infra_metrics/span_tracer.mbt`——对标 OpenTelemetry SDK span
  管线 + pprof/火焰图聚合：活动 span 栈隐式给出父子（O(1)/事件），span
  结束点即时结算 total（含子）/ self（不含子）并按名增量累入聚合表；
  任意时刻查询聚合 O(名字数)，与 trace 规模无关。时间戳显式传入，
  同一事件流产出逐位一致的树与聚合（确定性时钟约定同 DST/timer wheel）。

## 流式 trace + 高频聚合查询（嵌套 ≤12 层、6 个名字，每 64 事件查询一次）

| n（事件数） | 增量聚合 tracer | 朴素事件日志全量回放/查询 | 倍率 |
|---|---|---|---|
| 8000 | 725.86 µs ± 31.82 µs | 1.48 ms ± 92.47 µs | 2.0× |
| 32000 | 2.90 ms ± 100.32 µs | 41.21 ms ± 1.79 ms | **14.2×** |
| 128000 | 12.03 ms ± 761.97 µs | 801.19 ms ± 9.70 ms | **66.6×** |

- 朴素做法每次查询回放全部已有事件 O(已有事件数)——高频查询（面板刷新/
  告警评估）下总量 O(n²/64)，随 trace 增长持续劣化；增量结算侧近线性，
  差距随规模持续放大（数量级级别）。

## 验证

- 三后端（native / wasm-gc / js）全绿、`moon check` 0 告警。
- 差分 PBT：与朴素事件回放参照逐名 (count, total, self) 等价 200 迭代
  （随机嵌套 ≤12 层、随机时间步）；嵌套结算/多根/未结束 span/空栈 end
  定向锁定；确定性重放逐位一致。
