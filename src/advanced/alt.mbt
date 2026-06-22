// ALT — A* + Landmarks + Triangle inequality.
//
// Reference: Goldberg, A. V., & Harrelson, C. (2005). "Computing the
// Shortest Path: A* Search Meets Graph Theory." SODA 2005, pp. 156-165.
//
// Core idea (per docs/zh/algorithms/alt.md):
//
//   For any triple (l, n, t) of nodes the triangle inequality gives
//       |dist(l, n) - dist(l, t)| <= dist(n, t)
//   so `h(n) := max_{l in L} |dist(l, n) - dist(l, t)|` is a provably
//   admissible heuristic, consistent as well when the `max` is taken
//   over a finite set L of landmarks.
//
// This file provides:
//   * `Landmark[N, W]` — preprocessed distance tables.
//   * `alt_preprocess(nodes, successors, k)` — picks k farthest-first
//     landmarks and runs Dijkstra from each to fill the tables.
//   * `alt_query(lm, start, goal, successors)` — A* with the triangular
//     landmark heuristic, falling back to uniform h=zero() if tables are
//     empty (degenerates to Dijkstra safely).

///|
/// Preprocessed landmark data.
///
/// Fields:
///   * `nodes`      — node list; indexes align with `dist_from`/`dist_to`.
///   * `landmarks`  — chosen landmark node set (size = k).
///   * `dist_from`  — `dist_from[l][n]` = shortest distance from landmark l
///                    to node n along the original graph.
///   * `dist_to`    — `dist_to[l][n]`   = shortest distance from node n to
///                    landmark l (computed by running Dijkstra on a
///                    reverse view if provided; in the symmetric undirected
///                    case this equals `dist_from`).
pub struct Landmark[N, W] {
  nodes : Array[N]
  landmarks : Array[N]
  dist_from : Map[N, Map[N, W]]
  dist_to : Map[N, Map[N, W]]
}

