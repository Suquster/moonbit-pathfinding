# Hands-on Tutorials — every direction, by example

Each section below is a five-minute tutorial for one direction of the
library: the key public APIs, a minimal snippet you can paste into a
`is-main` package, and the runnable demo that exercises the full workflow.
All snippets are drawn from the demos under `examples/`, so they compile
and run as shown. Run any demo with:

```bash
moon run examples/<name>
```

The pathfinding core is covered by the executable docs in
[`docs/zh/algorithms/`](../zh/algorithms/README.md); this handbook focuses on
the INFRA directions that ship alongside it.

## 1. Pathfinding (BFS / Dijkstra / A*)

Demos: `examples/maze_solver`, `examples/network_routing`,
`examples/eight_puzzle`.

```moonbit
let result = @pathfinding.dijkstra(
  start,
  fn(n) { neighbors_of(n) }, // (N) -> Array[(N, W)]
  fn(n) { n == goal },
)
```

Nodes can be any `Eq + Hash` type, weights any `Weight + Compare` type.
See the per-algorithm executable docs for BFS/A*/JPS/CH/ALT and more.

## 2. Mini compiler (`src/mini_compiler`)

Demo: `examples/mini_compiler_pipeline` — lexer → parser → HM type
inference → optimizer → bytecode VM with tail-call optimization,
interpreter differential testing, and JS emission from one source program.

## 3. Regex engine (`src/regex_engine`)

Demo: `examples/regex_toolkit` — named captures, `replace_all` redaction,
`split`, and linear-time matching (ReDoS-resistant NFA simulation).

## 4. Structured logging (`src/logging`)

Demo: `examples/log_pipeline` — trace spans with W3C `traceparent`
propagation, JSON/logfmt/pretty renderers, PII redaction, env-filter.

## 5. Actors (`src/actor`)

Demo: `examples/actor_worker_pool`.

```moonbit
let sys = @actor.ActorSystem::new()
// supervised pool: faults trigger restart per SupervisorSpec
// routing: round-robin / random / consistent-hash
// bounded mailboxes give natural backpressure
```

## 6. Build tool (`src/build_tool`)

Demo: `examples/build_pipeline` — rule parsing, parallel wave scheduling,
minimal incremental rebuilds (dirty closure), cached execution, auto-bisect
for first-bad-commit search.

## 7. Serialization (`src/serialization`)

Demo: `examples/serialization_studio` — `.proto` parse/validate, typed
wire + JSON round-trips, canonical bytes, breaking-change detection.

## 8. Deterministic simulation testing (`src/dst`)

Demo: `examples/dst_explorer` — seeded deterministic replays,
partition/crash fault injection, DPOR exploration, shrinking,
linearizability checking.

## 9. Config + diff (`src/infra_config`, `src/infra_diff`)

Demo: `examples/config_diff_ops` — TOML/INI parsing, unified diffs, patch
apply/revert, diff3 three-way merge with conflict detection, SemVer gates.

## 10. Hashing (`src/infra_hash`)

Demo: `examples/hash_integrity`.

```moonbit
@hash.sha256_hex(artifact)                    // matches sha256sum
let tag = @hash.hmac_sha256(key, message)     // authentication tag
let okm = @hash.hkdf(ikm, salt, info, 32)     // key derivation
let dk = @hash.pbkdf2_hmac_sha256(pw, salt, 1000, 32)
let h = @hash.Sha256Hasher::new()             // streaming == one-shot
h.update(chunk1); h.update(chunk2); h.finalize()
let shard = (@hash.xxhash64(bytes, 42) % 3UL).to_int()
```

Rule of thumb (see `benches/results/infra-hash-compress-native-2026-07-12.md`):
xxHash64 is ~7.5× faster than SHA-256 at 16 KiB — use non-crypto hashes for
sharding, crypto digests for integrity.

## 11. Compression (`src/infra_compress`)

Demo: `examples/compress_workbench`.

```moonbit
let c = @compress.deflate(data)               // smallest here (46‰)
@compress.inflate(c) == Some(data)            // lossless
let zs = @compress.zstd_compress_entropy(data, true)
let zd = @compress.zlib_compress_with_dict(small, dict) // shared dict wins on tiny payloads
@compress.gzip_decompress(corrupted) is None  // CRC rejects tampering
```

