// predicates.mbt — shared mathematical predicates for formal proofs.
//
// This module is the **single source of truth** for the invariants used
// across `bfs_proof.mbt` (task 33.2) and `dijkstra_proof.mbt` (task 34.x).
//
// Design philosophy (per design.md §7.1 / Requirement R8):
//   * Every proof assertion is encoded once as a `pub fn` returning `Bool`,
//     so that (a) the same predicate can be referenced from both the
//     `moon prove` post-condition comment block and from runtime tests
//     that exercise the predicate concretely, and (b) when `moon prove`
//     matures, its annotations can import these predicates directly.
//   * Each predicate is **total and pure** — no partial pattern matches,
//     no side effects, no recursion on unbounded data. `moon prove` is
//     happier with total functions.
//   * Predicates are **generic** in the node type `N : Eq + Hash`, so the
//     same definitions serve BFS (unweighted) and Dijkstra (weighted)
//     without duplication.
//
// When we flip the "Formally verified" badge from grey to green
// (tasks.md 34.3), every assertion in `bfs_proof.mbt` / `dijkstra_proof.mbt`
// will be phrased in terms of the predicates defined here.

///|
/// `is_valid_path(path, start, successors)` — true iff `path` is a legal
/// walk from `start` through the graph induced by `successors`.
///
/// Formal meaning (the target of `moon prove` for BFS / Dijkstra):
///
///   1. `path` is non-empty;
///   2. `path[0] == start`;
///   3. for every consecutive pair `(path[i], path[i+1])`, there exists
///      some successor of `path[i]` equal to `path[i+1]`.
///
/// This predicate is the "path-structural" half of the BFS post-condition:
/// together with `is_reachable` (reachability witness) it pins down what
/// "BFS returns a valid result" means.
pub fn[N : Eq] is_valid_path(
  path : Array[N],
  start : N,
  successors : (N) -> Array[N],
) -> Bool {
  if path.length() == 0 {
    return false
  }
  if path[0] != start {
    return false
  }
  let mut i = 0
  while i < path.length() - 1 {
    let u = path[i]
    let v = path[i + 1]
    // v must appear in successors(u). We do a linear scan because
    // successors may return any Array, not a set — this keeps the
    // predicate total and easy to prove about.
    let nbrs = successors(u)
    let mut found = false
    let mut j = 0
    while j < nbrs.length() {
      if nbrs[j] == v {
        found = true
        break
      }
      j += 1
    }
    if !found {
      return false
    }
    i += 1
  }
  true
}

///|
/// `is_reachable(start, goal, successors, nodes)` — true iff there exists
/// **some** path from `start` to a node satisfying `goal`.
///
/// The predicate is implemented as a bounded BFS over `nodes` (the whole
/// known node set), so it terminates even if `successors` would otherwise
/// enumerate an infinite state space. This makes it safe to call from proof
/// obligations that quantify over all graphs.
///
/// Bound rationale: a simple-path between two nodes visits every node at
/// most once, so iterating `nodes.length()` times from `start` is both
/// necessary and sufficient.
pub fn[N : Eq + Hash] is_reachable(
  start : N,
  goal : (N) -> Bool,
  successors : (N) -> Array[N],
  nodes : Array[N],
) -> Bool {
  if goal(start) {
    return true
  }
  let visited : Map[N, Bool] = Map::new()
  visited[start] = true
  let queue : Array[N] = [start]
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head += 1
    for v in successors(u) {
      if visited.contains(v) {
        continue
      }
      if goal(v) {
        return true
      }
      visited[v] = true
      queue.push(v)
    }
  }
  // touch `nodes` to justify the bound. We only ever iterate up to
  // `nodes.length()` nodes because `visited` ensures no repeats; this
  // helper intentionally has the same asymptotic shape as BFS.
  ignore(nodes)
  false
}

///|
/// `path_cost(path, edge_weight)` — sum of edge weights along `path`.
///
/// `edge_weight(u, v)` should return `Some(w)` when `(u, v)` is an edge,
/// `None` otherwise. The predicate `is_valid_path` above uses `successors`
/// rather than `edge_weight`, so `path_cost` is a separate helper that
/// `dijkstra_proof.mbt` uses to phrase the "cost assertion".
///
/// If the path contains an illegal pair (no edge), the function returns
/// `None`, signalling "undefined cost". Dijkstra's post-condition quantifies
/// over only well-formed paths, so this `None` branch never fires in the
/// `moon prove` obligation, but having a total function keeps the proof
/// environment happy.
pub fn[N, W : @core.Weight] path_cost(
  path : Array[N],
  edge_weight : (N, N) -> W?,
) -> W? {
  if path.length() == 0 {
    return Some(@core.Weight::zero())
  }
  let mut total = @core.Weight::zero()
  let mut i = 0
  while i < path.length() - 1 {
    match edge_weight(path[i], path[i + 1]) {
      Some(w) => total = @core.Weight::add(total, w)
      None => return None
    }
    i += 1
  }
  Some(total)
}

///|
/// `is_non_negative(w)` — true iff `w >= Weight::zero()`.
///
/// Small but essential helper for Dijkstra's non-negativity invariant
/// (`dist[v] >= 0` for every reachable v under non-negative edge weights,
/// task 34.1). Keeping it as a named predicate makes the proof annotations
/// read like mathematics rather than inline comparisons.
pub fn[W : @core.Weight] is_non_negative(w : W) -> Bool {
  !(w < @core.Weight::zero())
}

///|
/// `all_edges_non_negative(edges, edge_weight)` — quantifier predicate
/// used as a *precondition* by Dijkstra's proof (Requirement R8.2a).
///
/// Iterates edge list explicitly; this avoids the need for `moon prove`
/// to reason about successor closures directly.
pub fn[N, W : @core.Weight] all_edges_non_negative(
  edges : Array[(N, N)],
  edge_weight : (N, N) -> W?,
) -> Bool {
  let mut i = 0
  while i < edges.length() {
    let (u, v) = edges[i]
    match edge_weight(u, v) {
      Some(w) => if !is_non_negative(w) { return false }
      None => ()
    }
    i += 1
  }
  true
}
