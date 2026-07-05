# Championship Backlog

> Search time: 2026-05-31 17:00:00 Asia/Shanghai
> Freshness: realtime-level official contest information, crawled from the 2026 MoonBit Software Synthesis Challenge page.
> Scope: `Suquster/moonbit-pathfinding`

This backlog keeps the project aligned with the official judging model and
turns every discovered gap into a verifiable task. It is intentionally stricter
than a normal TODO list: an item is complete only when code, docs, or CI evidence
exists in the repository.

## Official Scoring Frame

Official contest page: <https://www.moonbitlang.cn/2026-scc>

### Rolling Acceptance

| Dimension | Weight | What must be demonstrable in this repository |
|---|---:|---|
| Completion | 25% | Declared scope builds, runs, and reproduces through commands, examples, and tests. |
| Engineering quality | 25% | Clear module boundaries, maintainable code, tests for key and exceptional paths, consistent error handling. |
| Explainability | 25% | Development article, design rationale, AI-agent usage record, and comparison with adopted open-source references. |
| User experience | 25% | Low-friction install, examples, docs, playground or CLI flows, and AI-agent-friendly usage paths. |

### Final Defense

| Dimension | Weight | Championship interpretation |
|---|---:|---|
| Solves a real problem | 25% | Pathfinding and graph algorithms fill a MoonBit ecosystem gap with realistic use cases. |
| Complete user experience | 25% | README, executable docs, examples, package publishing, and preferably browser playground. |
| Uses MoonBit language strengths | 25% | Generic APIs, multi-backend support, executable Markdown tests, and `moon prove`-ready contracts. |
| Domain knowledge | 25% | Algorithms are grounded in papers, benchmarked, and explained with tradeoffs. |

## Current Baseline

- Package: `Suquster/moonbit-pathfinding` v0.0.1.
- Toolchain observed locally: `moon 0.1.20260427`.
- Baseline before first fix: `moon test` reported 147 passed, 0 failed.
- After first fix: `moon test` reported 150 passed, 0 failed.
- After warning-cleanup pass: fast acceptance reported 151 tests passed, 0
  failed; `moon check` emitted no warnings.
- CI exists with three-backend matrix, coverage, hard-gated docs audit, and release-branch proof evidence jobs.
- Local acceptance entrypoint exists at `scripts/acceptance.ps1`.
- Key risk: authenticated mooncakes publishing, a real browser playground, broader negative/edge regressions, and large real-road benchmark artifacts still need stronger evidence before they can be treated as completed deliverables.

## High-Impact Queue

### P0 - Truthfulness And Verification

- [x] Replace the BFS minimality proof predicate stub with an executable bounded shortest-path check.
  - Evidence: `src/proofs/bfs_proof.mbt`, `src/proofs/bfs_proof_test.mbt`.
  - Verification: `moon test` increased from 147 to 150 tests and passes.
- [x] Remove or harden README / presentation claims that overstated proof, playground, FFI, benchmarks, or advanced algorithms.
  - Evidence: `README.md`, `README.zh-CN.md`, `README.mbt.md`, `docs/presentation/*`, `docs/zh/algorithms/{ch,jps,alt}.md`.
  - Remaining markers are tracked below when they correspond to real future work or environment-gated proof evidence.
- [x] Remove or harden every remaining `stub`, `placeholder`, `TBD`, and `coming soon` claim that affects official scoring.
  - Acceptance: marker scan has no scoring-relevant false claims, or each remaining marker is explicitly scoped as future work.
  - Evidence: `CODE_OF_CONDUCT.md` contact placeholder removed; `lib.mbt` no longer calls itself a placeholder; public package metadata and presentation docs no longer claim unverified `moon prove`, realtime playground, Python FFI, or measured speedups.
- [x] Decide the root package strategy.
  - Current state: `lib.mbt` is intentionally empty and documented as the README doctest anchor.
  - Rationale: implementation packages remain under `src/`; the root package exists so `README.mbt.md` can run as black-box executable documentation without inventing a facade API before MoonBit packaging requirements are settled.
