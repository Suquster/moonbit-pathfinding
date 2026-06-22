// Contraction Hierarchies (CH) — hierarchical shortest-path acceleration.
//
// Reference: Geisberger, R., Sanders, P., Schultes, D., & Delling, D. (2008).
// "Contraction Hierarchies: Faster and Simpler Hierarchical Routing in Road
// Networks." WEA 2008, LNCS 5038, pp. 319-333.
//
// Scope (tasks.md 35.x + R18.1(a)):
//   * `CHGraph[N, W]` — preprocessed data structure holding node ordering,
//     upward / downward edges, and shortcut witnesses.
//   * `ch_preprocess(nodes, successors)` — witness-search implementation
//     with **edge-difference contraction ordering** (lazy re-evaluation):
//     at every step the node with the smallest `shortcuts_needed -
//     incident_edges` estimate is contracted next, which is the standard
//     heuristic from the CH paper. Shortcuts are added whenever the
//     "witness Dijkstra" fails to find a faster bypass.
//   * `ch_query(graph, source, target)` — bidirectional Dijkstra restricted
//     to upward edges on each side.
//
// A reverse-residual adjacency map is maintained incrementally so finding
// the incoming edges of a contraction candidate is O(deg) instead of an
// O(V) scan over all nodes.

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
/// Helper: build the initial residual successor view plus its reverse
/// mirror from the original graph. The residual grows with each added
/// shortcut during contraction; `rev_residual` enables O(deg) incoming-edge
/// lookups. Shared by `ch_preprocess` and `ch_preprocess_with_order`.
fn[N : Eq + Hash, W] ch_init_residual(
  nodes : Array[N],
  successors : (N) -> Array[(N, W)],
) -> (Map[N, Array[(N, W)]], Map[N, Array[(N, W)]]) {
  let residual : Map[N, Array[(N, W)]] = Map([])
  let rev_residual : Map[N, Array[(N, W)]] = Map([])
  for n in nodes {
    residual[n] = successors(n)
  }
  for n in nodes {
    for e in residual.get(n).unwrap_or([]) {
      let (v, w) = e
      let lst = rev_residual.get(v).unwrap_or([])
      lst.push((n, w))
      rev_residual[v] = lst
    }
  }
  (residual, rev_residual)
}

///|
/// Helper: contract a single node `v` on the residual graph. Enumerates
/// every `(u -> v -> x)` pair over uncontracted neighbours; when the
/// witness Dijkstra finds no equal-or-cheaper bypass, a shortcut
/// `u -> x` (weight `w_uv + w_vx`, middle `v`) is appended to the residual
/// graph and recorded in `shortcut`. Finally marks `v` contracted.
///
/// Shared by both the edge-difference ordering (`ch_preprocess`) and the
/// caller-supplied ordering (`ch_preprocess_with_order`) so the two entry
/// points stay behaviourally identical per contraction step.
fn[N : Eq + Hash, W : @core.Weight + Compare] ch_contract_node(
  v : N,
  residual : Map[N, Array[(N, W)]],
  rev_residual : Map[N, Array[(N, W)]],
  contracted : Map[N, Bool],
  shortcut : Map[(N, N), N],
) -> Unit {
  // Enumerate (u -> v -> x) pairs on the residual graph via the reverse
  // adjacency (deduplicating by taking each uncontracted in-neighbour).
  let incoming : Array[(N, W)] = []
  for e in rev_residual.get(v).unwrap_or([]) {
    let (u, w) = e
    if contracted.get(u).unwrap_or(false) || u == v {
      continue
    }
    incoming.push((u, w))
  }
  let outgoing = residual.get(v).unwrap_or([])
  for in_pair in incoming {
    let (u, w_uv) = in_pair
    for out_pair in outgoing {
      let (x, w_vx) = out_pair
      if contracted.get(x).unwrap_or(false) {
        continue
      }
      // Skip the contracted node's own self-loop (`x == v`): a `v -> v`
      // edge is never part of a shortest simple path through `v`, and
      // admitting it would mint a degenerate shortcut whose middle equals
      // an endpoint (`shortcut[(u, v)] = v`). Such a record both violates
      // the contraction hierarchy invariant and can OVERWRITE a legitimate
      // shortcut for the same key — which previously caused `ch_query` to
      // emit an unexpanded `[u, v]` path on graphs containing self-loops.
      if x == v {
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
        // residual (and its mirror in rev_residual), and record the
        // middle node for later expansion.
        let u_list = residual.get(u).unwrap_or([])
        u_list.push((x, via_cost))
        residual[u] = u_list
        let x_list = rev_residual.get(x).unwrap_or([])
        x_list.push((u, via_cost))
        rev_residual[x] = x_list
        shortcut[(u, x)] = v
      }
    }
  }
  contracted[v] = true
}

