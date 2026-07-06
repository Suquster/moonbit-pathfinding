# Paper-to-Code 追溯：前沿算法（src/advanced + src/directed 生产级变体）

> 目的：把三大高级寻路算法的**论文原文构造** → **代码位置** → **验证测试**
> 建立逐条可审计的追溯链，供滚动验收与决赛答辩引用。
> 所有行号基于 main（T8 收官后）；差分 oracle 均为库内 Dijkstra / A*，
> 三后端（native / wasm-gc / js）测试全绿。

---

## 1. Contraction Hierarchies（CH）

**论文**：Geisberger, Sanders, Schultes, Delling.
*Contraction Hierarchies: Faster and Simpler Hierarchical Routing in Road
Networks.* WEA 2008.

| 论文构造 | 代码位置 | 说明 |
|---|---|---|
| §2 节点收缩（contraction）：删除节点 v，对每对邻居 (u,x) 加捷径 u→x，权 w(u,v)+w(v,x) | `src/advanced/ch.mbt:138-…`（`contract a single node` 帮助函数） | 逐对枚举未收缩邻居，捷径记录 `middle=v` 供路径展开 |
| §2 witness search：若存在不经 v 的等价/更廉价旁路则**不加**捷径 | `src/advanced/ch.mbt:57-111`（witness Dijkstra，跳数上界 `CH_WITNESS_HOPS`） | 有界 witness 搜索控制预处理开销——论文 §3.2 的 hop limit 技术 |
| §3.1 节点排序 edge difference（加捷径数 − 删边数） | `src/advanced/ch.mbt:279`（`edge_difference`） | 贪心按当前残差图上的 edge difference 选下一个收缩节点 |
| §4 查询：双向 Dijkstra，正向只走「向上」边、反向只走「向上」入边 | `src/advanced/ch.mbt:524-…`（`ch_query`）+ `up_adj`/`dn_adj` 字段（:31-38） | `level[n]`=收缩序；上行图/下行图分别喂前向/后向搜索 |
| §4 meeting node：取 `fwd_dist[m]+bwd_dist[m]` 最小的相遇点 | `src/advanced/ch.mbt:504-554`（meet/best 归并） | 与论文 stopping criterion 一致 |
| §4 路径展开：捷径递归展开为原图边序列 | `ch.mbt` `shortcut` map（`(u,v)→middle`，:39-41）+ 展开例程 | 保证输出的是**原图**最短路径 |

**验证测试（正确性 = 与 Dijkstra 差分逐值相等）**
- `ch_test.mbt`：5 节点图成本/路径逐节点等于 Dijkstra；`source==target`；不可达 `None`；展开路径覆盖全部中间节点。
- `edge_cases_test.mbt`：witness 抑制冗余捷径；捷径替换更贵既有边；带弦双向环；不可达。
- `prop_frontier_diff_test.mbt`（Property 10）：随机图 PBT——CH 成本 ≡ Dijkstra 成本 + 链式 anchor。
- `advanced_ext_test.mbt`（task 19.1）：定制收缩序 `ch_preprocess_with_order` 仍 ≡ Dijkstra；批查询 ≡ 逐对查询。

---

## 2. Jump Point Search（JPS）

**论文**：Harabor, Grastien. *Online Graph Pruning for Pathfinding on Grid
Maps.* AAAI 2011.

| 论文构造 | 代码位置 | 说明 |
|---|---|---|
| 网格模型：直行代价 1、对角 √2，对角合法需两侧直邻均可走（无 corner-cutting） | `src/advanced/jps.mbt:30-32`、`JPSGrid::new`（:44） | 与论文 8 邻域无角穿模型一致 |
| Definition 1/2 forced neighbour（直行）：垂直邻居被堵而其后对角可走 | `jps.mbt:115-131`（`forced_left/right/up/down`） | 直行剪枝的唯一保留条件 |
| forced neighbour（对角）+ 对角跳需递归检查两条直行子方向 | `jps.mbt:134-…`（`diag_forced_a/b` + cardinal sub-jumps） | 论文 Algorithm 2 的对角分解 |
| Algorithm 1 `jump`：沿方向直冲，遇目标/受迫邻居/子跳命中即返回跳点 | `jps.mbt:89-…`（`jump` 递归） | 折叠无分支长廊，等价保持最优性（论文 Theorem 1） |
| `identify_successors`：A* 只扩展跳点 | `jps.mbt:285-…`（`jps` 主入口） | A* 框架 + Octile 启发（:75-77，可采纳） |

