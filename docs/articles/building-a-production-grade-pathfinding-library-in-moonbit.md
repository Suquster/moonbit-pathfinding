# Building a Production-Grade Pathfinding Library in MoonBit

> Draft for the MoonBit community forum (discuss.moonbitlang.com).
> Everything below is reproducible from the public repository:
> <https://github.com/Suquster/moonbit-pathfinding> (mirrored at
> <https://www.gitlink.org.cn/Taoyouce/moonbit-pathfinding>), package
> `Suquster/moonbit-pathfinding` on mooncakes.io.

MoonBit is quickly becoming a language you can do serious engineering in —
but a young ecosystem is missing basic infrastructure. This post walks
through how I built **moonbit-pathfinding**, a graph-algorithm and
pathfinding library (BFS/DFS/Dijkstra/A\*/JPS up through ALT, Contraction
Hierarchies, CCH and Hub Labels), and the engineering practices that made
it hold up: successor-function APIs, four-backend testing, differential
and property-based testing, honest benchmarking against Rust, and an
end-to-end real-OSM in-browser demo.

## 1. API design: successor functions over graph types

The single most important design decision was to make the core search
functions **generic over a successor function** instead of a concrete
graph type:

```moonbit
pub fn[N : Eq + Hash, W : @core.Weight + Compare] astar(
  start : N,
  successors : (N) -> Array[(N, W)],
  heuristic : (N) -> W,
  is_goal : (N) -> Bool,
) -> (Array[N], W)?
```

Users never have to adapt their data to a `Graph` type. A warehouse grid,
a game map, a parsed OSM network, or an implicit state space (e.g. puzzle
states) all plug in with a closure. A downstream consumer looks like
this — a maze solver from
[moonbit-maze](https://github.com/Suquster/moonbit-maze):

```moonbit
@directed.astar(
  start,
  fn(cell) { maze.successors(cell) },       // open corridors, unit cost
  fn(cell) { manhattan(cell, goal) },       // admissible on a unit grid
  fn(cell) { cell == goal },
)
```

Two things to note:

- `N : Eq + Hash` means node types are **user-defined** — tuples, structs,
  whatever — with no numbering step required.
- `W : @core.Weight + Compare` abstracts the cost semiring, so `Int`,
  `Int64` and `Double` weights all work, and A\*'s admissibility contract
  (`heuristic(n) <= true_cost(n)`) is documented and test-enforced.

For hot paths there is a parallel **indexed CSR layer**
(`dijkstra_indexed`, `astar_indexed`, `dijkstra_bidirectional_ctx`, …)
that trades ergonomics for zero-allocation adjacency scans. The generic
layer is for correctness and reach; the indexed layer is what the
benchmarks and the OSM engine run on.

## 2. Testing: four backends, differential oracles, properties

MoonBit compiles to wasm-gc, js, native and wasm. All 3300+ tests run on
**all four backends** in CI — this caught real numeric and ordering
discrepancies early. Beyond example-based tests, two techniques carried
most of the weight:

**Differential testing.** Every fast algorithm is cross-checked against a
slow oracle on randomized inputs. Bidirectional Dijkstra against
unidirectional; CH/ALT/Hub-Labels query results against plain Dijkstra;
A\* against Dijkstra whenever the heuristic is admissible:

```moonbit
test "osm bidirectional agrees with unidirectional on random graphs" {
  // 128-node strongly-connected random graphs, 50 queries each:
  // cost(bidir) must equal cost(uni) for every query.
}
```

**Property-based testing.** Instead of asserting specific outputs, assert
invariants: returned paths start at the source, end at the goal, only use
existing edges, and their summed edge weights equal the reported cost.
These properties hold for *every* algorithm, so they are written once and
instantiated per algorithm.

A practical MoonBit tip: `moon test --target js,native,wasm,wasm-gc`
in a CI matrix plus `moon check --deny-warn` keeps the library
warning-free on every backend simultaneously.

## 3. Honest benchmarking against Rust

We benchmark against the Rust `pathfinding` crate with **identical
workloads** (shared xorshift generator, sizes up to 100k nodes / 1.6M
edges) and element-wise identical result signatures. Two rules keep the
numbers honest:

1. **Same-algorithm comparisons only**: MoonBit unidirectional
   BFS/Dijkstra/A\* vs. Rust unidirectional equivalents — 18/18 cases,
   median speedup ≈2.7× (range 2.1–3.6×) on the native backend.
2. **Capability bonuses reported separately**: our bidirectional variants
   are 8–68× faster than our own unidirectional baselines, but Rust's
   crate has no equivalent API, so this is *never* blended into the
   cross-language number.

The full methodology, seeds and per-case results live in a checked-in
JSON artifact (`benches/results/latest-rust-comparison.json`).

## 4. Real data end to end: OSM in the browser

The same library compiles to a **22 KB wasm-gc module** that powers an
in-browser playground (<https://Suquster.github.io/moonbit-pathfinding/>).
The newest mode loads the real Xiamen driving network — 125,639 nodes and
215,947 edges extracted from OpenStreetMap (© contributors, ODbL 1.0) —
and lets you click two points to race unidirectional vs. bidirectional
Dijkstra, comparing settled-node counts and timings live, with costs
cross-checked on every query:
<https://Suquster.github.io/moonbit-pathfinding/osm.html>

The wasm export layer is deliberately boring: a flat integer-handle
protocol (`pg_osm_reset` / `pg_osm_add_edge` / `pg_osm_route` /
`pg_osm_path_at` …) that needs no JS glue for data marshalling — and the
same protocol is lifted to a typed **WIT component-model world** and
invoked function-by-function under wasmtime in CI.

## 5. Consuming the package

```bash
moon add Suquster/moonbit-pathfinding
```

then import `"Suquster/moonbit-pathfinding/src/directed"` in your
`moon.pkg`. Two independent example consumers with their own CI:

- [moonbit-pathfinding-demo](https://github.com/Suquster/moonbit-pathfinding-demo)
  — a warehouse robot route planner;
- [moonbit-maze](https://github.com/Suquster/moonbit-maze) — a
  perfect-maze generator + A\* solver CLI.

The repository also treats its INFRA directions as first-class citizens,
not side quests: all 20 directions ship runnable end-to-end workflows under
`examples/` — from `actor_worker_pool`, `build_pipeline`,
`serialization_studio`, `dst_explorer` and `config_diff_ops` to
`hash_integrity`, `compress_workbench`, `time_scheduler`,
`resilience_gateway`, `cli_devtool`, `observability_kit`,
`text_editor_core`, `parser_playground` and `pbt_fuzz_lab` — backed by the
same test/bench/acceptance gates as the pathfinding core, with per-direction
tutorials in `docs/tutorials/README.md`.

## Takeaways for MoonBit library authors

1. Design generic APIs around closures and trait bounds — MoonBit's
   generics make successor-function APIs cheap and ergonomic.
2. Run tests on all four backends from day one; discrepancies are much
   cheaper to fix early.
3. Pair every optimized algorithm with a differential oracle; property
   tests scale better than example tests.
4. Report benchmarks with same-algorithm discipline; keep capability
   advantages in a separate, clearly-labeled lane.
5. wasm-gc + a flat integer export protocol is a surprisingly pleasant
   way to ship interactive demos of real libraries.

Questions and PRs welcome — the repository is Apache-2.0.
