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
