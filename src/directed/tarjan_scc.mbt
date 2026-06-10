// Tarjan's strongly connected components (SCC) algorithm.
//
// Reference: Tarjan, R. (1972). "Depth-first search and linear graph
// algorithms". SIAM Journal on Computing, 1(2), 146-160.

///|
/// Compute the strongly connected components of a directed graph in a single
/// DFS pass, using Tarjan's algorithm (iterative version with explicit stack
/// to avoid deep recursion).
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `successors`: function returning outgoing edges of a node
///
/// ## Returns
/// An array of SCCs, each SCC being an array of its member nodes.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
pub fn[N : Eq + Hash] tarjan_scc(
  nodes : Array[N],
  successors : (N) -> Array[N],
) -> Array[Array[N]] {
  let index_map : Map[N, Int] = Map([])
  let lowlink : Map[N, Int] = Map([])
  let on_stack : Map[N, Bool] = Map([])
  let stack : Array[N] = []
  let mut idx = 0
  let sccs : Array[Array[N]] = []
  // Iterative DFS using a work stack of (node, iterator-position).
  // Each work-stack entry carries the index into successors(node) to process next.
  fn strong_connect(v : N) -> Unit {
    // Simulated recursion via a manual stack to avoid MoonBit recursion limits.
    let call_stack : Array[(N, Int)] = [(v, 0)]
    index_map[v] = idx
    lowlink[v] = idx
    idx += 1
    stack.push(v)
    on_stack[v] = true
    while call_stack.length() > 0 {
      let (u, i) = call_stack[call_stack.length() - 1]
      let neighbors = successors(u)
      if i < neighbors.length() {
        call_stack[call_stack.length() - 1] = (u, i + 1)
        let w = neighbors[i]
        if !index_map.contains(w) {
          index_map[w] = idx
          lowlink[w] = idx
          idx += 1
          stack.push(w)
          on_stack[w] = true
          call_stack.push((w, 0))
        } else if on_stack.get(w).unwrap_or(false) {
          let lw = index_map.get(w).unwrap()
          let lu = lowlink.get(u).unwrap()
          if lw < lu {
            lowlink[u] = lw
          }
        }
      } else {
        // All children processed; check if u is an SCC root.
        let lu = lowlink.get(u).unwrap()
        let iu = index_map.get(u).unwrap()
        if lu == iu {
          let component : Array[N] = []
          while stack.length() > 0 {
            let w = stack.pop().unwrap()
            on_stack[w] = false
            component.push(w)
            if w == u {
              break
            }
          }
          sccs.push(component)
        }
        ignore(call_stack.pop())
        // Propagate lowlink back to parent.
        if call_stack.length() > 0 {
          let (parent, _) = call_stack[call_stack.length() - 1]
          let lp = lowlink.get(parent).unwrap()
          if lu < lp {
            lowlink[parent] = lu
          }
        }
      }
    }
  }

  for n in nodes {
    if !index_map.contains(n) {
      strong_connect(n)
    }
  }
  sccs
}
