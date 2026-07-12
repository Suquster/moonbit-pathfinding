# 真实 OSM 路网端到端 showcase（厦门驾车网，路径级校验，2026-07-12）

> 命令：`moon bench -p benches/advanced_bench --target native`
> （用例 `bench: real OSM end-to-end path showcase`，
> 源码 `benches/advanced_bench/osm_showcase_bench.mbt`）。
> 链路：嵌入真实 OSM 负载 → CSR 解析 → CH 预处理 →
> `ch_csr_query` 路径展开 → 逐边校验。

- 数据集: OpenStreetMap 厦门驾车网（osmnx 提取，权重=道路分米）
- 节点数: 23925; 有向边数: 54151
- 随机查询对: 32; 可达: 31（1 对不可达，与 Dijkstra 判定一致）
- 路径级校验（端点/逐边存在于原图/逐边权重求和=查询代价=独立 Dijkstra 代价）: **true**
- 可达路径总跳数: 2306
- 最长路径样例: 节点 18540→5726，183 跳，代价 418249 分米（约 41.82 km）

## 意义

既有 OSM 基准（`osm-suite-native-2026-07-12.md` 等）验证的是**代价**
对拍一致；本 showcase 把证据链推进到**可行驶路径**层面——CH 展开的
每条路径的每条边都真实存在于原始路网 CSR，且逐边权重求和与查询代价、
与独立 Dijkstra 三方逐位一致，不可达判定也与 Dijkstra 一致。
数据→索引→查询→路径的全链路在真实城市路网上闭环。
