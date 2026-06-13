# Parser_Combinator Benchmark Results (packrat vs naive)

- Generated at: `2026-06-12T10:55:24Z`
- Packages: `benches/parser_json_bench`, `benches/parser_arith_bench`
- MoonBit: `moon 0.1.20260608 (60bc8c3 2026-06-08)`
- Target: `native`
- Machine: `Linux 6.1.172 x86_64`, `8` logical processors
- Run command (native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`):
  - `moon bench -p benches/parser_json_bench --target native`
  - `moon bench -p benches/parser_arith_bench --target native`

> Scope: native `moon bench` statistics from `@bench.T` blocks. Each workload is
> measured twice — once with packrat memoization (`run_packrat`) and once with
> the naive reference (`run_naive`) — over geometrically increasing input sizes.
> This is algorithm-level regression evidence and a packrat-vs-naive complexity
> trend comparison (R12.3), not a cross-language speedup claim.

## JSON parser (`benches/parser_json_bench`)

| Workload | Size | run_packrat (mean) | run_naive (mean) |
|---|---:|---:|---:|
| flat array `[0,…,n-1]` | 16 | 100.78 µs | 100.28 µs |
| flat array | 64 | 383.60 µs | 384.77 µs |
| flat array | 256 | 1.52 ms | 1.53 ms |
| nested array `[[…]]` | 8 | 55.46 µs | 55.54 µs |
| nested array | 16 | 106.02 µs | 105.64 µs |
| nested array | 32 | 208.58 µs | 206.62 µs |

## Arithmetic evaluator (`benches/parser_arith_bench`)

| Workload | Size | run_packrat (mean) | run_naive (mean) |
|---|---:|---:|---:|
| sum chain `1+1+…+1` | 16 | 47.49 µs | 47.62 µs |
| sum chain | 64 | 186.59 µs | 185.28 µs |
| sum chain | 256 | 729.84 µs | 729.62 µs |
| nested parens `((…1…))` | 8 | 40.81 µs | 40.48 µs |
| nested parens | 16 | 76.56 µs | 76.56 µs |
| nested parens | 32 | 149.36 µs | 149.17 µs |

## Interpretation

Both example grammars are predominantly **predictive (single-token-lookahead)
PEG** grammars: each alternative is disambiguated by the leading character, so
there is little exponential backtracking for packrat to amortize away. Hence
packrat and naive track each other closely here, and both scale **linearly** in
input size (doubling the size roughly doubles the time). The packrat machinery
adds only a small constant-factor caching overhead while guaranteeing the linear
worst-case bound that protects against pathological backtracking grammars. The
benchmark exists to (a) guard against regressions in either run mode across
backends and (b) provide reproducible evidence of the linear trend.
