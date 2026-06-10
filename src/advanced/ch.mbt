// Contraction Hierarchies (CH) — hierarchical shortest-path acceleration.
//
// Reference: Geisberger, R., Sanders, P., Schultes, D., & Delling, D. (2008).
// "Contraction Hierarchies: Faster and Simpler Hierarchical Routing in Road
// Networks." WEA 2008, LNCS 5038, pp. 319-333.
//
// v1.0.0 scope (tasks.md 35.x + R18.1(a)):
//   * `CHGraph[N, W]` — preprocessed data structure holding node ordering,
//     upward / downward edges, and shortcut witnesses.
//   * `ch_preprocess(nodes, successors)` — naive-but-correct witness-search
//     implementation: contract nodes in input order, add shortcuts
//     whenever the "witness Dijkstra" fails to find a faster bypass.
//   * `ch_query(graph, source, target)` — bidirectional Dijkstra restricted
//     to upward edges on each side.
//
// The CH speedup (literature: 100x-1000x on road networks) depends heavily
// on the contraction-order heuristic. The v1.0.0 release ships a linear
// input-order contractor plus the correct query machinery; order tuning
// (edge-difference ranking, lazy updates) is queued for v1.1.x.

///|
/// CH preprocessed graph.
///
/// Fields:
///   * `nodes`  — exact node list, used for output iteration and witness
///                searches.
///   * `level`  — `level[n]` is the rank at which `n` was contracted
///                (smaller = contracted earlier = "lower" in the hierarchy).
///   * `up_adj` — upward edges: `(v, w)` means an edge from key-node to v
///                where `level[v] > level[key]`. Used by the forward
///                Dijkstra at query time.
///   * `dn_adj` — downward edges: `(u, w)` means an edge **into** key-node
///                from u where `level[u] > level[key]`. Used by the
///                backward Dijkstra. (We store the *incoming* edge at
///                the lower end because bidirectional Dijkstra walks
///                from both endpoints upward.)
///   * `shortcut` — map `(u, v) -> middle_node` recording the witness
///                middle for each shortcut, used to expand paths into
///                the underlying original graph.
pub struct CHGraph[N, W] {
  nodes : Array[N]
  level : Map[N, Int]
  up_adj : Map[N, Array[(N, W)]]
  dn_adj : Map[N, Array[(N, W)]]
  shortcut : Map[(N, N), N]
}

///|
/// Witness-search budget. A bigger number means fewer false-positive
/// shortcuts (slightly better query time) at the cost of preprocessing
/// time. For v1.0.0 we use a small fixed budget; road-network tuning
/// lands in v1.1.x.
const CH_WITNESS_HOPS : Int = 5

///|
/// Helper: witness Dijkstra from `src` to `dst` on the **uncontracted**
/// subgraph, i.e. ignoring every node currently in `contracted`. Returns
/// `Some(cost)` when a path of at most `CH_WITNESS_HOPS` edges exists.
/// This runs per shortcut-candidate during preprocessing, which keeps
/// witness search total cost bounded.
fn[N : Eq + Hash, W : @core.Weight + Compare] ch_witness(
  src : N,
  dst : N,
  via : N,
  bound : W,
  successors : (N) -> Array[(N, W)],
  contracted : Map[N, Bool],
) -> W? {
  let dist : Map[N, W] = Map([])
  let pq : @core.PQueue[N, W] = @core.PQueue::new()
  let zero = @core.Weight::zero()
  dist[src] = zero
  pq.push(zero, src)
  let mut hops = 0
  while !pq.is_empty() && hops < CH_WITNESS_HOPS {
    let (d, u) = pq.pop().unwrap()
    hops += 1
    if u == dst {
      return Some(d)
    }
    match dist.get(u) {
      Some(cur) => if d > cur { continue }
      None => continue
    }
    for pair in successors(u) {
      let (v, w) = pair
      if v == via {
        continue // must avoid the contracted node itself
      }
      if contracted.get(v).unwrap_or(false) {
        continue
      }
      let new_d = @core.Weight::add(d, w)
      if new_d > bound {
        continue
      }
      let improve = match dist.get(v) {
        Some(cur) => new_d < cur
        None => true
      }
      if improve {
        dist[v] = new_d
        pq.push(new_d, v)
      }
    }
  }
  None
}