**验证测试（正确性 = 与全展开 A* 成本相等 + 锚定路径）**
- `jps_test.mbt`：5×5 开阔网格对角直达；`start==goal` 单点；围死不可达；障碍绕行仍最优；whitebox 拒绝畸形网格输入。
- `edge_cases_test.mbt`：起/终点被堵 `None`；垂直/水平行进中的受迫邻居（论文 Fig.1/2 情形的直接编码）；向上向左跨越开阔网格。
- `prop_frontier_diff_test.mbt`（Property 10）：随机网格 PBT——JPS 成本 ≡ A* 成本 + 开阔网格 anchor。
- `advanced_ext_test.mbt`：`jps_batch` ≡ 逐对 `jps` + anchor。
- 修复记录：2026-06-21「JPS 受迫邻居修复」——对角受迫条件的边界修正（见 main 提交历史），随修复补 `edge_cases_test.mbt` 受迫邻居回归。

---

## 3. ALT（A*, Landmarks, Triangle inequality）

**论文**：Goldberg, Harrelson. *Computing the Shortest Path: A\* Search Meets
Graph Theory.* SODA 2005.

| 论文构造 | 代码位置 | 说明 |
|---|---|---|
| §3 三角不等式下界：`h(n) = max_l max(dist(l,t)−dist(l,n), dist(n,l)−dist(t,l))` | `src/advanced/alt.mbt:8-12`（推导注释）+ `alt_query`（:272）内的 landmark 启发 | 双向表都参与取 max——论文的双侧下界 |
| §3 预处理：从每个 landmark 跑单源 Dijkstra 填 `dist_from`，反图填 `dist_to` | `alt.mbt:149-184`（表构建帮助函数）+ `LandmarkData`（:23-41） | 正/反两张表缺一不可（:194 注释阐明） |
| §5 landmark 选择：farthest-first（每次取距已选集最远者） | `alt.mbt:77-148`（`pick_landmarks`） | 论文实验推荐的 farthest 选点策略 |
| 可采纳性/一致性 ⇒ A* 最优 | `alt_query` 落回 `h=zero()` 当表缺失（:19-20） | 退化即普通 Dijkstra，保证永不高估 |

**验证测试**
- `alt_test.mbt`：5 节点图 ≡ Dijkstra；`source==target` 零成本；不可达 `None`。
- `edge_cases_test.mbt`：零 landmark 退化为 Dijkstra（下界恒 0 的退化正确性）；空节点集不产 landmark。
- `prop_frontier_diff_test.mbt`（Property 10）：随机图 PBT——ALT 成本 ≡ Dijkstra 成本 + 链式 anchor。
- `advanced_ext_test.mbt`：caller 指定 landmark 的 `alt_preprocess_with_landmarks` 仍 ≡ Dijkstra；批查询 ≡ 逐对。

---

## 4. 生产级稠密快路径变体（src/directed，2026-07 新增）

以下变体面向真实路网（OSM 北京/厦门驾车网），全部附全量对拍
一致性校验 + 差分 PBT，证据归档 `benches/results/ch-osm-20260705.md`。

### 4.1 CH 生产级（`src/directed/ch.mbt`）

| 论文构造 | 代码位置 | 说明 |
|---|---|---|
| Geisberger 2008 §3.1 懒更新优先级（edge difference + 已删邻居数） | `ch.mbt`（`prio` + 懒重估主循环） | pop 后重估，劣于堆顶则重新入队；重估与中标收缩共享同一次 witness 搜索（捷径缓冲回放） |
| §3.2 有界 witness 搜索 | `ch.mbt`（`CH_WITNESS_POPS`） | 弹出数上限保守补捷径，只影响捷径数不影响正确性 |
| §4 stall-on-demand | `ch.mbt`（`query` 双向循环内 stall 检查） | 存在更高 rank 节点经下行边给出更短距离则免松弛 |
| §4 捷径展开 | `ch.mbt`（`unpack_edge` 显式栈） | 还原原图路径，PBT 逐边校验权和 |

验证：`src/directed/ch_test.mbt`（120 迭代差分 PBT 含路径合法性）；
OSM 实测北京 46× / 厦门 17×（vs 双向 Dijkstra）。

### 4.2 Hub Labeling（`src/directed/hub_labels.mbt`）

