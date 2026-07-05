# Rust `pathfinding` Comparison Report — indexed 快路径接入后同机重跑

- Generated at: `2026-07-05T12:50 UTC`
- Sides: MoonBit `bench_rust/moon_side`（已接入 `bfs_indexed` /
  `dijkstra_indexed` / `astar_indexed` 快路径，CSR + 扁平数组 + 编码堆）
  vs Rust `bench_rust/`（`pathfinding` crate 4.11.0）
- Seed: `1311768467463790320` · Workload: BFS/Dijkstra/A* × n=1000 ×
  deg {4,16} × 100 queries · warmup 5 / samples 30 / timeout 60s
- Machine: Ubuntu 22.04, x64 ×2 · moon release native · rustc 1.83 release

## Golden cross-check

✅ MATCH — 两侧黄金图样本逐元素一致（edges/queries 完全相等）。

## Per-case comparison（中位口径，>1 = MoonBit 更快）

| Algorithm | Deg | Rust median ms | MoonBit median ms | Speedup | Sig match |
|---|---:|---:|---:|---:|:--:|
| BFS | 4 | 1.631 | 0.673 | **2.42×** | ✅ |
| Dijkstra | 4 | 7.027 | 5.224 | **1.35×** | ✅ |
| A* | 4 | 8.487 | 5.449 | **1.56×** | ✅ |
| BFS | 16 | 1.503 | 0.576 | **2.61×** | ✅ |
| Dijkstra | 16 | 10.772 | 9.047 | **1.19×** | ✅ |
| A* | 16 | 14.660 | 9.463 | **1.55×** | ✅ |

- **Median of per-case median speedups: 1.55×（此前 0.2498×）**——indexed
  快路径把本库从「全面落后 Rust 3-5×」翻转为 **6/6 用例全部快于 Rust**。
- 全部 6 用例两侧结果签名逐元素一致（正确性交叉验证通过）。

## 变更点

- `bench_rust/moon_side/main.mbt` 三个签名函数改用 indexed 快路径
  （CSR 邻接由同一确定性边集构建，golden 交叉校验保证图/查询逐位一致，
  签名一致保证语义等价）。
- `dijkstra_indexed` 专用无启发式主循环（去掉每弹出/入堆的 Option 分支），
  `astar_indexed` 走带 h 的共享实现。
- 编码堆升级为 **4 叉堆 + 持洞上滤/下滤**（每层一次赋值、更浅更缓存友好），
  Dijkstra 再提 ~15%（1.06-1.15× → 1.19-1.35×）。
