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
      //
      // 循环不变式（R10.1 · Yen K-最短路主循环 · 谓词见 @proofs.yen_post）:
      //
      //   (布尔陈述) accepted 恰为按代价非降排列的前 ki 条无环 s-t 路径，且互不相同；
      //       candidates 是「以某 accepted 路径前缀为根、在被禁边/禁点约束下经 Dijkstra
      //       求得」的待选偏离路径池，其中任一候选代价不小于已接受路径的末条。
      //
      //   (初始化成立) 进入循环前 ki=1，accepted=[最短路]，candidates=[]：单条最短路
      //       平凡有序且无环；空候选池平凡满足下界条件。
      //
      //   (迭代保持) 对第 ki-1 条路径的每个 spur 节点，禁掉「与已接受路径共享根前缀」的
      //       后继边及根上其余节点（保证无环），用 Dijkstra 求 spur→goal，与根前缀拼接、
      //       去重后入 candidates。随后线性扫描取代价最小的候选加入 accepted、移出候选池，
      //       ki 递增：新接受路径代价不小于上一条（候选下界 + 取最小），故 accepted 始终
      //       有序。候选池空则提前结束。最多产出 k 条，循环终止。
      //
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
        // Pick the cheapest candidate via a single linear scan (O(C)) rather
        // than re-sorting the whole growing candidate list every iteration
        // (which would be O(C log C) per round). Ties keep the earliest
        // candidate for deterministic output.
        let mut best_idx = 0
        let mut bi = 1
        while bi < candidates.length() {
          if candidates[bi].1 < candidates[best_idx].1 {
            best_idx = bi
          }
          bi += 1
        }
        let chosen = candidates[best_idx]
        accepted.push(chosen)
        candidates.remove(best_idx) |> ignore
        ki += 1
      }
      Ok(accepted)
    }
  }
}
