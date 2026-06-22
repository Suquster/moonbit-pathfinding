// bfs_proof.mbt — formal-verification scaffolding for `@uw.bfs`.
//
// This file encodes the post-conditions (Requirement R8.1, task 33.2) that
// `moon prove` will discharge once the tool-chain exposes
// `#requires` / `#ensures` / `#decreases` annotations as first-class
// syntax. Until then, the assertions are validated by **runtime property
// tests** that invoke the same predicates from `predicates.mbt`, so the
// contract is already enforced in CI; only the _proof mechanism_ is
// pending.
//
// Correspondence to design.md §7.2:
//   * POST-1 (path starts at `start`)       — `check_starts_at_start`
//   * POST-2 (path ends at a goal node)     — `check_ends_at_goal`
//   * POST-3 (every consecutive pair is an edge, a.k.a. path validity)
//                                           — `check_edges_valid`
//   * POST-4 (path is the shortest possible) — `check_minimality`
//   * NON-EXISTENCE (None iff goal unreachable) — `check_none_witness`
//
// Each POST-K predicate is a `Bool`-returning pure function, so BFS's
// future `#ensures` annotation can reference it verbatim.

///|
/// POST-1 · Path starts at `start`.
///
/// Trivial pointwise check, but isolated so that `moon prove` sees it as
/// a **named** post-condition — we want the proof tree to carry the same
/// vocabulary as the English comment in `bfs.mbt`. A `None` result is
/// treated as vacuously true (no path ⇒ nothing to check); a `Some(path)`
/// must be non-empty and have `path[0] == start`. Pure and total.
pub fn[N : Eq] check_starts_at_start(result : Array[N]?, start : N) -> Bool {
  match result {
    Some(path) => path.length() > 0 && path[0] == start
    None => true // vacuous: no path ⇒ nothing to check.
  }
}

///|
/// POST-2 · Path ends at a node satisfying `goal`.
///
/// The `goal` argument is a predicate `(N) -> Bool` so the check supports
/// both single-target and multi-target queries. A `None` result is
/// vacuously true; a `Some(path)` must be non-empty and have its last
/// element satisfy `goal`. Pure and total; mirrors the future `#ensures`
/// vocabulary referenced from `bfs.mbt`.
pub fn[N] check_ends_at_goal(result : Array[N]?, goal : (N) -> Bool) -> Bool {
  match result {
    Some(path) => path.length() > 0 && goal(path[path.length() - 1])
    None => true
  }
}

///|
/// POST-3 · Every consecutive pair in the path is an edge.
///
/// Wires through `is_valid_path` from `predicates.mbt`, the shared
/// structural predicate. When `moon prove` matures, this same predicate
/// is what the `#ensures` annotation will reference. A `None` result is
/// vacuously true. Pure and total.
pub fn[N : Eq] check_edges_valid(
  result : Array[N]?,
  start : N,
  successors : (N) -> Array[N],
) -> Bool {
  match result {
    Some(path) => is_valid_path(path, start, successors)
    None => true
  }
}

///|
/// POST-4 · Minimality (shortest path).
///
/// The full minimality statement reads
///
///   `forall p' valid path from start to goal, |path| <= |p'|`
///
/// This runtime predicate checks the same obligation with a bounded BFS:
/// for a returned path of length `k`, it searches only depths `< k`.
/// Finding any goal node at a smaller depth disproves minimality. That
/// keeps the contract executable in CI while the future `moon prove`
/// annotation can still reference this named predicate.
pub fn[N : Eq + Hash] check_minimality(
  result : Array[N]?,
  start : N,
  successors : (N) -> Array[N],
  goal : (N) -> Bool,
) -> Bool {
  match result {
    None => true
    Some(path) => {
      if path.length() == 0 {
        return false
      }
      if !is_valid_path(path, start, successors) {
        return false
      }
      if !goal(path[path.length() - 1]) {
        return false
      }
      let target_edges = path.length() - 1
      if target_edges == 0 {
        return goal(start)
      }
      if goal(start) {
        return false
      }

      let visited : Map[N, Bool] = Map([])
      let queue : Array[(N, Int)] = [(start, 0)]
      visited[start] = true
      let mut head = 0
      while head < queue.length() {
        let (cur, depth) = queue[head]
        head += 1
        if depth + 1 >= target_edges {
          continue
        }
        for next in successors(cur) {
          if visited.contains(next) {
            continue
          }
          let next_depth = depth + 1
          if goal(next) {
            return false
          }
          visited[next] = true
          queue.push((next, next_depth))
        }
      }
      true
    }
  }
}

///|
/// NON-EXISTENCE witness · `bfs == None` iff goal is truly unreachable.
///
/// Uses `is_reachable` (the bounded BFS oracle in `predicates.mbt`) to
/// cross-check that every `None` returned by `bfs` corresponds to an
/// actually unreachable goal. If BFS claims "unreachable" while the oracle
/// disagrees, the contract is violated — this is an independent safety
/// net even before `moon prove` can discharge the full proof.
pub fn[N : Eq + Hash] check_none_witness(
  result : Array[N]?,
  start : N,
  successors : (N) -> Array[N],
  goal : (N) -> Bool,
  nodes : Array[N],
) -> Bool {
  match result {
    Some(_) => true // proved reachable by giving an explicit witness.
    None => !is_reachable(start, goal, successors, nodes)
  }
}

///|
/// Aggregate post-condition: all POST-K conjoined.
///
/// The `moon prove` annotation on `bfs` will read:
///
/// ```moonbit skip
/// #ensures(bfs_post(result, start, successors, goal, nodes))
/// pub fn[N : Eq + Hash] bfs(...) { ... }
/// ```
///
/// Until then, callers who want runtime enforcement can wrap the call:
///
/// ```moonbit skip
/// let r = @uw.bfs(start, succ, goal)
/// assert_true(@proofs.bfs_post(r, start, succ, goal, nodes))
/// ```
pub fn[N : Eq + Hash] bfs_post(
  result : Array[N]?,
  start : N,
  successors : (N) -> Array[N],
  goal : (N) -> Bool,
  nodes : Array[N],
) -> Bool {
  check_starts_at_start(result, start) &&
  check_ends_at_goal(result, goal) &&
  check_edges_valid(result, start, successors) &&
  check_minimality(result, start, successors, goal) &&
  check_none_witness(result, start, successors, goal, nodes)
}
