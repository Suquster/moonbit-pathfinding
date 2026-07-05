
- 数据集: synthetic 4-connected weighted grid（R8.7 合成替身）
- 节点数: 250000（side=500）; 有向边数: 998000
- 查询对: 24; 预热: 3; 采样: 12
- CH 层级图边数: up=1136884 dn=1138873
- 代价对拍全一致: true
- CH 预处理耗时: 29877.985238 ms
- Dijkstra 每查询中位耗时: 18630.0320625 µs
- CH 每查询中位耗时（代价）: 111.96191666666668 µs
- CH 每查询中位耗时（含路径展开）: 245.7798541666667 µs
- 中位加速比: 166.39615163042788x（门槛 ≥100x: PASS）

===CH_CSR_EVIDENCE_END===

## 复现方式

```bash
moon bench -p benches/advanced_bench --target native
```

- 采集时间（UTC）: 2026-07-05
- 排序估值加权 2·ED - deg + 2·DN 后复测（166.4×，前值 151.9×）
