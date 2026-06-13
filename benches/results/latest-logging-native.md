# Logging_Library 旗舰深化 · 原生基准（native `moon bench`）

> 方向七（R9）`benches/logging_bench` 的原生基准证据。本工件为局部算法级回归
> 证据，非跨语言性能宣称。

## 运行元数据（machine / backend / scale）

| 字段 | 值 |
|---|---|
| schema | `moonbit-pathfinding.logging-bench.v1` |
| generated_at | 2026-06-12T15:24Z |
| backend target | `native` |
| toolchain | moon 0.1.20260608 (60bc8c3 2026-06-08) |
| host kernel | Linux 6.1.x x86_64 (amzn2023) |
| release mode | true (`moon bench`) |

## 运行命令（reproducible）

```bash
# native 后端运行前先导出库路径（R9.4）
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 原生基准（四类工作负载）
moon bench -p Suquster/moonbit-pathfinding/benches/logging_bench --target native

# 冒烟 / 回归 guard（三后端任选；任一后端均须通过）
moon test -p Suquster/moonbit-pathfinding/benches/logging_bench --target wasm-gc
moon test -p Suquster/moonbit-pathfinding/benches/logging_bench --target js
moon test -p Suquster/moonbit-pathfinding/benches/logging_bench --target native
```

## 计时统计（input scale + timing）

| workload | 输入规模 | mean ± σ | range (min … max) |
|---|---|---|---|
| `log_emit_5000` | 5000 条事件发射 | 1.31 ms ± 17.07 µs | 1.29 … 1.34 ms |
| `format_json_1000` | 1000 条事件 JSON 渲染 | 2.36 ms ± 5.05 µs | 2.35 … 2.37 ms |
| `format_logfmt_1000` | 1000 条事件 logfmt 渲染 | 1.61 ms ± 4.06 µs | 1.60 … 1.62 ms |
| `sample_trace_10000` | 10000 个 trace 采样判定 | 178.73 µs ± 480.92 ns | 177.99 … 179.61 µs |
| `sample_stream_2000` | 2000 事件流系统采样 | 14.08 µs ± 183.17 ns | 13.94 … 14.43 µs |
| `span_enter_exit_2000` | 2000 层 span 进入/退出 | 284.01 µs ± 1.41 µs | 282.57 … 286.19 µs |

## 回归 guard（R9.3）

`logging_bench.mbt` 内联回归 guard 对确定性输出精确比较，偏离即审计失败：

- `sample_stream(0.25, n=1000)` 保留条数基线 = `250`（== `floor(rate*n)`）；
- `count_by_level` 计数守恒基线 = `1000`（各级别计数之和 == 事件总数）；
- 固定事件 `format_json` 字节级渲染基线（防渲染回归）。

范围说明：上述为单机算法级时间，受运行环境影响，不构成跨语言或跨机器的性能宣称。
