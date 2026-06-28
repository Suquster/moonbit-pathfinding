# Regex 字面量预过滤（T2.1）基准证据 — native

对标 Rust `regex` / RE2 的字面量预过滤（literal prefilter）：在 Pike VM 播种线程
前，用首字符集快速跳过不可能成为匹配起点的位置。本工件量化其在「稀疏命中长文本」
场景的提速。

## 工作负载

- 模式：字面量 `needle`（首字符集 = `{'n'}`）。
- 输入：`sparse_haystack(2000, 500)` —— 2000 个词、每 500 词插入一次 `needle` 的
  长文本（填充词 `lorem ipsum dolor sit amet` 不含字符 `n`），命中极稀疏。
- 操作：`Pattern::find_all`，开启 vs 关闭预过滤（`without_prefilter`）。

## 结果（native，`moon bench`）

| 基准 | 均值时间 | 备注 |
|------|---------|------|
| `regex_sparse_prefilter_on`  | **276.50 µs ± 4.09 µs** | 启用字面量预过滤 |
| `regex_sparse_prefilter_off` | **5.58 ms ± 72.01 µs**  | 禁用预过滤（纯 Pike VM 逐位播种） |

**提速比 ≈ 20.2×**（5.58 ms / 276.5 µs），远超纲领 KPI（≥5×）。

确定性佐证（非计时，`moon test` 下恒成立）：guard
`prefilter eliminates majority of seed positions on sparse text` 证明预过滤把
需要播种 Pike VM 的位置数从 O(n) 削减到 <5%（与命中数同阶）。

## 复现

```bash
export LIBRARY_PATH=/usr/lib64:/usr/lib   # native 链接需要
moon bench -p Suquster/moonbit-pathfinding/benches/regex_bench --target native
# 确定性 guard（三后端）：
moon test  -p Suquster/moonbit-pathfinding/benches/regex_bench --target wasm-gc
moon test  -p Suquster/moonbit-pathfinding/benches/regex_bench --target native
moon test  -p Suquster/moonbit-pathfinding/benches/regex_bench --target js
```

## 正确性保证

提速不改变任何匹配语义。差分属性测试 `src/regex_engine/prop_prefilter_test.mbt`
（≥200 迭代）证明开/关预过滤在 `exec`（含各捕获组）/ `find` / `find_all` /
`is_match` 上逐字段相等，并覆盖可空退化、锚点、忽略大小写折叠、无候选起点提前
终止等关键分支。
