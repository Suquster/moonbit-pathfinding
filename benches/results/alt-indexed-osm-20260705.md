# ALT(indexed) 地标启发式 —— 实验证据（2026-07-05）

新增 `@directed.AltLandmarks`：稠密整数节点快路径版 ALT（Goldberg &
Harrelson 2005），farthest 选点 + 正/反向全源 Dijkstra 预处理，节点主序
（`u*k+i`）布局 + INF 统一截断（保持下界可采纳且一致），提供
`h_to/h_from` 及预绑定端点的 `h_to_closure/h_from_closure`，可直接喂给
`astar_indexed_ctx` / `astar_bidirectional_ctx`。

同时 `dijkstra_bidirectional_ctx` 的大权（>1024）/零权回退从**单向**
Dijkstra 升级为**堆式双向**（零启发式 NBA*，meet-in-the-middle）。

## 正面证据：真实 OSM 路网（moon bench -p benches/advanced_bench -f osm_alt_bench.mbt）

| 数据集 | 节点/边 | k | 单向 Dijkstra | 双向 Dijkstra | ALT 双向 A* | ALT vs 双向 | 预处理 |
|---|---|---|---|---|---|---|---|
| 厦门驾车网 | 23925 / 54151 | 8 | 912.6 µs | 626.4 µs | 602.3 µs | **1.04×** | 20.7 ms |
| 北京驾车网 | 163501 / 406591 | 16 | 9903.4 µs | 7353.3 µs | 1113.8 µs | **6.60×** | 546.9 ms |

大权（>1024）堆式双向 Dijkstra（本次升级的回退路径）相对旧单向
回退在真实路网上即得 **1.35–1.46×**；叠加 ALT 后北京网相对旧单向
共计 **8.9×**。

代价全量对拍一致（48 查询 × 2 数据集）。路网越大、度量结构越明显，
地标下界越紧，收益越大；预处理成本在 ~90+ 查询即摊薄（北京：546.9 ms ÷
(7353.3−1113.8) µs ≈ 88 查询回本）。

## 反面证据（实验证伪）：合成随机图不适用 ALT

在 rust-comparison 工作负载（uniform 随机图，n=1000/10000, deg=4/16,
100 查询）上把 A* 的零启发式换成 ALT（k=4，预处理计入）后**全面变慢**：

| 用例 | 零启发式双向 A* 中位 | ALT k=4 中位 |
|---|---|---|
| 1000 / deg4 | 0.815 ms | 1.849 ms |
| 1000 / deg16 | 1.354 ms | 4.274 ms |
| 10000 / deg4 | 2.337 ms | 13.815 ms |
| 10000 / deg16 | 5.239 ms | 36.382 ms |

原因：uniform 随机图是 expander（直径 O(log n)、距离高度集中），
任意地标的 d(u,L)−d(t,L) ≈ 0，三角不等式下界退化为零启发式，
而每次 h 求値多付 k 轮数组读 + 预处理多付 (2k+1) 次全量扫描。
结论：rust-comparison 基准侧维持零启发式双向 A*（该 8.1× 用例的
剩余差距属启发式信息缺失，非实现效率问题）；ALT 作为库能力面向
真实路网/层次结构图景提供，正确性由 `src/directed/alt_test.mbt`
差分 PBT（可采纳性 + 逐边一致性 + 单/双向 A* 代价对拍）守卫。

## 附：h 代戳记忆化实验证伪

尝试在 astar_bidial/biheap 入口统一将 h 包一层代戳记忆（每节点
每查询只求値一次）：rust-comparison 零启发式工作负载上 A* 中位从
0.81/1.42/2.36/5.20 ms 劣化到 0.97/1.77/3.14/6.96 ms（廉价 h 下
记忆查表的分支+写开销超过闭包重算），已回退；重型 h 场景由
调用方自行选择预绑定闭包（h_to_closure/h_from_closure）即可。