///|
/// CH preprocessing: contract nodes in their input order, emitting a
/// shortcut `u -> v` whenever the witness search does NOT find a
/// `u ~> v` path of equal-or-smaller cost avoiding the contracted node.
///
/// Returns a fully populated `CHGraph` ready for `ch_query`.
pub fn[N : Eq + Hash, W : @core.Weight + Compare] ch_preprocess(
  nodes : Array[N],
  successors : (N) -> Array[(N, W)],
) -> CHGraph[N, W] {
  let level : Map[N, Int] = Map([])
  let up_adj : Map[N, Array[(N, W)]] = Map([])
  let dn_adj : Map[N, Array[(N, W)]] = Map([])
  let shortcut : Map[(N, N), N] = Map([])
  // Start with everything unordered; we assign levels 0..n-1 in input order
  // and contract them one by one.
  for i in 0..<nodes.length() {
    level[nodes[i]] = i
  }
  // Residual successor view: starts as the original graph, grows with
  // each added shortcut.
  let residual : Map[N, Array[(N, W)]] = Map([])
  for n in nodes {
    residual[n] = successors(n)
  }
  let contracted : Map[N, Bool] = Map([])
  for i in 0..<nodes.length() {
    let v = nodes[i]
    // Enumerate (u -> v -> w) pairs on the residual graph.
    let incoming : Array[(N, W)] = []
    for u in nodes {
      if contracted.get(u).unwrap_or(false) {
        continue
      }
      if u == v {
        continue
      }
      match residual.get(u) {
        Some(out_edges) =>
          for e in out_edges {
            if e.0 == v {
              incoming.push((u, e.1))
            }
          }
        None => ()
      }
    }
    let outgoing = residual.get(v).unwrap_or([])
    for in_pair in incoming {
      let (u, w_uv) = in_pair
      for out_pair in outgoing {
        let (x, w_vx) = out_pair
        if contracted.get(x).unwrap_or(false) {
          continue
        }
        if u == x {
          continue
        }
        let via_cost = @core.Weight::add(w_uv, w_vx)
        // Witness search on residual graph, avoiding v itself.
        let witness = ch_witness(
          u,
          x,
          v,
          via_cost,
          fn(n) { residual.get(n).unwrap_or([]) },
          contracted,
        )
        let need_shortcut = match witness {
          Some(wc) => via_cost < wc
          None => true
        }
        if need_shortcut {
          // Append the synthetic edge u -> x with weight via_cost to
          // residual, and record the middle node for later expansion.
          let u_list = residual.get(u).unwrap_or([])
          u_list.push((x, via_cost))
          residual[u] = u_list
          shortcut[(u, x)] = v
        }
      }
    }
    contracted[v] = true
  }
  // Build upward / downward adjacency from the final residual graph.
  for u in nodes {
    let level_u = level.get(u).unwrap()
    let out_edges = residual.get(u).unwrap_or([])
    for e in out_edges {
      let (v, w) = e
      let level_v = level.get(v).unwrap()
      if level_v > level_u {
        let lst = up_adj.get(u).unwrap_or([])
        lst.push((v, w))
        up_adj[u] = lst
      } else {
        let lst = dn_adj.get(v).unwrap_or([])
        lst.push((u, w))
        dn_adj[v] = lst
      }
    }
  }
  { nodes, level, up_adj, dn_adj, shortcut }
}

///|
/// Helper: expand a possibly-shortcut edge into the underlying original
/// path. If `(u, v)` is a shortcut with middle node `m`, recursively
/// expand `(u, m)` then `(m, v)`. If `(u, v)` is an original edge, return
/// just `[u, v]`. The final path of `ch_query` is built by concatenating
/// these expansions pairwise and deduplicating the seam nodes.
fn[N : Eq + Hash, W] expand_edge(
  graph : CHGraph[N, W],
  u : N,
  v : N,
) -> Array[N] {
  match graph.shortcut.get((u, v)) {
    Some(mid) => {
      let left = expand_edge(graph, u, mid)
      let right = expand_edge(graph, mid, v)
      let out : Array[N] = []
      for x in left {
        out.push(x)
      }
      // Skip `right[0] == mid`, the seam, to avoid duplication.
      let mut i = 1
      while i < right.length() {
        out.push(right[i])
        i += 1
      }
      out
    }
    None => [u, v]
  }
}

///|
/// Reconstruct the ancestor chain in an "upward" search tree.
///
/// Walks `parents` backward from `node` to `root` (or until the chain
/// breaks), producing `[root, ..., node]` in forward order.
fn[N : Eq + Hash] reverse_chain(
  parents : Map[N, N],
  root : N,
  node : N,
) -> Array[N] {
  let rev : Array[N] = [node]
  let mut cur = node
  while cur != root {
    match parents.get(cur) {
      Some(p) => {
        cur = p
        rev.push(cur)
      }
      None => break
    }
  }
  rev.rev_in_place()
  rev
}

