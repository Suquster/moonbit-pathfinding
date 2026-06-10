# AI Agent Usage Guide

> Scope: concise integration notes for code agents, reviewers, and scripted examples.
> This file describes the current repository layout and avoids future-only APIs.

## Verified Entry Points

Use package-level imports instead of the root package. The root package is kept
empty so `README.mbt.md` can run as executable documentation.

| Task | Package | Common alias |
|------|---------|--------------|
| BFS on unweighted graphs | `Suquster/moonbit-pathfinding/src/unweighted` | `@uw` |
| Dijkstra, A*, Bellman-Ford, DFS, SCC, flow | `Suquster/moonbit-pathfinding/src/directed` | `@dir` |
| Kruskal, connected components, matching | `Suquster/moonbit-pathfinding/src/undirected` | `@und` |
| CH, JPS, ALT | `Suquster/moonbit-pathfinding/src/advanced` | `@adv` |
| Runtime proof predicates | `Suquster/moonbit-pathfinding/src/proofs` | `@proofs` |

## Import Template

In a MoonBit package inside this workspace, declare imports in `moon.pkg`:

```moonbit
import {
  "Suquster/moonbit-pathfinding/src/unweighted" @uw,
  "Suquster/moonbit-pathfinding/src/directed" @dir,
  "Suquster/moonbit-pathfinding/src/undirected" @und,
  "Suquster/moonbit-pathfinding/src/proofs" @proofs,
}
```

Then call algorithms through the alias:

```moonbit
let path = @uw.bfs(0, fn(n) { adj[n] }, fn(n) { n == 3 })
let result = @dir.dijkstra(0, fn(n) { weighted_adj[n] }, fn(n) { n == 3 })
```

## Successor Function Pattern

Most algorithms take graph access as a function. Do not build a wrapper graph
type unless your application already has one.

```moonbit
let adj : Array[Array[(Int, Int)]] = [
  [(1, 1), (2, 4)],
  [(2, 2), (3, 5)],
  [(3, 1)],
  [],
]

let successors = fn(n : Int) -> Array[(Int, Int)] { adj[n] }
let is_goal = fn(n : Int) -> Bool { n == 3 }
let answer = @dir.dijkstra(0, successors, is_goal)
```

## Return Value Pattern

Shortest-path functions use option-style results. Always handle `None`.

```moonbit
match answer {
  Some((path, cost)) => {
    println("cost = \{cost}")
    println("path = \{path}")
  }
  None => println("unreachable")
}
```

## Common Pitfalls

| Pitfall | Safer pattern |
|---------|---------------|
| Passing negative weights into Dijkstra or A* | Use Bellman-Ford or prove weights are non-negative first |
| Treating `None` as an error | Treat it as a normal unreachable result |
| Claiming CH/JPS/ALT speedups without artifacts | Run benchmarks and record `benches/results/*.json` first |
| Calling root package APIs | Import the concrete `src/*` package instead |
| Calling `moon prove` a hard gate | Run `scripts/proof_evidence.ps1`; report runtime predicates plus any Why3/toolchain blocker |
| Hard-coding benchmark numbers in docs | Include MoonBit version, backend, machine, seed, and raw timings |

## Local Verification

Fast inner-loop check:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\acceptance.ps1 -SkipCoverage
```

Full local gate:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\acceptance.ps1
```

Focused example workflows:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\examples_guard.ps1
```

Focused executable docs:

```powershell
moon test README.mbt.md
```

Focused proof predicates:

```powershell
moon test src/proofs
```

Proof evidence artifact:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\proof_evidence.ps1
```

Release readiness:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\release_guard.ps1
```

Native benchmark regression guard:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\benchmark_native_guard.ps1
```

## What To Cite In Generated Explanations

- `README.mbt.md` and `docs/examples/latest-examples-run.md` for executable user-facing examples.
- `docs/CHAMPIONSHIP_BACKLOG.md` for current competition status and known gaps.
- `docs/release/latest-release-readiness.md` for package metadata and mooncakes publish-readiness evidence.
- `benches/results/latest-native-guard.md` for native benchmark regression evidence.
- `src/proofs/bfs_proof.mbt`, `src/proofs/bfs_proof_test.mbt`, and `docs/verification/latest-proof-evidence.md` for proof-predicate and `moon prove` environment evidence.
- `scripts/acceptance.ps1` for the local acceptance gate.
- `docs/zh/algorithms/` for Chinese algorithm explanations.