///|
/// Helper: split the final residual edges into upward / downward adjacency
/// using the assigned contraction `level`s. An edge `u -> v` is *upward*
/// when `level[v] > level[u]` (used by the forward query Dijkstra), and is
/// otherwise stored as a *downward* edge **into** `v` (used by the backward
/// Dijkstra). Shared by both CH preprocessing entry points.
fn[N : Eq + Hash, W] ch_build_adjacency(
  nodes : Array[N],
  level : Map[N, Int],
  residual : Map[N, Array[(N, W)]],
) -> (Map[N, Array[(N, W)]], Map[N, Array[(N, W)]]) {
  let up_adj : Map[N, Array[(N, W)]] = Map([])
  let dn_adj : Map[N, Array[(N, W)]] = Map([])
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
  (up_adj, dn_adj)
}

///|
/// CH preprocessing: contract nodes in edge-difference order (lazy
/// re-evaluation), emitting a shortcut `u -> v` whenever the witness
/// search does NOT find a `u ~> v` path of equal-or-smaller cost avoiding
/// the contracted node.
///
/// Returns a fully populated `CHGraph` ready for `ch_query`.
///
/// ## ASCII 示意（3×3 网格底图，预处理输入）
/// 预处理按边差（edge-difference）顺序逐个收缩底图的全部节点，并在 witness
/// 搜索找不到更优旁路时补充捷径。下图以一个 3×3 网格底图为例（`S`/`G` 仅
/// 标示后续查询的两端，预处理本身遍历全部节点、不产出单条路径）：
///
///     S..
///     .#.
///     ..G
///
/// 图例：S=起点 G=终点 #=障碍 .=空闲（预处理阶段不产生路径字符 `*`）
pub fn[N : Eq + Hash, W : @core.Weight + Compare] ch_preprocess(
  nodes : Array[N],
  successors : (N) -> Array[(N, W)],
) -> CHGraph[N, W] {
  let level : Map[N, Int] = Map([])
  let shortcut : Map[(N, N), N] = Map([])
  let (residual, rev_residual) = ch_init_residual(nodes, successors)
  let contracted : Map[N, Bool] = Map([])
  // Edge-difference estimate for contraction ordering: the number of
  // potential shortcuts (in-degree x out-degree among uncontracted
  // neighbours) minus the number of incident residual edges. Smaller
  // values contract first; estimates are re-evaluated lazily on pop.
  fn edge_difference(v : N) -> Int {
    let mut in_deg = 0
    for e in rev_residual.get(v).unwrap_or([]) {
      if !contracted.get(e.0).unwrap_or(false) && e.0 != v {
        in_deg += 1
      }
    }
    let mut out_deg = 0
    for e in residual.get(v).unwrap_or([]) {
      if !contracted.get(e.0).unwrap_or(false) && e.0 != v {
        out_deg += 1
      }
    }
    in_deg * out_deg - (in_deg + out_deg)
  }

  let order : @core.PQueue[N, Int] = @core.PQueue::new()
  for n in nodes {
    order.push(edge_difference(n), n)
  }
  let mut next_level = 0
  while !order.is_empty() {
    let (prio, v) = order.pop().unwrap()
    if contracted.get(v).unwrap_or(false) {
      continue
    }
    // Lazy re-evaluation: contracting earlier nodes may have changed this
    // node's edge difference; if it grew, push it back and pick again.
    let fresh = edge_difference(v)
    if fresh > prio && !order.is_empty() {
      order.push(fresh, v)
      continue
    }
    level[v] = next_level
    next_level += 1
    ch_contract_node(v, residual, rev_residual, contracted, shortcut)
  }
  // Build upward / downward adjacency from the final residual graph.
  let (up_adj, dn_adj) = ch_build_adjacency(nodes, level, residual)
  { nodes, level, up_adj, dn_adj, shortcut }
}

