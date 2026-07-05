# 万级 actor 吞吐基准（ActorSystem）

- actor 数: 10000; 每 actor 消息: 10; 总消息: 100000
- 单轮中位耗时: 8.902283666666666 ms（采样 3）
- 消息吞吐: 11233072.742271263 msgs/sec
- 正确性门禁: 全部消息恰好处理一次（见同名 guard 测试）

## 复现方式

```bash
moon bench -p benches/actor_bench --target native
```

- 采集时间（UTC）: 2026-07-05
- cell_by_id O(1) 直索引 + 有界邮箱 O(1) 出队后复测
