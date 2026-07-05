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
| BFS | 1000 | 4 | 1.608 | 0.619 | **2.60×** | ✅ |
| Dijkstra | 1000 | 4 | 5.285 | 2.626 | **2.01×** | ✅ |
| A* | 1000 | 4 | 6.579 | 5.303 | **1.24×** | ✅ |
| BFS | 1000 | 16 | 1.502 | 0.517 | **2.91×** | ✅ |
| Dijkstra | 1000 | 16 | 10.749 | 5.268 | **2.04×** | ✅ |
| A* | 1000 | 16 | 12.618 | 9.294 | **1.36×** | ✅ |
| BFS | 10000 | 4 | 17.515 | 7.770 | **2.25×** | ✅ |
| Dijkstra | 10000 | 4 | 55.104 | 23.564 | **2.34×** | ✅ |
| A* | 10000 | 4 | 75.213 | 63.422 | **1.19×** | ✅ |
| BFS | 10000 | 16 | 10.414 | 4.119 | **2.53×** | ✅ |
| Dijkstra | 10000 | 16 | 136.924 | 51.869 | **2.64×** | ✅ |
| A* | 10000 | 16 | 159.338 | 111.802 | **1.43×** | ✅ |

- **Median of per-case median speedups: 2.15×（此前 0.2498×）**——12/12
  用例全部快于 Rust，其中 Dijkstra 2.0-2.6×、BFS 2.3-2.9×。
- 全部 12 用例两侧结果签名逐元素一致（正确性交叉验证通过）。

## 变更点（逐层累积）

1. indexed 快路径：CSR 邻接 + visited/dist/parent 扁平数组 +
   (dist<<21|node) Int64 编码堆（无哈希无装箱）→ 0.25× → 1.41×。
2. 编码堆升级 4 叉堆 + 持洞上滤/下滤（每层一次赋值、更浅更缓存友好）
   → 1.41× → 1.55×。
3. 可复用 SearchCtx / BfsCtx（generation 戳懒失效，批量查询免每次
   O(n) 初始化）+ 打包边 (w<<21|v) 单数组边扫描。
4. 小整数边权（≤1024）自动切换 **Dial 桶队列**（Dial 1969，O(E+D)
   无堆无比较）→ Dijkstra 1.0-1.3× → 2.0-2.6×，总中位 **2.15×**。

全部变体与通用 Map 泛型版差分 PBT（150/150/120/120/100/60 迭代）守卫，
三后端（native/wasm-gc/js）全绿、0 告警。
