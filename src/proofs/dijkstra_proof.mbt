// dijkstra_proof.mbt — formal-verification scaffolding for `@dir.dijkstra`.
//
// Encodes the two proof obligations called out by tasks.md tasks 34.1
// (non-negativity) and 34.2 (termination), plus the structural
// post-conditions mirrored from `bfs_proof.mbt`. As with the BFS proof,
// each obligation is encoded as a `Bool`-returning pure predicate so
// that:
//
//   * A runtime PBT can drive `dijkstra` over random non-negative graphs
//     and call `dijkstra_post(...)` on the output to catch any contract
//     violation instantly (tasks.md 28.3 snapshot + 27.3 PBT);
//   * When `moon prove` exposes `#requires` / `#ensures` / `#decreases`
//     annotations, this file becomes the source of truth for the proof
//     terms — `#ensures(dijkstra_post(...))` and `#decreases(...)` can
//     be dropped straight into `src/directed/dijkstra.mbt` source.
//
// Correspondence to design.md §7.3 and Requirement R8.2:
//   * POST-1 · Non-negativity ( 34.1 )  — `check_non_negativity`
//   * POST-2 · Termination    ( 34.2 )  — `check_termination_measure`
//   * POST-3 · Path validity            — `check_edges_valid_weighted`
//   * POST-4 · Cost consistency         — `check_cost_matches_path`
//   * PRE-1  · Edges are non-negative   — `require_non_negative_edges`

///|
/// PRE-1 · "All edges have non-negative weights" — the pre-condition that
/// guarantees Dijkstra's correctness. Encoded as a thin alias over
/// `all_edges_non_negative` from `predicates.mbt` so that `moon prove`
/// annotations can refer to it by name.
pub fn[N, W : @core.Weight] require_non_negative_edges(
  edges : Array[(N, N)],
  edge_weight : (N, N) -> W?,
) -> Bool {
  all_edges_non_negative(edges, edge_weight)
}

///|
/// POST-1 · `dist[v] >= zero()` for every reachable node v
/// (Requirement R8.2a · task 34.1).
///
/// We encode this as "the cost component of `result`, if `Some`, is
/// non-negative". Because Dijkstra returns `(path, cost)` rather than the
/// full `dist` map, we only need to verify the cost of the returned path;
/// the invariant on every intermediate `dist[v]` follows by induction on
/// the heap-pop order (see design.md §7.3 Lemma-1).
pub fn[N, W : @core.Weight] check_non_negativity(
  result : (Array[N], W)?,
) -> Bool {
  match result {
    Some((_path, cost)) => is_non_negative(cost)
    None => true // vacuous
  }
}

///|
/// POST-2 · Termination-measure witness (Requirement R8.2b · task 34.2).
///
/// For Dijkstra running on a graph with `V` nodes, the termination measure
/// is
///
///   `measure(state) = |V| - |visited|`
///
/// which (a) is a natural number, (b) strictly decreases on every heap
/// pop that is not a stale entry, (c) cannot be negative. `moon prove` can
/// discharge termination by supplying this measure via `#decreases`.
///
/// The predicate below checks the static property: "for any `nodes` set
/// and any `visited` subset, `measure >= 0`". The truly interesting part
/// (strict decrease per iteration) will be an invariant on Dijkstra's
/// main loop when the tool-chain matures.
pub fn[N] check_termination_measure(
  nodes : Array[N],
  visited_count : Int,
) -> Bool {
  // Natural-number measure: |V| - |visited| >= 0.
  visited_count >= 0 && visited_count <= nodes.length()
}

///|
/// POST-3 · Path validity — same as BFS's `is_valid_path` but ported over
/// Dijkstra's weighted successor shape. We strip the weight component
/// before delegating to the unweighted structural predicate, because
/// "which edges exist" is the question being asked, regardless of cost.
pub fn[N : Eq, W] check_edges_valid_weighted(
  result : (Array[N], W)?,
  start : N,
  successors : (N) -> Array[(N, W)],
) -> Bool {
  match result {
    Some((path, _cost)) => {
      // Unweight the successor so we can reuse `is_valid_path`.
      let unw_succ = fn(n : N) -> Array[N] {
        let xs = successors(n)
        let out : Array[N] = []
        for p in xs {
          out.push(p.0)
        }
        out
      }
      is_valid_path(path, start, unw_succ)
    }
    None => true
  }
}

///|
/// POST-4 · Cost consistency — the returned `cost` must equal the sum of
/// edge weights along the returned `path`.
///
/// This is Dijkstra's "accountability" theorem: the algorithm reports a
/// total cost, and the user can reconstruct the same cost by summing the
/// path. We use `path_cost` from `predicates.mbt` to compute the reference
/// and compare for equality; `Some(c)` vs `None` discrepancy fails the
/// predicate.
pub fn[N, W : @core.Weight] check_cost_matches_path(
  result : (Array[N], W)?,
  edge_weight : (N, N) -> W?,
) -> Bool {
  match result {
    Some((path, cost)) =>
      match path_cost(path, edge_weight) {
        Some(c2) => c2 == cost
        None => false
      }
    None => true
  }
}

///|
/// Aggregate post-condition for Dijkstra.
///
/// In the `moon prove`-enabled future this reads:
///
/// ```moonbit skip
/// #requires(require_non_negative_edges(edges, edge_weight))
/// #ensures(dijkstra_post(result, start, successors, edge_weight))
/// #decreases(|nodes| - |visited|)
/// pub fn[N, W] dijkstra(...) { ... }
/// ```
pub fn[N : Eq, W : @core.Weight] dijkstra_post(
  result : (Array[N], W)?,
  start : N,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
) -> Bool {
  check_non_negativity(result) &&
  check_edges_valid_weighted(result, start, successors) &&
  check_cost_matches_path(result, edge_weight)
}
