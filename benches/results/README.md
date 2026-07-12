# Benchmark Results

This directory stores reproducible benchmark evidence for
`Suquster/moonbit-pathfinding`.

## SOTA evidence index (2026-07-05, 复测 2026-07-12)

| direction | artifact | headline |
| --- | --- | --- |
| OSM 端到端 showcase · 路径级 | `osm-showcase-path-native-2026-07-12.md` | 厦门 32 随机查询：CH 展开路径逐边存在于原图、权重求和=代价=Dijkstra 三方一致，最长样例 183 跳 41.8 km |
| OSM 加速结构全家福 · 复测 | `osm-suite-native-2026-07-12.md` | 北京 HL 查询 0.64 µs（vs 双向 Dijkstra 11242×）、CH 99.7×、CCH 换权 13.2× 快于重建、many-to-many bucket 16×、RPHAST 10×；合成 250k CH 184×；全部代价对拍一致 |
| CH · 真实 OSM 路网 | `osm-real-networks-ch-native-2026-07-05.md` | 北京 104×、厦门 45×（≥100× PASS，48 组代价逐位一致）；预处理 9.4s→6.6s（活跃前缀分区） |
| CH · 250k 合成路网 | `ch-csr-large-scale-native-2026-07-05.md` | 中位加速 160.8×；预处理 28s→20s（排序权重 2·ED-deg+2·DN + 活跃前缀分区） |
| Codegen · 真实语料 | `codegen-real-corpus-native-2026-07-05.md` | 11 内核削减 40.1%（137→82，含 PRE 菱形上提 + 外部输入复制传播），全路径语义对拍一致 |
| Codegen · 合成程序族 | `codegen-opt-reduction-2026-07-05.md` | 削减 86.8%，双路径语义对拍一致 |
| Actor · 10k 吞吐 | `actor-ten-k-throughput-2026-07-05.md` | 11.35M msgs/sec（100k 消息，恰好一次处理守卫） |
| Actor · 监督风暴 | `actor-supervision-storm-native-2026-07-05.md` | 685k events/sec，17087 次重启全部恢复 Running |
| Actor · 有界邮箱 | `actor-bounded-mailbox-scaling-native-2026-07-05.md` | 出队摊销 O(1)（8× 规模差下每消息耗时比率 0.95） |

Current artifacts have two layers:

1. Native `moon bench` evidence from `@bench.T` blocks for algorithm-level
   timing.
2. End-to-end smoke timing for package-level regression checks.

Generate the native benchmark baseline with:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_native.ps1
```

Compare a fresh native run against the checked-in baseline with:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_native_guard.ps1
```

The native guard writes its fresh run under `_build/native-benchmark-guard/`,
compares median `moon bench` mean timings against `latest-native.json`, and
stores `latest-native-guard.{json,md}` here. The default tolerance is 25%.

Generate the package-level smoke timing artifacts with:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_smoke.ps1
```

The script records MoonBit version, target backend, release/debug mode,
machine metadata, git state, exact commands, raw command output, and per-run
elapsed milliseconds.

To compare a fresh smoke run against the checked-in baseline without
overwriting that baseline, run:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_guard.ps1
```

The guard writes its fresh run under `_build/benchmark-guard/`, compares median
timings against `latest-smoke.json`, and stores `latest-guard.{json,md}` here.
The default tolerance is deliberately loose (50%) because this is end-to-end
`moon test -p ...` timing, not isolated algorithm microbenchmark timing.

Important scope note: native artifacts are local algorithm-level regression
evidence, while smoke artifacts are end-to-end `moon test -p ...` package
timings. Neither artifact is a cross-language speedup claim.

## LSP_Suite benchmarks (`benches/lsp_bench`)

The LSP direction (`lsp_binding` + `lsp_server`) contributes five native
`moon bench` workloads, each registered over increasing input sizes with
benchmark rows named `<workload>_<size>`:

1. `decode_encode_<N>` — `encode_message` / `decode_message` round-trip over a
   JSON-RPC request whose params hold `N` object entries (N = 8 / 64 / 512).
2. `dispatch_<N>` — `dispatch` routing of `N` requests across an 8-handler
   `Router` (N = 16 / 128 / 1024).
3. `analyze_<N>` — `analyze` over a DSL document with `N` reference lines
   (N = 16 / 64 / 256).
4. `apply_changes_<N>` — `apply_changes` applying `N` equal-length incremental
   `ContentChange`s under UTF-16 encoding (N = 16 / 64 / 256).
5. `references_<N>` / `rename_<N>` — `references` / `rename` over a document with
   a single key referenced `N` times (N = 16 / 64 / 256).

Native benchmarks require `LIBRARY_PATH` to be exported first:

```bash
export LIBRARY_PATH=/usr/lib64:/usr/lib
moon bench benches/lsp_bench --target native
```

Smoke guards (one per workload plus an encode/decode round-trip) run on every
backend:

```bash
moon test benches/lsp_bench --target wasm-gc
moon test benches/lsp_bench --target js
moon test benches/lsp_bench --target native   # requires LIBRARY_PATH export first
```

`benches/lsp_bench` is registered in both `scripts/benchmark_native.ps1` (native
`moon bench` artifacts + baseline-median guard via
`scripts/benchmark_native_guard.ps1`, default tolerance 25%) and
`scripts/benchmark_smoke.ps1` (package-level smoke timing), so its artifacts,
baseline comparison and over-tolerance failure report are produced by the same
scripts as the other directions.
