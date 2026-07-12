# INFRA 基准实测：时间 / 韧性 / CLI / PBT+fuzz（native）

- 日期：2026-07-12
- 工具链：moon 0.1.20260703 (6fbf8c3 2026-07-03)
- 命令（native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）：
  - `moon bench -p benches/infra_time_bench --target native`
  - `moon bench -p benches/infra_resilience_bench --target native`
  - `moon bench -p benches/infra_cli_bench --target native`
  - `moon bench -p benches/infra_pbt_bench --target native`
- 环境：Ubuntu x86_64 CI 型虚拟机，结果为 `moon bench` 报告的 mean ± σ。

## 时间（infra_time，256 个确定性 DateTime / 每次迭代）

| bench | mean | σ |
|---|---:|---:|
| parse_iso8601_256 | 49.19 µs | 323.33 ns |
| format_iso8601_256 | 140.85 µs | 648.05 ns |
| strftime_256 | 82.58 µs | 1.17 µs |
| civil_roundtrip_256 | 4.20 µs | 11.50 ns |
| tz_offset_at_256 | 7.97 µs | 170.32 ns |

解读：civil 双向换算（Howard Hinnant 算法族）与 POSIX TZ 偏移求解都是
纯整数运算，单次约 16 ns / 31 ns；字符串解析/格式化以分配为主，
`format_iso8601` 约为 `parse_iso8601` 的 2.9×。

## 韧性（infra_resilience，4096 次调用 / 每次迭代）

| bench | mean | σ | 单次调用 |
|---|---:|---:|---:|
| circuit_breaker_4096_ops | 2.38 µs | 5.53 ns | ~0.6 ns |
| token_bucket_4096_ops | 4.35 µs | 13.34 ns | ~1.1 ns |
| aimd_4096_ops | 3.96 µs | 87.72 ns | ~1.0 ns |
| backoff_jittered_4096 | 6.93 µs | 26.03 ns | ~1.7 ns |
| sliding_window_4096_ops | 14.67 µs | 136.27 ns | ~3.6 ns |

解读：五种原语的每次调用开销都在个位数纳秒级，可安全放进请求热路径；
滑动窗口因需维护时间片桶而略贵于纯计数器方案。

## CLI（infra_cli，512 次调用 / 每次迭代）

| bench | mean | σ | 单次调用 |
|---|---:|---:|---:|
| validate_rules_512 | 15.80 µs | 259.74 ns | ~31 ns |
| parse_512 | 608.32 µs | 16.59 µs | ~1.2 µs |
| help_text_512 | 587.30 µs | 2.40 µs | ~1.1 µs |
| suggest_option_512 | 2.19 ms | 11.77 µs | ~4.3 µs |

解读：完整子命令解析（含短参展开与默认值）单次约 1.2 µs，对交互式
CLI 完全无感；拼写建议是 Damerau-Levenshtein 对全部候选的逐一距离
计算，属于错误路径上的一次性成本。

## PBT 与 fuzz（infra_pbt + infra_fuzz）

| bench | mean | σ |
|---|---:|---:|
| holds_for_all_200_iters | 533.41 ns | 14.98 ns |
| check_with_shrink_falsified | 2.00 µs | 41.11 ns |
| frequency_gen_1024 | 8.82 µs | 36.89 ns |
| fuzz_graph_gen_64 | 24.09 µs | 114.72 ns |

解读：200 次属性检查亚微秒级；从随机反例缩小到边界值（500_000）
含全部 shrink 步骤仅 ~2 µs；16 节点种子化图每个生成约 0.38 µs，
可支撑大规模 fuzz 会话。

## 复现

以上均可用文首命令在 native 后端复现；对应冒烟测试
（`moon test -p benches/<name>`）额外校验了行为正确性
（熔断器开闸、令牌桶补给、AIMD 收敛、ISO 8601 往返、shrink 到边界值、
种子可复现的图生成），确保基准测的是真实语义而非空转。