///|
/// Helper: decide whether `(a, b)` should be treated as a *shortcut* and,
/// if so, return its recorded middle node `m`.
///
/// **Hierarchy guard (R8.1 production-grade robustness).** A genuine CH
/// shortcut `(a, b)` is emitted while contracting its middle node `m`, so
/// the contraction invariant guarantees `level[m] < level[a]` **and**
/// `level[m] < level[b]` (the middle was contracted strictly earlier than
/// both endpoints). We re-verify that invariant here before recursing:
///
///   * If the recorded `m` violates it (anomalous / overwritten shortcut
///     reference, or a self/parallel-edge artefact such as `m == a` or
///     `m == b`), we **refuse** to treat `(a, b)` as a shortcut and fall
///     back to the direct edge. This is the safe degradation demanded by
///     R8.1: never crash, never loop — return a well-formed edge instead.
///   * The guard is also what makes expansion provably terminating: every
///     decomposition `(a, b) -> (a, m) + (m, b)` strictly *decreases*
///     `level[·] + level[·]` for both children (because `level[m]` is
///     below both endpoints), and the sum is a non-negative integer, so
///     the explicit-stack loop below cannot diverge.
fn[N : Eq + Hash, W] ch_shortcut_mid(graph : CHGraph[N, W], a : N, b : N) -> N? {
  match graph.shortcut.get((a, b)) {
    Some(mid) => {
      // A shortcut whose middle coincides with an endpoint is degenerate
      // (would recurse on the same pair) — reject it.
      if mid == a || mid == b {
        return None
      }
      match (graph.level.get(mid), graph.level.get(a), graph.level.get(b)) {
        (Some(lm), Some(la), Some(lb)) =>
          // Contraction invariant: middle ranks below both endpoints.
          if lm < la && lm < lb {
            Some(mid)
          } else {
            None
          }
        // Missing level information ⇒ cannot certify the invariant ⇒
        // degrade safely to the direct edge rather than risk a cycle.
        _ => None
      }
    }
    None => None
  }
}

///|
/// Helper: expand a possibly-shortcut edge into the underlying original
/// path. If `(u, v)` is a shortcut with middle node `m`, the edge unfolds
/// into `(u, m)` followed by `(m, v)`; original (non-shortcut) edges
/// contribute themselves. The final path of `ch_query` is built by
/// concatenating these expansions pairwise and deduplicating the seam
/// nodes.
///
/// **Iterative, stack-safe (R8.1).** Earlier this routine recursed on
/// `(u, m)` / `(m, v)`, so an anomalous shortcut reference (e.g. a
/// shortcut cycle produced by overwritten middles on graphs with parallel
/// edges / self-loops) could blow the native call stack
/// (`Maximum call stack size exceeded`). We now drive the expansion with
/// an **explicit stack** of pending `(a, b)` pairs and the
/// `ch_shortcut_mid` hierarchy guard, which together guarantee the walk
/// terminates for *any* preprocessed graph and always yields a valid
/// edge-by-edge node sequence `[u, …, v]`.
fn[N : Eq + Hash, W] expand_edge(
  graph : CHGraph[N, W],
  u : N,
  v : N,
) -> Array[N] {
  // Output begins with the start node; every resolved *direct* edge `(a,b)`
  // appends its target `b`, yielding `[u, …, v]` in forward order.
  let out : Array[N] = [u]
  // Pending pairs to resolve. We push children so that the *left* child is
  // popped first (LIFO): for a shortcut `(a,b)->m` we push `(m,b)` then
  // `(a,m)`, so `(a,m)` is processed before `(m,b)` — preserving order.
  let stack : Array[(N, N)] = [(u, v)]
  while stack.length() > 0 {
    let (a, b) = stack.pop().unwrap()
    match ch_shortcut_mid(graph, a, b) {
      Some(mid) => {
        stack.push((mid, b))
        stack.push((a, mid))
      }
      None => out.push(b)
    }
  }
  out
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
///
/// ## ASCII 示意（4×4 网格底图，分层查询结果）
/// CH 先将图预处理为带捷径的层级结构，查询时在两端各做一次「向上」
/// Dijkstra，得到与朴素 Dijkstra 等价的最短路径。将网格底图的相邻空闲格
/// 视为单位边时，下图 `*` 标出从源点 `S` 到目标 `G` 的查询结果路径：
///
///     S**.
///     ..*.
///     #.*#
///     ..*G
///
/// 图例：S=起点 G=终点 #=障碍 *=路径 .=空闲
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
