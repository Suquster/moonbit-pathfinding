# CH(CSR) vs Dijkstra — 真实 OSM 路网基准（厦门驾车网，R21.1）

- 数据集: OpenStreetMap 厦门驾车路网（osmnx 提取，权重=道路米长）
- 节点数: 23925; 有向边数: 54151
- 查询对: 48; 预热: 3; 采样: 12
- CH 层级图边数: up=66953 dn=66926
- 代价对拍全一致: true
- CH 预处理耗时: 1861.544161 ms
- Dijkstra 每查询中位耗时: 1181.4254791666667 µs
- CH 每查询中位耗时（代价）: 25.26105208333333 µs
- 中位加速比: 46.76865695337149x


## 复现方式

```bash
./benches/osm/download.sh   # 拉取真实路网并生成 TSV
moon bench -p benches/advanced_bench --target native
```

- 采集时间（UTC）: 2026-07-05
- 说明: 2.4 万节点城市路网上 46.8×；≥100× 门槛证据见 25 万节点基准（更大真实路网北京网抓取中）。
