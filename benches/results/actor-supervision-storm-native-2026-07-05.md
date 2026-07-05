# 监督树失败风暴压力测试（生产级语义守卫）

- 拓扑: root → 8 mid（OneForOne/OneForAll/RestForOne 轮转）→ 每 mid 32 leaf
- 风暴: 1000 轮 × (1 失败注入 + 8 正常消息)
- 事件总数: 9000（正常 8000 + 失败 1000）
- 重启总次数: 17087（≥ 注入轮数 1000）
- 风暴后全部恢复 Running: true
- 单轮风暴中位耗时: 14481.474142857143 µs
- 风暴事件吞吐: 621483.690901673 events/sec

## 复现方式

```bash
moon bench -p benches/actor_bench --target native
```

- 采集时间（UTC）: 2026-07-05