///|
/// Expand a CH-level chain into the original-graph path by repeatedly
/// expanding each consecutive pair and concatenating (seam-deduped).
fn[N : Eq + Hash, W] expand_chain(
  graph : CHGraph[N, W],
  chain : Array[N],
) -> Array[N] {
  if chain.length() == 0 {
    return []
  }
  let out : Array[N] = [chain[0]]
  let mut i = 0
  while i < chain.length() - 1 {
    let segment = expand_edge(graph, chain[i], chain[i + 1])
    let mut j = 1 // skip seam (== chain[i])
    while j < segment.length() {
      out.push(segment[j])
      j += 1
    }
    i += 1
  }
  out
}

///|
/// Upward Dijkstra on the CH up-hierarchy. Returns distance + parent maps
/// so `ch_query` can reconstruct CH-level paths before expanding them.
fn[N : Eq + Hash, W : @core.Weight + Compare] ch_up_dijkstra(
  graph : CHGraph[N, W],
  source : N,
  use_up : Bool,
) -> (Map[N, W], Map[N, N]) {
  let dist : Map[N, W] = Map([])
  let parents : Map[N, N] = Map([])
  let pq : @core.PQueue[N, W] = @core.PQueue::new()
  let zero = @core.Weight::zero()
  dist[source] = zero
  pq.push(zero, source)
  while !pq.is_empty() {
    let (d, u) = pq.pop().unwrap()
    match dist.get(u) {
      Some(cur) => if d > cur { continue }
      None => continue
    }
    let edges = if use_up {
      graph.up_adj.get(u).unwrap_or([])
    } else {
      graph.dn_adj.get(u).unwrap_or([])
    }
    for pair in edges {
      let (v, w) = pair
      let new_d = @core.Weight::add(d, w)
      let improve = match dist.get(v) {
        Some(cur) => new_d < cur
        None => true
      }
      if improve {
        dist[v] = new_d
        parents[v] = u
        pq.push(new_d, v)
      }
    }
  }
  (dist, parents)
}

///|
/// CH point-to-point query with **full path expansion**.
///
/// Steps:
///   1. Run two upward Dijkstras (source-upward, target-upward-via-down-edges).
///   2. Find the meeting node `m` that minimises `fwd_dist[m] + bwd_dist[m]`.
///   3. Reconstruct the forward half `source → m` via `fwd_parents`, and the
///      backward half `target → m` via `bwd_parents` (reversed to `m → target`).
///   4. Concatenate the two halves into a CH-level chain, then call
///      `expand_chain` to unfold every shortcut back to original-graph nodes.
///
/// Returns `(path, cost)` where `path` lists every **original** node from
/// `source` to `target` in order, matching the Dijkstra-equivalent output.
pub fn[N : Eq + Hash, W : @core.Weight + Compare] ch_query(
  graph : CHGraph[N, W],
  source : N,
  target : N,
) -> (Array[N], W)? {
  if source == target {
    return Some(([source], @core.Weight::zero()))
  }
  let (fwd_dist, fwd_parents) = ch_up_dijkstra(graph, source, true)
  let (bwd_dist, bwd_parents) = ch_up_dijkstra(graph, target, false)
  // Merge settled nodes and find the minimum-sum meeting point.
  let mut best : W? = None
  let mut meet : N? = None
  for entry in fwd_dist {
    let (u, d1) = entry
    match bwd_dist.get(u) {
      Some(d2) => {
        let total = @core.Weight::add(d1, d2)
        let better = match best {
          None => true
          Some(b) => total < b
        }
        if better {
          best = Some(total)
          meet = Some(u)
        }
      }
      None => ()
    }
  }
  match (meet, best) {
    (Some(m), Some(cost)) => {
      // Forward half: source -> ... -> m
      let fwd_chain = reverse_chain(fwd_parents, source, m)
      // Backward half: target -> ... -> m, reversed (minus the m seam)
      let bwd_chain_to_m = reverse_chain(bwd_parents, target, m)
      let ch_chain : Array[N] = []
      for x in fwd_chain {
        ch_chain.push(x)
      }
      let mut i = bwd_chain_to_m.length() - 2
      while i >= 0 {
        ch_chain.push(bwd_chain_to_m[i])
        i -= 1
      }
      let full_path = expand_chain(graph, ch_chain)
      Some((full_path, cost))
    }
    _ => None
  }
}