///|
/// Run single-source Dijkstra on a successor function, returning the map
/// from every reachable node to its distance from `source`. A helper we
/// reuse for landmark-table construction.
fn[N : Eq + Hash, W : @core.Weight + Compare] dijkstra_from(
  source : N,
  successors : (N) -> Array[(N, W)],
) -> Map[N, W] {
  let dist : Map[N, W] = Map([])
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
    for pair in successors(u) {
      let (v, w) = pair
      let new_d = @core.Weight::add(d, w)
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
  dist
}

///|
/// Pick `k` landmarks using the "farthest-first" heuristic:
/// start from `nodes[0]`, then iteratively pick the node whose minimum
/// distance to the already-chosen landmark set is largest. Produces a
/// landmark set that spreads across the graph rather than clustering.
fn[N : Eq + Hash, W : @core.Weight + Compare] pick_landmarks(
  nodes : Array[N],
  successors : (N) -> Array[(N, W)],
  k : Int,
) -> Array[N] {
  if nodes.length() == 0 || k <= 0 {
    return []
  }
  let chosen : Array[N] = [nodes[0]]
  // `min_dist[n]` = distance from `n` to its nearest already-chosen landmark.
  let min_dist : Map[N, W] = dijkstra_from(nodes[0], successors)
  while chosen.length() < k && chosen.length() < nodes.length() {
    // Find the farthest node w.r.t. min_dist.
    let mut far_node : N? = None
    let mut far_dist : W = @core.Weight::zero()
    for n in nodes {
      let already = {
        let mut in_set = false
        for c in chosen {
          if c == n {
            in_set = true
            break
          }
        }
        in_set
      }
      if already {
        continue
      }
      match min_dist.get(n) {
        Some(d) =>
          match far_node {
            None => {
              far_node = Some(n)
              far_dist = d
            }
            Some(_) =>
              if d > far_dist {
                far_node = Some(n)
                far_dist = d
              }
          }
        None => ()
      }
    }
    match far_node {
      Some(next) => {
        chosen.push(next)
        // Update min_dist with distances from the new landmark.
        let new_table = dijkstra_from(next, successors)
        for n in nodes {
          match new_table.get(n) {
            Some(d) =>
              match min_dist.get(n) {
                Some(cur) => if d < cur { min_dist[n] = d }
                None => min_dist[n] = d
              }
            None => ()
          }
        }
      }
      None => break // no more reachable nodes
    }
  }
  chosen
}

///|
/// Helper: build the `dist_from` / `dist_to` landmark distance tables for a
/// fixed landmark set. `dist_from[l]` is single-source Dijkstra from `l` on
/// the original graph; `dist_to[l]` is Dijkstra from `l` on the reverse
/// graph (= distances *into* `l`). The reverse edge map is materialised
/// once (linear scan, no in-loop array `+`). Shared by `alt_preprocess`
/// (farthest-first landmarks) and `alt_preprocess_with_landmarks`
/// (caller-supplied landmarks) so both paths stay consistent.
fn[N : Eq + Hash, W : @core.Weight + Compare] alt_build_tables(
  nodes : Array[N],
  successors : (N) -> Array[(N, W)],
  landmarks : Array[N],
) -> (Map[N, Map[N, W]], Map[N, Map[N, W]]) {
  let rev_map : Map[N, Array[(N, W)]] = Map([])
  for n in nodes {
    rev_map[n] = []
  }
  for u in nodes {
    for pair in successors(u) {
      let (v, w) = pair
      let lst = rev_map.get(v).unwrap_or([])
      lst.push((u, w))
      rev_map[v] = lst
    }
  }
  let reverse_succ = fn(n : N) -> Array[(N, W)] { rev_map.get(n).unwrap_or([]) }
  let dist_from : Map[N, Map[N, W]] = Map([])
  let dist_to : Map[N, Map[N, W]] = Map([])
  for l in landmarks {
    // dist_from[l][n] = dist(l, n) on the original graph
    dist_from[l] = dijkstra_from(l, successors)
    // dist_to[l][n] = dist(n, l) = dist(l, n) on the reverse graph
    dist_to[l] = dijkstra_from(l, reverse_succ)
  }
  (dist_from, dist_to)
}

///|
/// Preprocess a graph for ALT by selecting `num_landmarks` landmarks and
/// computing distance tables **in both directions** (needed for
/// correctness on directed graphs).
///
/// For each landmark `l`:
///   * `dist_from[l][n]` = dist(l, n) via forward Dijkstra.
///   * `dist_to[l][n]`   = dist(n, l) via reverse-graph Dijkstra.
///
/// Both tables are essential: the triangle-inequality heuristic for
/// ALT uses `max_l max( dist_to[l][target] - dist_to[l][node],
///                      dist_from[l][node] - dist_from[l][target] )`,
/// which is admissible on directed graphs (see
/// docs/zh/algorithms/alt.md).
pub fn[N : Eq + Hash, W : @core.Weight + Compare] alt_preprocess(
  nodes : Array[N],
  successors : (N) -> Array[(N, W)],
  num_landmarks : Int,
) -> Landmark[N, W] {
  let landmarks = pick_landmarks(nodes, successors, num_landmarks)
  let (dist_from, dist_to) = alt_build_tables(nodes, successors, landmarks)
  { nodes, landmarks, dist_from, dist_to }
}

///|
/// Landmark heuristic: `h(n) = max_l |dist(l, n) - dist(l, target)|`.
///
/// Now that `Weight::sub` exists (saturating-at-zero semantics), we can
/// compute the absolute difference on a generic `W` and take the
/// pointwise max over every landmark that is **reachable from both** `n`
/// and `target`. Unreachable landmarks are skipped — they would contribute
/// `infinity - finite = infinity`, which is always an over-estimate and
/// breaks the admissibility of A*.
///
/// Mathematical correctness (proved in docs/zh/algorithms/alt.md):
///
///   For any triple (l, n, t) of nodes in a graph where
///   `dist(l, n)` and `dist(l, t)` are both finite,
///       |dist(l, n) - dist(l, t)| <= dist(n, t)   (triangle inequality)
///   hence `max_l |...|` is an admissible heuristic for A* from n to t.
fn[N : Eq + Hash, W : @core.Weight + Compare + Eq] alt_heuristic(
  lm : Landmark[N, W],
  node : N,
  target : N,
) -> W {
  let inf = @core.Weight::infinity()
  let mut best = @core.Weight::zero()
  for l in lm.landmarks {
    // Direction 1: triangle using dist_from (l → ·).
    //   dist(l, target) <= dist(l, node) + dist(node, target)
    //   => h1 = dist_from[l][target] - dist_from[l][node] <= dist(node, target),
    //   admissible when both are finite.
    let from_table = lm.dist_from.get(l).unwrap_or(Map([]))
    match (from_table.get(node), from_table.get(target)) {
      (Some(fn_), Some(ft)) =>
        if fn_ != inf && ft != inf && ft >= fn_ {
          let diff = @core.Weight::sub(ft, fn_)
          if diff > best {
            best = diff
          }
        }
      _ => ()
    }
    // Direction 2: triangle using dist_to (· → l).
    //   dist(node, l) <= dist(node, target) + dist(target, l)
    //   => h2 = dist_to[l][node] - dist_to[l][target] <= dist(node, target),
    //   admissible when both are finite.
    let to_table = lm.dist_to.get(l).unwrap_or(Map([]))
    match (to_table.get(node), to_table.get(target)) {
      (Some(tn), Some(tt)) =>
        if tn != inf && tt != inf && tn >= tt {
          let diff = @core.Weight::sub(tn, tt)
          if diff > best {
            best = diff
          }
        }
      _ => ()
    }
  }
  best
}

///|
/// ALT query: A* driven by the landmark heuristic.
///
/// When the landmark table is empty (no preprocessing, or `num_landmarks = 0`),
/// the heuristic becomes zero and ALT degenerates to plain Dijkstra.
pub fn[N : Eq + Hash, W : @core.Weight + Compare + Eq] alt_query(
  lm : Landmark[N, W],
  start : N,
  goal : N,
  successors : (N) -> Array[(N, W)],
) -> (Array[N], W)? {
  if start == goal {
    return Some(([start], @core.Weight::zero()))
  }
  let g_cost : Map[N, W] = Map([])
  let parents : Map[N, N] = Map([])
  let pq : @core.PQueue[N, W] = @core.PQueue::new()
  let zero = @core.Weight::zero()
  g_cost[start] = zero
  pq.push(alt_heuristic(lm, start, goal), start)
  while !pq.is_empty() {
    let (_, u) = pq.pop().unwrap()
    // Skip stale entries: if g_cost[u] has been improved since this push,
    // this pop is outdated. This is the standard "lazy deletion" pattern
    // used by Dijkstra; combined with an admissible heuristic it guarantees
    // that when we pop goal, g_cost[goal] is optimal — so we can stop there
    // instead of exhausting the whole queue.
    let gu = match g_cost.get(u) {
      Some(g) => g
      None => continue
    }
    if u == goal {
      let path = [goal]
      let mut node = goal
      while node != start {
        match parents.get(node) {
          Some(p) => {
            node = p
            path.push(node)
          }
          None => break
        }
      }
      path.rev_in_place()
      return Some((path, gu))
    }
    // Expand successors.
    for pair in successors(u) {
      let (v, w) = pair
      let tentative = @core.Weight::add(gu, w)
      let improve = match g_cost.get(v) {
        Some(cur) => tentative < cur
        None => true
      }
      if improve {
        g_cost[v] = tentative
        parents[v] = u
        let f = @core.Weight::add(tentative, alt_heuristic(lm, v, goal))
        pq.push(f, v)
      }
    }
  }
  // Queue exhausted without popping goal: unreachable.
  None
}