- [x] Convert `moon prove` from best-effort story to the strongest currently supported evidence.
  - Acceptance: runnable command, documented limitations, and at least one proof/predicate artifact that fails on a bad witness.
  - Evidence: `src/proofs/moon.pkg` enables proof mode; `scripts/proof_evidence.ps1` runs `moon test src/proofs`, checks `moon prove --help`, attempts `moon prove src\proofs`, and writes `docs/verification/latest-proof-evidence.{json,md}`. Bad-witness tests are named in `src/proofs/bfs_proof_test.mbt` and `src/proofs/dijkstra_proof_test.mbt`.
  - Verification: `pwsh -File scripts\proof_evidence.ps1` exited 0; runtime predicates reported 35 passed, 0 failed; `moon prove --help` exited 0; static discharge is recorded as `blocked-missing-why3` because Why3 is not on `PATH` on this machine.

### P1 - Official Completion

- [x] Reconcile README claims with implemented scope.
  - Acceptance: every advertised algorithm, backend, benchmark, and example has a command or file path proving it.
  - Evidence: package metadata, README performance section, playground section, and presentation assets now distinguish shipped evidence from planned artifacts; benchmark speed numbers were replaced with artifact requirements.
- [x] Add an official acceptance script.
  - Acceptance: one command runs check, fmt check, tests, README executable docs, docs audit, and coverage gate locally.
  - Evidence: `scripts/acceptance.ps1`.
- [x] Ensure examples are full workflows, not snippets.
  - Acceptance: maze solver, network routing, and eight puzzle each have documented input/output and are covered by tests.
  - Evidence: `examples/maze_solver`, `examples/network_routing`, and `examples/eight_puzzle` are documented runnable packages; `scripts/examples_guard.ps1` executes all three sequentially and checks scenario-specific output markers; `docs/examples/latest-examples-run.{json,md}` and timestamped `docs/examples/examples-run-*.json` artifacts store evidence.
  - Verification: `pwsh -File scripts\examples_guard.ps1` exited 0; maze solver checked 6 markers, network routing checked 5 markers, eight puzzle checked 6 markers.
- [x] Make the package publish-ready.
  - Acceptance: license, README, semver, changelog, package metadata, and mooncakes instructions are internally consistent.
  - Evidence: `moon.mod.json` now points mooncakes to `README.md`, includes repository/homepage/license/keywords/description metadata; `.github/workflows/release.yml` no longer masks publish failures and materializes mooncakes credentials from CI secrets; `scripts/release_guard.ps1` checks metadata, README/changelog/license consistency, workflow hard gates, `moon package`, and `moon publish --dry-run`; `docs/release/latest-release-readiness.{json,md}` stores evidence.
  - Verification: `pwsh -File scripts\release_guard.ps1` exited 0 with `pass-with-warnings`; `moon package` produced `_build\publish\Suquster-moonbit-pathfinding-0.0.1.zip`; `moon publish --dry-run` is blocked locally by missing mooncakes credentials and recorded as an environment warning rather than a false publish claim.

### P1 - Engineering Quality

- [x] Reduce toolchain warnings in core and advanced packages.
  - Acceptance: no deprecated `not(...)`, `.or(...)`, `.size()` usage in maintained source and test code; `moon check` emits no warnings.
  - Evidence: source/test migration to `!expr`, `unwrap_or`, `length`, test-scoped imports, explicit `@double` import, and narrower generic bounds.
  - Verification: `moon check` exited 0 with no warning output; `pwsh -File scripts\acceptance.ps1 -SkipCoverage` exited 0 with 151 tests passed, 5 README doctests passed, `moon doc` passed, and 63/63 public declarations documented.
- [x] Harden CI gates.
  - Acceptance: docs audit is a hard gate, and prove evidence is documented with its Why3/toolchain blocker and upgrade path.
  - Evidence: `.github/workflows/ci.yml` now runs `scripts/audit_doc.ps1` as a hard gate after `moon doc`; the release-branch proof job runs `scripts/proof_evidence.ps1`, records runtime predicate evidence, and preserves the Why3 environment blocker instead of pretending static proof succeeded.
  - Verification: local acceptance runs include `moon doc` plus `scripts/audit_doc.ps1`; the latest release/proof artifacts document the remaining environment-gated proof boundary.
- [x] Add regression tests for negative and edge cases across algorithms.
  - Acceptance: unreachable, invalid graph, zero-node, single-node, duplicate-edge, negative-weight, and disconnected cases are covered where relevant.
  - Evidence: `src/undirected/edge_cases_test.mbt` (Kruskal/Prim/CC/bridges/Hopcroft-Karp/Kuhn-Munkres: empty, single-node, duplicate parallel edges, disconnected forest, non-square matrix), `src/unweighted/edge_cases_test.mbt` (BFS tree: unreachable None, duplicate successors), `src/directed/edge_cases_more_test.mbt` (Yen InvalidK/unreachable, topo empty/single/self-loop cycle, Edmonds-Karp disconnected & source==sink), on top of existing `src/directed/edge_cases_test.mbt` and `src/advanced/edge_cases_test.mbt` (negative-cycle, unknown-node, JPS blocked/forced cases).
