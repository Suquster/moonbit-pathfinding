# Benchmark Results

This directory stores reproducible benchmark evidence for
`Suquster/moonbit-pathfinding`.

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