**论文**：Abraham, Delling, Goldberg, Werneck. *A Hub-Based Labeling
Algorithm for Shortest Paths in Road Networks.* SEA 2011.

| 论文构造 | 代码位置 | 说明 |
|---|---|---|
| CH 之上 rank 降序构建 2-hop 标签 | `HubLabels::build`（gather 自上而下合并向上邻居标签） | 正确性由 CH 向上覆盖性保证 |
| 支配剪枝（存在其他公共 hub 给出不更长距离则删条目） | `prune` + `hl_dominated`（归并早退） | 均摊标签长北京 128.9 |
| 查询 = 两条有序标签归并取最小和 | `query` / `hl_merge_min` | 0.44 µs/查询（北京） |
| 路径还原 | `query_via`（距离+经停 hub）/ `query_path`（hub 分界 + 两段 CH 展开） | 80 迭代 PBT：距离最优 + 路径逐边合法 |

验证：`hub_labels_test.mbt`（100 迭代差分 PBT）、`hl_path_test.mbt`；
OSM 实测北京 14304× / 厦门 3815×。

### 4.3 PHAST（`src/directed/phast.mbt`）

**论文**：Delling, Goldberg, Nowatzyk, Werneck. *PHAST: Hardware-Accelerated
Shortest Path Trees.* IPDPS 2011.

| 论文构造 | 代码位置 | 说明 |
|---|---|---|
| 向上 Dijkstra + rank 降序线性下行扫描 | `one_to_all` | 无堆的第二阶段，位置空间 CSR（`dofs/dsrc/dwt`）缓存友好 |
| 一到全最短路树 | `one_to_all_tree`（PHAST + 一次原图边扫描定父指针） | 父链距离严格递减无环；60 迭代 PBT |

验证：`phast_test.mbt`（80+60 迭代 PBT）；OSM 实测 5.95–6.15×（vs
全量 Dijkstra），树版 ~2.2×。

### 4.4 RPHAST（`src/directed/rphast.mbt`）

| 论文构造 | 代码位置 | 说明 |
|---|---|---|
| 目标子集反向向上 BFS 提取受限空间 R | `rphast_targets` | \|R\| 仅全图 0.1–0.5%，预处理亚毫秒 |
| 每源向上 Dijkstra + 受限下行扫描 | `rphast_query` | 北京 9.8× / 厦门 6.9×（vs PHAST 每源） |

验证：`rphast_test.mbt`（60 迭代多源 PBT）。

### 4.5 Many-to-many 距离表（`src/directed/many_to_many.mbt`）

**论文**：Knopp, Sanders, Schultes, Schulz, Wagner. *Computing Many-to-Many
Shortest Paths Using Highway Hierarchies.* ALENEX 2007（bucket 法）。

| 论文构造 | 代码位置 | 说明 |
|---|---|---|
| 后向向上搜索在中转节点填桶 | `many_to_many` Phase 1（`bkt_j/bkt_d`） | 每 target 一次 |
| 前向向上搜索扫桶归并 | `many_to_many` Phase 2 | 一次算 \|S\|×\|T\| 全表 |

验证：`many_to_many_test.mbt`（60 迭代 PBT + 64×64 全表对拍）；
OSM 实测每对相对逐对 CH 北京 16.0× / 厦门 24.8×。

### 4.6 辅助基础设施

- **Radix heap（单调桶队列，Ahuja, Mehlhorn, Orlin, Tarjan 1990）**：
  `src/directed/`（`RadixHeap`），大权 Dijkstra/A*/双向 NBA*/CH 查询
  全线换装。
- **ALT 生产级（`src/directed/alt.mbt`）**：farthest 选点 + 节点主序
  布局 + INF 统一截断保证下界可采纳一致；OSM 北京 6.6×。

---

## 5. 取舍与已知边界（答辩 Q&A 素材）

- **CH witness 预算**（`CH_WITNESS_HOPS`，`ch.mbt:51-54`）：小预算 → 预处理快但可能多加冗余捷径（不影响正确性，只影响查询规模）；论文 §3.2 同款权衡。
- **CH 无 stall-on-demand（仅 src/advanced 教学版）**：生产级
  `src/directed/ch.mbt` 已实现 stall-on-demand（见 §4.1）。
- **JPS 仅支持均匀代价 8 邻域网格**：论文同款假设；加权网格需 JPS+ 变体。
- **ALT landmark 数量**：farthest-first 的 k 可调，k=0 时严格退化为 Dijkstra（有测试锁定）。
