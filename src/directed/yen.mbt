// Yen's K-Shortest Loopless Paths algorithm.
//
// Reference: Yen, J. Y. (1971). "Finding the K Shortest Loopless Paths in a
// Network". Management Science, 17(11), 712-716.

///|
/// Find the K shortest loopless paths from `start` to `goal` in a weighted
/// directed graph.
///
/// ## Parameters
/// - `start`: source node
/// - `goal`: target node
/// - `nodes`: all nodes (needed to enumerate blocked edges)
/// - `edges`: `(u, v, weight)` directed edges
/// - `k`: number of shortest paths to return
///
/// ## Returns
/// - `Ok(paths)` — up to `k` paths sorted by cost (may be fewer if the graph
///   has fewer than k simple s-t paths).
/// - `Err(InvalidK(k))` if `k <= 0`.
///
/// ## Complexity
/// Time: O(K * V * (E + V log V)).
pub fn[N : Eq + Hash, W : @core.Weight + Compare] yen_k_shortest(
  start : N,
  goal : N,
  edges : Array[(N, N, W)],
  k : Int,
) -> Result[Array[(Array[N], W)], @core.PathError] {
  if k <= 0 {
    return Err(InvalidK(k))
  }
  // Prebuild adjacency once: O(E) total instead of O(E) per successor call.
  let adj : Map[N, Array[(N, W)]] = Map([])
  let edge_weight : Map[(N, N), W] = Map([])
  for e in edges {
    let (a, b, w) = e
    let lst = adj.get(a).unwrap_or([])
    lst.push((b, w))
    adj[a] = lst
    // Keep the cheapest weight in case of parallel edges.
    match edge_weight.get((a, b)) {
      Some(existing) => if w < existing { edge_weight[(a, b)] = w }
      None => edge_weight[(a, b)] = w
    }
  }
  // Build successor function that respects banned edges/nodes via O(1)
  // hash lookups.
  fn build_succ(
    banned_edges : Map[(N, N), Bool],
    banned_nodes : Map[N, Bool],
  ) -> (N) -> Array[(N, W)] {
    fn(u : N) -> Array[(N, W)] {
      let result : Array[(N, W)] = []
      for pair in adj.get(u).unwrap_or([]) {
        let (b, w) = pair
        if banned_edges.get((u, b)).unwrap_or(false) {
          continue
        }
        if banned_nodes.get(b).unwrap_or(false) {
          continue
        }
        result.push((b, w))
      }
      result
    }
  }

  // First shortest path (A = [shortest]).
  let first = dijkstra(start, build_succ(Map([]), Map([])), fn(n) { n == goal })
  match first {
    None => return Ok([])
    Some(p_and_c) => {
      let accepted : Array[(Array[N], W)] = [p_and_c]
      let candidates : Array[(Array[N], W)] = []
      let mut ki = 1
      while ki < k {
        let prev_path = accepted[ki - 1].0
        let mut i = 0
        while i < prev_path.length() - 1 {
          let spur_node = prev_path[i]
          let root_path = prev_path[0:i + 1].iter().collect()
          // Build banned edges: edges used at position i by any accepted
          // path sharing this root prefix.
          let banned_edges : Map[(N, N), Bool] = Map([])
          for acc in accepted {
            let ap = acc.0
            if ap.length() > i + 1 {
              let mut matches = true
              let mut j = 0
              while j <= i && matches {
                if ap[j] != prev_path[j] {
                  matches = false
                }
                j += 1
              }
              if matches {
                banned_edges[(ap[i], ap[i + 1])] = true
              }
            }
          }
          // Ban root path nodes (except spur_node) to keep paths loopless.
          let banned_nodes : Map[N, Bool] = Map([])
          for rn in root_path {
            if rn != spur_node {
              banned_nodes[rn] = true
            }
          }
          let spur = dijkstra(
            spur_node,
            build_succ(banned_edges, banned_nodes),
            fn(n) { n == goal },
          )
          match spur {
            Some(sp) => {
              let (spath, scost) = sp
              let full : Array[N] = []
              for rn in root_path {
                full.push(rn)
              }
              let mut si = 1
              while si < spath.length() {
                full.push(spath[si])
                si += 1
              }
              // Full cost = root-prefix cost (per-hop O(1) lookups)
              // + the spur cost returned by Dijkstra.
              let mut total = scost
              let mut pi = 0
              while pi < i {
                let a = full[pi]
                let b = full[pi + 1]
                match edge_weight.get((a, b)) {
                  Some(w) => total = @core.Weight::add(total, w)
                  None => ()
                }
                pi += 1
              }
              // Deduplicate.
              let mut dup = false
              for c in candidates {
                if c.0 == full {
                  dup = true
                  break
                }
              }
              if !dup {
                candidates.push((full, total))
              }
            }
            None => ()
          }
          i += 1
        }
        if candidates.length() == 0 {
          break
        }
        // Pick the cheapest candidate.
        candidates.sort_by(fn(a, b) {
          if a.1 < b.1 {
            -1
          } else if a.1 > b.1 {
            1
          } else {
            0
          }
        })
        let chosen = candidates[0]
        accepted.push(chosen)
        candidates.remove(0) |> ignore
        ki += 1
      }
      Ok(accepted)
    }
  }
}
