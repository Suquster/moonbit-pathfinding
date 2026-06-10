# Contraction Hierarchies · 分层收缩（🚧 v1.0.0）

> **状态**：🧪 experimental — `src/advanced/ch.mbt` 与 `ch_test.mbt` 已落地；仍需真实路网基准、收缩顺序调优和论文到代码追踪后升级为稳定 API。

## 背景

Robert Geisberger、Peter Sanders、Dominik Schultes、Daniel Delling 于 2008 年
在 *Contraction Hierarchies: Faster and Simpler Hierarchical Routing in Road
Networks* 中提出，是**现代路网导航的工业标准**。Google Maps、Bing Maps、
OSRM 等真实路网引擎都基于 CH 或其衍生（CHASE, CRP）——在 10 万～1000 万
节点级别的国家路网上实现非常低延迟查询；具体加速比高度依赖路网规模、
收缩顺序、硬件和实现细节。本库文档不把论文或工业系统数据当作当前实测。

## 核心思想

**"预处理 + 双向上下半 Dijkstra"**：

1. **收缩节点**：按某种启发式顺序（常用 edge-difference 或 online-edge-
   difference）从图中逐个"压扁"节点。压扁节点 `v` 时，检查其每一对邻居
   `(u, w)`，若原图里 `u → v → w` 就是 `u → w` 的最短路径，就在 CH 图里
   加一条"**捷径边**" `u → w`（权 = `w(u,v) + w(v,w)`），同时标记 `v` 的
   **层级**为当前收缩轮次；
2. **查询时**：双向 Dijkstra 同时从 `s` 向**高层**走、从 `t` 向**高层**走，
   两边只走**层级递增**的边（正图一半、反图一半），前沿相交时拼接路径；
3. **展开捷径**：回溯时若遇到捷径 `u → w`（背后压着 `v`），递归展开为
   `u → v → w`，直到得到原图上的真实路径。

**正确性**核心：CH 保持了"节点间最短距离不变"（证人路径检查保证了捷径
边代价 = 原图最短路径），但把搜索空间从所有节点压到"每层级最多往上走
一次"的双向搜索。

## 预处理与查询复杂度

| 阶段 | 复杂度 | 备注 |
|------|--------|------|
| 预处理 | O(V · E · log V) 经验值 | 一次性，可并行到多核 |
| 单次查询 | O(√E · log V) 经验值 | 需本库 benchmark artifact 验证 |
| 空间 | O(V + E + 捷径) | 捷径通常 1~3 倍原图 |

## 典型场景

1. **全球路网导航**：OSM 全球路网 ≈ 10 亿节点，CH 把 30 秒 Dijkstra 压到
   毫秒级响应；
2. **静态路径服务**：数据相对稳定（道路新增 / 关闭低频），预处理开销
   可分摊到百万次查询；
3. **多目标查询**：One-to-Many / Many-to-Many（送餐、网约车）用 CH-SEARCH
   扩展，数量级加速；
4. **本库基准对照**：M4 里程碑将在真实或生成路网上对比 CH / ALT / Dijkstra，
   加速比必须来自可复现 benchmark artifact，而不是沿用论文数字。

## 当前 API

```moonbit skip
// 一次性预处理
let graph = @advanced.ch_preprocess(nodes, successors)
// graph 包含层级、上下半图、捷径记录
// 多次查询
let path1 = @advanced.ch_query(graph, source, target1)  // 毫秒级
let path2 = @advanced.ch_query(graph, source, target2)
```

详细签名见 `src/advanced/ch.mbt`（里程碑交付后填充）。

## 与其他加速方案

| 方案 | 性能叙事 | 预处理 | 更新成本 | 适合 |
|------|----------|--------|----------|------|
| **CH** | 路网查询加速方案，依赖收缩顺序和 shortcut 质量 | 重 | 高 | 静态路网 |
| ALT | 用 landmark 启发式减少搜索方向噪声 | 中（选地标）| 低 | 中小路网 + 动态 |
| CRP | 通过可定制分区适配轻度动态路网 | 中（按区划分）| 中 | 路网 + 轻度动态 |
| 朴素 Dijkstra | 无预处理基线 | 无 | 无 | 千节点级 |

本库选择 CH + ALT 组合：CH 作为主力，ALT 作为动态备份（`src/advanced/alt.mbt`）。

## 参考文献

- Geisberger, R., Sanders, P., Schultes, D., & Delling, D. (2008).
  "Contraction Hierarchies: Faster and Simpler Hierarchical Routing in Road
  Networks." *WEA 2008*, LNCS 5038, 319–333.
- Delling, D., Goldberg, A., Pajor, T., & Werneck, R. F. (2011).
  "Customizable Route Planning." *SEA 2011*.