LZ4 is ~7× faster round-trip than DEFLATE at 36 KB; zstd's entropy path
scales best as payloads grow.

## 12. Time + timers (`src/infra_time`, `src/infra_timer`)

Demo: `examples/time_scheduler`.

```moonbit
let dt = @time.parse_iso8601("2026-07-12T18:30:00.250Z").unwrap()
@time.format_rfc2822(dt, 0)
let rule = @time.parse_posix_tz("EST5EDT,M3.2.0/2,M11.1.0/2").unwrap()
let (offset, name) = @time.tz_offset_at(rule, dt) // seconds, "EDT"
let d = @time.parse_duration("2h30m").unwrap()    // Go-style durations
let wheel = @timer.TimerWheel::new()               // hierarchical wheel
let ws = @timer.WorkStealingScheduler::new(4)      // real steal counts
```

## 13. Resilience (`src/infra_resilience`)

Demo: `examples/resilience_gateway`.

```moonbit
let (ok, attempts) = @res.retry_run(policy, fn(i) { call(i) })
let cb = @res.CircuitBreaker::create(3, 1000)  // Closed→Open→HalfOpen→Closed
let tb = @res.TokenBucket::create(3, 1)
let bh = @res.Bulkhead::create(2, 1)           // slots + queue
let aimd = @res.AimdLimiter::create(10, 1, 100) // initial, min, max
let fire = @res.hedge_schedule(policy)          // hedged requests
```

## 14. CLI (`src/infra_cli`)

Demo: `examples/cli_devtool` — subcommands, typed validation with choices,
`suggest_option` typo hints, bundled short flags, `help_text`, and
`completion_bash` generation.

## 15. Metrics (`src/infra_metrics`)

Demo: `examples/observability_kit`.

```moonbit
let h = @metrics.HdrHistogram::new(3)
h.record(latency_ms)
h.value_at_percentile(99.9)
let s1 = @metrics.DDSketch::new(0.01)  // mergeable across shards
s1.merge_with(s2)
let tracer = @metrics.SpanTracer::new() // total vs self time per span
```

## 16. Text + data structures (`src/infra_text`, `src/infra_ds`)

Demo: `examples/text_editor_core`.

```moonbit
let rope = @text.Rope::from_string(src)
rope.delete(12, 16)        // half-open [lo, hi)
rope.insert(12, "println(\"hi\")")
rope.line_col_at(offset)
@text.grapheme_count("héllo 世界") // 8; display_width counts CJK as 2
let ops = @text.myers_diff(before, after)
let lru = @ds.LruCache::create(2)
let bloom = @ds.BloomFilter::create(1024, 3)
let bitmap = @ds.RoaringBitmap::new()
```

Note `PieceTable::delete(off, count)` takes a count while
`Rope::delete(lo, hi)` takes a half-open range.

## 17. Parser combinators (`src/parser_combinator`)

Demo: `examples/parser_playground`.

```moonbit
@pc.parse_and_eval("2 ^ 3 ^ 2") // 512 — right-assoc power, correct precedence
let json = @pc.parse_json(src)  // errors carry rendered caret positions
let (value, errors) = @pc.parse_json_recover(bad) // recovery diagnostics
let g = @pc.lift(parser)
let step = g.run_incremental(chunk1)  // NeedMore, not a false failure
let result = @pc.drive(step, [chunk2, chunk3], closed=true)
```

## 18. PBT + fuzzing (`src/infra_pbt`, `src/infra_fuzz`)

Demo: `examples/pbt_fuzz_lab`.

```moonbit
@pbt.holds_for_all(@pbt.gen_int_range(0, 1000), fn(n) { n + n == 2 * n })
let r = @pbt.check_with_shrink(gen, prop, @pbt.shrink_int) // minimal counterexample
@pbt.round_trip(gen, encode, decode)  // encode/decode law
let g = @fuzz.fuzz_graph_gen(5, 42)   // seeded, reproducible graphs
@fuzz.shrink_fuzz_graph(failing)      // structurally smaller candidates
```

## Benchmarks and evidence

- Algorithm + INFRA native benchmarks live under `benches/`; results under
  [`benches/results/`](../../benches/results/).
- Example outputs are guarded by `scripts/examples_guard.ps1`; latest
  evidence in [`docs/examples/latest-examples-run.md`](../examples/latest-examples-run.md).
- Full acceptance gate: `bash scripts/acceptance.sh`.
