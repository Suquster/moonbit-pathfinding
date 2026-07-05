# 万级 actor 吞吐基准（ActorSystem，任务 T10）

- 负载: 10 000 actor × 10 条消息 = 100 000 条调度事件
- 驱动: `run_until_idle_throughput`（轮转批量调度，旁路新增）
- 单轮中位耗时: 8.58 ms（采样 3，native）
- 消息吞吐: **11 659 967 msgs/sec（≈11.66M）**
- 对照: 逐步驱动 `run_until_idle` 同负载 8 058.84 ms ≈ 12 409 msgs/sec
- 提升: **≈940×**（每消息 O(A) 全量就绪扫描 → 轮转批量摊还 O(A×轮数+消息数)）
- 追加优化: Mailbox 队首游标出队（O(n) 头删 → 摊还 O(1)），单 actor 高频
  send 5000 msgs: 2 370 µs → 444.8 µs（≈5.3×，≈11.2M msgs/sec）
- 正确性门禁: 全部消息恰好处理一次（三后端常跑 guard 测试）；
  终态与逐步驱动差分一致（计数/转发链/显式停止结算，src/actor/throughput_test.mbt）

## 复现方式

```bash
moon test -p benches/actor_bench            # 门禁
moon bench -p benches/actor_bench --target native   # 证据输出
```

- 采集时间（UTC）: 2026-07-05
- 采集环境: Linux x86_64（release/native；单调时钟微秒）