- [x] Establish benchmark smoke artifacts.
  - Acceptance: reproducible benchmark JSON or Markdown results with machine, target, input size, and comparison baseline.
  - Evidence: `scripts/benchmark_smoke.ps1`, `benches/results/README.md`, `benches/results/latest-smoke.{json,md}`, and timestamped `benches/results/smoke-wasm-gc-20260531-174841.json`.
  - Verification: `pwsh -File scripts\benchmark_smoke.ps1` exited 0; every benchmark package ran 1 warmup + 5 release iterations on `wasm-gc`.
- [x] Add a benchmark smoke regression guard.
  - Acceptance: a fresh smoke run is compared against checked-in baseline medians without overwriting the baseline, and the guard writes an auditable pass/fail report.
  - Evidence: `scripts/benchmark_guard.ps1`, `benches/results/latest-guard.{json,md}`, and timestamped `benches/results/guard-wasm-gc-20260531-175448.json`.
  - Verification: `pwsh -File scripts\acceptance.ps1 -SkipCoverage -RunBenchmarkGuard` exited 0; BFS, Dijkstra, A*, and Kruskal median deltas were all under the current 50% smoke threshold.
- [x] Upgrade benchmark evidence from smoke timing to lower-noise benchmark/regression gate.
  - Acceptance: native `moon bench` or equivalent harness records algorithm-level timing and compares against checked-in baselines with documented tolerance.
  - Evidence: four `benches/*_bench/*.mbt` packages now keep `moon test` smoke guards and add native `@bench.T` blocks; `scripts/benchmark_native.ps1`, `scripts/benchmark_native_guard.ps1`, `benches/results/latest-native.{json,md}`, `benches/results/latest-native-guard.{json,md}`, and timestamped native artifacts.
  - Verification: `moon bench -p ... --target wasm-gc --release --no-parallelize` reported 4 native benchmarks passed; `pwsh -File scripts\benchmark_native.ps1` generated a native baseline; `pwsh -File scripts\benchmark_native_guard.ps1` exited 0 with all four algorithms under the 25% regression threshold.

### P1 - User Experience

- [x] Turn the playground from TBD into a usable demo or remove the badge until it exists.
  - Acceptance: web demo builds locally and is linked from README, or README no longer implies a ready playground.
  - Evidence: README / README.zh-CN badge and section say `planned`; presentation and offline demo scripts no longer require a browser playground or 60fps claim as current evidence.
- [x] Create an AI-agent usage guide.
  - Acceptance: a concise guide shows install, package imports, common calls, and known pitfalls for code agents.
  - Evidence: `docs/AI_AGENT_USAGE.md`, linked from both README files.
- [ ] Polish bilingual docs.
  - Acceptance: English and Chinese README files agree on status, scope, and commands.

### P2 - Championship Differentiators

- [ ] Deepen the advanced algorithm trio: CH, JPS, ALT.
  - Acceptance: each has implementation, tests, docs, and benchmark story; claims avoid "skeleton" ambiguity.
- [x] Add paper-to-code traceability.
  - Acceptance: each advanced algorithm doc links assumptions and departures from the source paper to code sections and tests.
  - Evidence: `docs/verification/paper-to-code-advanced.md` — CH (Geisberger 2008) / JPS (Harabor & Grastien 2011) / ALT (Goldberg & Harrelson 2005), paper construct → code lines → tests, plus documented departures (witness budget, no stall-on-demand, uniform-cost JPS).
- [ ] Prepare defense assets.
  - Acceptance: slides, script, Q&A, and offline demo all reflect the current repository instead of future plans.

## Next Attack Order

1. Add negative and edge-case regression tests across algorithms.
2. Polish bilingual docs and defense assets from verified artifacts only.
3. Deepen CH / JPS / ALT paper-to-code traceability and benchmark narratives.
4. Add large real-road / OSM benchmark artifacts before making speedup claims.
5. Decide whether the playground becomes a real local demo or remains outside score-facing claims.
