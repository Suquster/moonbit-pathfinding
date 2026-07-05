# LSP T5.1 rope 化增量同步 基准（native）

- Generated at: `2026-07-05T09:48:28Z`
- Target: `native`，Linux x86_64
- Run command（native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）:
  - `moon bench -p benches/lsp_bench --target native`

## 改动内容

`RopeDocument`（src/lsp_server/rope_sync.mbt）：高度平衡 rope（join-based
balanced tree，参照 Blelloch/Ferizovic/Sun 2016 join 算法，键改为码位权重），
节点缓存码位数/换行数/高度；单条增量变更 = split×2 + join×2 =
O(log N + L + M)，替代参照实现 `apply_changes` 的每条 O(N) 全文物化。
Position→码位索引换算：换行计数下降定位行首 O(log N) + 行内码元扫描 O(L)，
语义与 `position_to_cp_index` 逐一致（UTF-8/16/32 三编码 + 错误路径由等价性
PBT 100 迭代 ×3 编码锁定）。

## 工作负载：N 行文档 × 16 次均匀分布的单点等长替换（逐条应用）

| N 行 | 参照 O(N)（string） | rope O(log N) | 加速比 |
|---:|---:|---:|---:|
| 1024 | 1.09 ms | 66.48 µs | 16.4× |
| 4096 | 4.69 ms | 63.89 µs | 73.4× |
| 16384 | 19.44 ms | 85.18 µs | **228×** |

趋势：参照实现随 N 线性增长（1.09→4.69→19.44 ms，×4.3/×4.1）；rope 基本
持平（66→64→85 µs），呈对数级——文档规模每翻 16 倍加速比同步扩大，
满足 KPI「长文档增量编辑达对数级更新」。

## 原始输出

sync_string_1024 1.09 ms ± 31.59 µs；sync_rope_1024 66.48 µs ± 3.27 µs；
sync_string_4096 4.69 ms ± 218.47 µs；sync_rope_4096 63.89 µs ± 1.75 µs；
sync_string_16384 19.44 ms ± 664.31 µs；sync_rope_16384 85.18 µs ± 11.35 µs。
