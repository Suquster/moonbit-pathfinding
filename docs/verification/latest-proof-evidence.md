# Proof Evidence

- Generated at: 2026-05-31T18:18:44.6587475+08:00
- Script: scripts\proof_evidence.ps1
- Package: src\proofs
- MoonBit: moon 0.1.20260427 (48d7def 2026-04-27)  Feature flags enabled: rr_moon_pkg
- Runtime predicate tests: ExitCode=0
- moon prove --help: ExitCode=0
- Why3 available: False
- moon prove status: blocked-missing-why3

## Interpretation

Runtime proof predicates passed, and moon prove exists, but static proof discharge is blocked on this machine because Why3 is missing from PATH.

## Bad-Witness Coverage

- bad witness: bfs_post rejects a non-minimal returned path
- bad witness: bfs_post rejects None when a goal is reachable
- bad witness: dijkstra_post rejects invalid edge transition
- bad witness: dijkstra_post rejects mismatched returned cost

Raw JSON: proof-evidence-20260531-181844.json and latest-proof-evidence.json.
