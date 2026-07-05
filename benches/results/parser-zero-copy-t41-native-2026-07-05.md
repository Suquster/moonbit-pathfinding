# Parser_Combinator T4.1 零拷贝输入 基准对照（native）

- Generated at: `2026-07-05T09:38:15Z`
- MoonBit: `moon 0.1.20260629 (3e587ed 2026-06-29)`
- Target: `native`，Linux x86_64
- Run command（native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）:
  - `moon bench -p benches/parser_json_bench --target native`
  - `moon bench -p benches/parser_arith_bench --target native`

## 改动内容

`Input` 由 `chars : Array[Char]`（`from_string` 时 O(n) 全量物化）改为直接
持有源 `String` 并以 UTF-16 码元偏移索引（`String::get_char`），构造 O(1)、
零字符物化；`advance` 按码元宽度推进（BMP 1 / 增补平面 2）。

## 与改动前工件（latest-parser-combinator.md，同机同法）对照

| Workload | Size | 改动前 packrat | 改动后 packrat | 提升 |
|---|---:|---:|---:|---:|
| json flat array | 16 | 100.78 µs | 80.73 µs | +24.8% |
| json flat array | 64 | 383.60 µs | 310.25 µs | +23.6% |
| json flat array | 256 | 1.52 ms | 1.23 ms | +23.6% |
| json nested | 8 | 55.46 µs | 45.93 µs | +20.7% |
| json nested | 16 | 106.02 µs | 85.43 µs | +24.1% |
| json nested | 32 | 208.58 µs | 177.53 µs | +17.5% |

arith 工作负载同幅度改善（sum_256：582.65 µs；parens_32：127.35 µs）。
naive 路径同步受益（json flat 256：1.24 ms）。

> 注：改动前数字来自 2026-06-12 的 `latest-parser-combinator.md`（moon
> 0.1.20260608），量级对照仅供趋势参考；本轮全部 122+5 项包内测试与
> Property 9a/9b/9c 契约不变量在新表示下保持通过，守恒律改以「共享同一
> 源字符串 + 码元偏移界内」形式锁定。

## 原始输出（改动后）

见 `moon bench` 输出：json_flat_packrat_16 80.73 µs ± 2.65 µs；
json_flat_naive_16 82.98 µs；json_flat_packrat_256 1.23 ms；
arith_sum_packrat_256 582.65 µs；arith_parens_packrat_32 127.35 µs。
