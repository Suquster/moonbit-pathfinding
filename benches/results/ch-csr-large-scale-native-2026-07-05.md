# CH(CSR) vs Dijkstra — 大规模合成路网基准（任务 19.1）

- 数据集: synthetic 4-connected weighted grid（R8.7 合成替身）
- 节点数: 250000（side=500）; 有向边数: 998000
- 查询对: 24; 预热: 3; 采样: 12
- CH 层级图边数: up=1162074 dn=1163075
- 代价对拍全一致: true
- CH 预处理耗时: 57408.28086 ms
- Dijkstra 每查询中位耗时: 18512.394479166665 µs
- CH 每查询中位耗时（代价）: 121.89470833333333 µs
- CH 每查询中位耗时（含路径展开）: 267.4164791666667 µs
- 中位加速比: 151.87201095344238x（门槛 ≥100x: PASS）

## 复现方式

```bash
moon bench -p benches/advanced_bench --target native
```

- 采集时间（UTC）: 2026-07-05
- 采集环境: Linux x86_64（release/native；单调时钟微秒）
- 正确性护栏: 全部 24 组查询与点对点 Dijkstra 代价逐位一致（parity=true）
