# Paper-to-Code 追溯：CH / JPS / ALT（src/advanced）

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

## 4. 取舍与已知边界（答辩 Q&A 素材）

- **CH witness 预算**（`CH_WITNESS_HOPS`，`ch.mbt:51-54`）：小预算 → 预处理快但可能多加冗余捷径（不影响正确性，只影响查询规模）；论文 §3.2 同款权衡。
- **CH 无 stall-on-demand**：论文 §4 的查询期加速技术未实现——正确性不受影响，属纯性能优化，列为后续项。
- **JPS 仅支持均匀代价 8 邻域网格**：论文同款假设；加权网格需 JPS+ 变体。
- **ALT landmark 数量**：farthest-first 的 k 可调，k=0 时严格退化为 Dijkstra（有测试锁定）。
