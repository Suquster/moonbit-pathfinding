# 上手教程 —— 每个方向五分钟

英文完整版见 [`docs/tutorials/README.md`](../tutorials/README.md)。本页按方向给出
关键 API、最小片段与对应可运行 demo（片段均取自 `examples/` 下真实代码，可编译
可运行）。任一 demo 用 `moon run examples/<名称>` 运行。

寻路核心算法的可执行文档见 [`docs/zh/algorithms/`](./algorithms/README.md)。

| 方向 | demo | 关键 API |
|---|---|---|
| 寻路核心 | maze_solver / network_routing / eight_puzzle | `dijkstra(start, neighbors, is_goal)`，节点任意 `Eq + Hash` 类型 |
| 迷你编译器 | mini_compiler_pipeline | 词法→语法→HM 推断→优化→字节码 VM+TCO、解释器差分、JS 发射 |
| 正则引擎 | regex_toolkit | 命名捕获、`replace_all`、`split`、线性时间抗 ReDoS |
| 结构化日志 | log_pipeline | trace span + W3C traceparent、JSON/logfmt/pretty、PII 脱敏 |
| Actor | actor_worker_pool | 监督重启（`SupervisorSpec`）、路由策略、有界邮箱背压 |
| 构建工具 | build_pipeline | 波次调度、脏闭包增量重建、缓存执行、auto-bisect |
| 序列化 | serialization_studio | .proto 解析、二进制/JSON 往返、破坏性变更检测 |
| DST | dst_explorer | 种子确定性重放、DPOR、缩小、线性一致性 |
| 配置+差分 | config_diff_ops | TOML/INI、统一 diff、patch 应用/回退、diff3、semver |
| 哈希 | hash_integrity | `sha256_hex`（与 sha256sum 一致）、`hmac_sha256`、`hkdf`、`pbkdf2_hmac_sha256`、流式 `Sha256Hasher`、`xxhash64` 分片 |
| 压缩 | compress_workbench | `deflate`/`zstd_compress_entropy`/`lz4_compress` 无损往返、`zlib_compress_with_dict` 字典、损坏 CRC 拒绝 |
| 时间+定时器 | time_scheduler | `parse_iso8601`、`parse_posix_tz` 夏令时、`parse_duration("2h30m")`、`TimerWheel`、`WorkStealingScheduler` |
| 韧性原语 | resilience_gateway | `retry_run` 封顶退避、`CircuitBreaker` 状态机、`TokenBucket`/`SlidingWindowLimiter`、`Bulkhead`、`AimdLimiter::create(initial, min, max)`、`hedge_schedule` |
| CLI | cli_devtool | 子命令解析、类型化校验 + choices、`suggest_option` 拼写建议、`help_text`、`completion_bash` |
| 指标 | observability_kit | `HdrHistogram` 尾部分位数、可合并 `DDSketch`、`SpanTracer` total vs self |
| 文本+数据结构 | text_editor_core | `Rope::delete(lo, hi)` 半开区间（`PieceTable::delete(off, count)` 是计数）、`grapheme_count`、`myers_diff`、`LruCache`、`BloomFilter`、`RoaringBitmap` |
| 解析器组合子 | parser_playground | `parse_and_eval`（优先级/结合性正确）、`parse_json_recover` 错误恢复、`run_incremental` + `drive` 增量解析 |
| PBT + fuzz | pbt_fuzz_lab | `holds_for_all`、`check_with_shrink` 最小反例、`round_trip` 往返律、`fuzz_graph_gen` 种子化图、`shrink_fuzz_graph` |

## 性能证据

- 哈希/压缩原生基准（含解读）：
  [`benches/results/infra-hash-compress-native-2026-07-12.md`](../../benches/results/infra-hash-compress-native-2026-07-12.md)
  —— 16 KiB 下 xxHash64 比 SHA-256 快约 7.5×；36 KB 下 LZ4 往返比 DEFLATE 快约 7×。
- 其余方向基准见 `benches/`（timer/metrics/text/parser/codec/actor/dst 等），
  结果归档于 `benches/results/`。
- 全量门禁：`bash scripts/acceptance.sh`。
