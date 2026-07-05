# Rust `pathfinding` Comparison Report — indexed 快路径接入后同机重跑

- Generated at: `2026-07-05T13:02 UTC`
- Sides: MoonBit `bench_rust/moon_side`（已接入 indexed 快路径：CSR +
  扁平数组 + 4 叉编码堆 + 可复用 SearchCtx/BfsCtx + 小整数权 Dial 桶队列）
  vs Rust `bench_rust/`（`pathfinding` crate 4.11.0）
- Seed: `1311768467463790320` · Workload: BFS/Dijkstra/A* × n {1000,10000}
  × deg {4,16} × 100 queries · warmup 5 / samples 30 / timeout 60s
- Machine: Ubuntu 22.04, x64 ×2 · moon release native · rustc release

## Golden cross-check

✅ MATCH — 两侧黄金图样本逐元素一致（edges/queries 完全相等）。

## Per-case comparison（中位口径，>1 = MoonBit 更快）

| Algorithm | n | Deg | Rust median ms | MoonBit median ms | Speedup | Sig match |
|---|---:|---:|---:|---:|---:|:--:|
| BFS | 1000 | 4 | 1.608 | 0.048 | **33.6×** | ✅ |
| Dijkstra | 1000 | 4 | 5.285 | 0.502 | **10.5×** | ✅ |
| A* | 1000 | 4 | 6.579 | 1.004 | **6.55×** | ✅ |
| BFS | 1000 | 16 | 1.502 | 0.066 | **22.7×** | ✅ |
| Dijkstra | 1000 | 16 | 10.749 | 1.271 | **8.46×** | ✅ |
| A* | 1000 | 16 | 12.618 | 1.670 | **7.56×** | ✅ |
| BFS | 10000 | 4 | 17.515 | 0.249 | **70.4×** | ✅ |
| Dijkstra | 10000 | 4 | 55.104 | 1.445 | **38.1×** | ✅ |
| A* | 10000 | 4 | 75.213 | 2.636 | **28.5×** | ✅ |
| BFS | 10000 | 16 | 10.414 | 0.267 | **39.0×** | ✅ |
| Dijkstra | 10000 | 16 | 136.924 | 4.185 | **32.7×** | ✅ |
| A* | 10000 | 16 | 159.338 | 5.449 | **29.2×** | ✅ |

- **Median of per-case median speedups: 28.9×（此前 0.2498×）**——12/12
  用例全部快于 Rust：BFS 23-70×、Dijkstra 8.5-38×、A* 6.6-29×。
- 全部 12 用例两侧结果签名逐元素一致（正确性交叉验证通过）。

## 变更点（逐层累积）

1. indexed 快路径：CSR 邻接 + visited/dist/parent 扁平数组 +
   (dist<<21|node) Int64 编码堆（无哈希无装箱）→ 0.25× → 1.41×。
2. 编码堆升级 4 叉堆 + 持洞上滤/下滤（每层一次赋值、更浅更缓存友好）
   → 1.41× → 1.55×。
3. 可复用 SearchCtx / BfsCtx（generation 戳懒失效，批量查询免每次
   O(n) 初始化）+ 打包边 (w<<21|v) 单数组边扫描。
4. 小整数边权（≤1024）自动切换 **Dial 桶队列**（Dial 1969，O(E+D)
   无堆无比较）→ Dijkstra 1.0-1.3× → 2.0-2.6×。
5. A* 同样桶化：**桶式 Dial A\***（一致启发式下弹出 f 单调不减，
   f 落循环桶 + 超窗条目 overflow 重分发，正确性不依赖增量上界）
   → A* 1.2-1.4× → 2.0-2.8×。
6. BFS 升级**层同步双向 BFS**（正向沿出边、反向沿逆图出边，每轮
   扩展较小前沿整层，整层收尾后取最小会合；搜索空间 ~O(b^(d/2))）
   → BFS 2.3-3.0× → **26-77×**。
7. Dijkstra 升级**双向 Dial Dijkstra**（正/反两侧各自 Dial 桶扫描，
   每轮推进当前扫描距离较小一侧，松弛时维护会合上界 μ，
   d_f + d_b > μ 终止，meet-in-the-middle 经典判据）
   → Dijkstra 2.0-2.6× → **4.0-20×+**。
8. A* 升级**双向 A\*（NBA* 剪枝式，Pijls & Post 2009）**：正/反
   两支 A* 每轮扩展堆顶 f 较小一侧，弹出节点满足
   `f(u) ≥ μ` 或 `g(u) + F_other − h_other(u) ≥ μ` 即剪枝
   → A* 2.0-2.8× → 3.2-9.0×。
9. 双向 A* 再桶化：小整数边权（≤1024）自动切换**桶式双向
   Dial A\***（两侧各自 f 循环桶 + overflow 重分发，无堆无比较，
   NBA* 剪枝判据不变）→ A* 3.2-9.0× → 4.1-21.8×。
10. **Dial 桶数组并入 SearchCtx 跨查询复用**（此前每查询分配
    m=maxw+1 个空桶，小图批量查询的主要分配开销；现只清空
    复用）→ 全线抬升：Dijkstra 8.5-38×、A* 6.6-29×，
    总中位 **28.9×**。

全部变体与通用 Map 泛型版/堆版差分 PBT（150/150/120/120/100/80/60
迭代，含完美一致启发式桶式 A* 专项）守卫，三后端（native/wasm-gc/js）
全绿、0 告警。
