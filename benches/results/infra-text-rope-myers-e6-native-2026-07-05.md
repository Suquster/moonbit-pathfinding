# E6 · Rope + Myers diff vs 朴素参照 — native

- 日期：2026-07-05 · 后端：native · 命令：`moon bench -p benches/infra_text_bench --target native`
- 实现：
  - `src/infra_text/rope.mbt`——Boehm/Atkinson/Plass 1995 rope：Leaf/Concat 二叉树
    + split/concat 编辑、深度超界（> 2·⌈log₂ n⌉ + 4）全量重建、相邻小叶合并抑制碎片化；
  - `src/infra_text/myers_diff.mbt`——Myers 1986 §4a 贪心正向 O((N+M)·D) 最短编辑脚本
    （V 快照回溯），附 O(N·M) DP LCS 参照。

## Rope 随机编辑 vs 朴素字符串整篇重建（doc=65536 码元，512 次混合 insert/delete）

| 实现 | 耗时 | 倍率 |
|---|---|---|
| Rope（split/concat O(log n)） | 785.01 µs ± 34.73 µs | — |
| 朴素整篇重建（O(n)/编辑） | 27.03 ms ± 1.54 ms | **34.4×** |

- 朴素参照每次编辑拷贝整篇 65536 码元；Rope 仅重建 O(log n) 条 split/concat 路径。
- 百万码元文档 + 512 次随机编辑的平衡不变量与逐点一致性由
  `rope_test.mbt`「million-char scale」测试锁定（深度 ≤ 2·⌈log₂ n⌉ + 4）。

## Myers diff vs O(N·M) 全量 DP（相似文本 n=4096，8 处单点变异，D=16）

| 实现 | 耗时 | 倍率 |
|---|---|---|
| myers_diff（O((N+M)·D)） | 143.26 µs ± 5.69 µs | — |
| DP LCS（O(N·M)） | 29.32 ms ± 1.30 ms | **204.7×** |

- 相似文本（D ≪ N+M）下 Myers 只扩展 D 层对角线；DP 无条件扫描全部 N·M 单元格。
- 最小性由差分 PBT 锁定（120 迭代 `diff_edit_cost == lcs_dp_cost`）；
  round-trip（apply==b、source==a）200 迭代；编辑受限性质（k 次变异 ⇒ D ≤ 2k）60 迭代。

## 批次 2 · 编辑器级索引（xi-editor metric 体系）

- 每节点缓存 (UTF-16 码元数, UTF-8 字节数, 换行数)，孤立代理项按 WTF-8 计
  3 字节；UTF-8↔UTF-16 偏移双向转换、行列定位、行首偏移均
  O(log n + 叶内扫描)。

| 负载 | Rope 索引 | 朴素全扫描 | 倍率 |
|---|---|---|---|
| line_col_at（doc=1M 码元，256 查询） | 142.39 µs ± 10.13 µs | 81.20 ms ± 6.03 ms | **570×** |

- 度量维护后 rope 编辑基准为 1.62 ms（vs 朴素 44.08 ms，**27.2×**）——
  维持数量级优势的同时换来 O(log n) 全套编辑器索引。
- 差分 PBT：随机编辑后 utf16_to_utf8/utf8_to_utf16 round-trip、line_col_at、
  offset_of_line、utf8_len 与朴素全扫描逐点一致 200 迭代
  （负载含换行/2B/3B/4B 代理对字符）；1B/2B/3B/4B/换行定向锁定。

## 验证

- 三后端（native / wasm-gc / js）2097 测试全绿、`moon check` 0 告警。
- 差分 PBT：Rope 与朴素字符串重建逐操作等价 200 迭代（insert/delete/slice/charcode_at/len）。
