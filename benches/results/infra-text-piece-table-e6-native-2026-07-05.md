# E6 · piece-table 变体 vs 朴素 String 拼接 — native

- 日期：2026-07-05 · 后端：native · 命令：`moon bench -p benches/infra_text_bench --target native`
- 实现：`src/infra_text/piece_table.mbt`——对标 VS Code 文本缓冲的线性
  piece 变体 / 经典 piece-table（Crowley 1998）：文档 = 只读 original +
  append-only add 缓冲上的 piece 序列，insert 命中 piece 最多一分为三、
  delete 收缩/剔除，编辑不移动任何已有文本字节，单次编辑 O(#pieces)
  与文档字节数无关。与 rope 互补：结构更简单、原始文本零拷贝、
  不可变缓冲天然支撑 undo。

## 随机小编辑（100k 字符文档 × 256 次编辑：2/3 插入 8 字符、1/3 删除 ≤8 字符）

| 负载 | piece-table | 朴素 String 拼接（每编辑 O(n) 重建） | 倍率 |
|---|---|---|---|
| 100k×256 | 459.58 µs ± 20.74 µs | 21.09 ms ± 876.98 µs | **45.9×** |

- 差距随文档规模线性放大（朴素每次编辑重建全文档；piece-table 只碰
  常数个 piece），编辑序列越长/文档越大优势越稳。

## 验证

- 三后端（native / wasm-gc / js）全绿、`moon check` 0 告警。
- 差分 PBT：与朴素 String 参照逐编辑等价 250 迭代（insert/delete/len/
  to_string/code_unit_at 点查）；与 Rope 交叉差分 100 迭代（同编辑序列
  终态逐位一致）；分裂/跨 piece 删除/空文档/夹取/全删定向锁定。
