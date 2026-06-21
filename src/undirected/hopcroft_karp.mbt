// Hopcroft-Karp maximum bipartite matching.
//
// Alternates BFS phases (building layered alternating-path structure) with
// DFS phases (augmenting along vertex-disjoint shortest alternating paths),
// achieving O(E * sqrt(V)) — asymptotically faster than the naive Hungarian
// augmenting approach.
//
// Reference: Hopcroft, J. E., & Karp, R. M. (1973). "An n^(5/2) algorithm
// for maximum matchings in bipartite graphs". SIAM J. Comput., 2(4).

///|
/// Sentinel level for unvisited / unmatched-side vertices.
const HK_INF : Int = 2147483647

///|
/// Compute a maximum matching in a bipartite graph.
///
/// ## Parameters
/// - `left`: nodes of the left partition
/// - `right`: nodes of the right partition
/// - `neighbors`: adjacency from a left node to its right-side neighbors
///
/// ## Returns
/// An array of matched `(left, right)` pairs of maximum cardinality.
///
/// ## Complexity
/// Time: O(E * sqrt(V)). Space: O(V + E).
pub fn[L : Eq + Hash, R : Eq + Hash] hopcroft_karp(
  left : Array[L],
  right : Array[R],
  neighbors : (L) -> Array[R],
) -> Array[(L, R)] {
  let nl = left.length()
  let nr = right.length()
  let rindex : Map[R, Int] = Map([])
  for j in 0..<nr {
    rindex[right[j]] = j
  }
  // Pre-resolve adjacency to integer indices once.
  let adj : Array[Array[Int]] = Array::makei(nl, fn(i) {
    let lst : Array[Int] = []
    for r in neighbors(left[i]) {
      match rindex.get(r) {
        Some(j) => lst.push(j)
        None => ()
      }
    }
    lst
  })
  // match_l[i] = right index matched to left i (-1 if free), and vice versa.
  let match_l : Array[Int] = Array::make(nl, -1)
  let match_r : Array[Int] = Array::make(nr, -1)
  let level : Array[Int] = Array::make(nl, HK_INF)
  fn bfs() -> Bool {
    let queue : Array[Int] = []
    for i in 0..<nl {
      if match_l[i] < 0 {
        level[i] = 0
        queue.push(i)
      } else {
        level[i] = HK_INF
      }
    }
    let mut found = false
    let mut head = 0
    while head < queue.length() {
      let u = queue[head]
      head += 1
      for j in adj[u] {
        let w = match_r[j]
        if w < 0 {
          found = true
        } else if level[w] == HK_INF {
          level[w] = level[u] + 1
          queue.push(w)
        }
      }
    }
    found
  }

  // Iterative augmenting-path search with an explicit call stack, mirroring
  // the recursive DFS exactly but without risking native-stack overflow on
  // long alternating paths (which can reach depth O(V) on large graphs).
  // This matches the codebase convention of keeping graph DFS non-recursive
  // (cf. `tarjan_scc`, `directed/dfs`).
  //
  // Each frame is `cs_node[k]` (a left vertex) with `cs_pos[k]` its current
  // scan offset into `adj`. `cs_j[k]` records the right vertex chosen to
  // descend from frame `k` to frame `k+1`; on success the whole alternating
  // path is re-matched in one upward pass.
  let cs_node : Array[Int] = []
  let cs_pos : Array[Int] = []
  let cs_j : Array[Int] = []
  fn dfs(u0 : Int) -> Bool {
    cs_node.clear()
    cs_pos.clear()
    cs_j.clear()
    cs_node.push(u0)
    cs_pos.push(0)
    while cs_node.length() > 0 {
      let top = cs_node.length() - 1
      let u = cs_node[top]
      let mut advanced = false
      while cs_pos[top] < adj[u].length() {
        let j = adj[u][cs_pos[top]]
        cs_pos[top] += 1
        let w = match_r[j]
        if w < 0 {
          // Free right vertex reached: augment along the whole path.
          match_l[u] = j
          match_r[j] = u
          let mut k = top - 1
          while k >= 0 {
            match_l[cs_node[k]] = cs_j[k]
            match_r[cs_j[k]] = cs_node[k]
            k -= 1
          }
          return true
        } else if level[w] == level[u] + 1 {
          cs_j.push(j)
          cs_node.push(w)
          cs_pos.push(0)
          advanced = true
          break
        }
      }
      if !advanced {
        // `u` exhausted with no augmenting edge: mark dead and backtrack.
        level[u] = HK_INF
        ignore(cs_node.pop())
        ignore(cs_pos.pop())
        if cs_node.length() > 0 {
          ignore(cs_j.pop())
        }
      }
    }
    false
  }

  while bfs() {
    for i in 0..<nl {
      if match_l[i] < 0 {
        let _ = dfs(i)
      }
    }
  }
  let result : Array[(L, R)] = []
  for i in 0..<nl {
    if match_l[i] >= 0 {
      result.push((left[i], right[match_l[i]]))
    }
  }
  result
}
