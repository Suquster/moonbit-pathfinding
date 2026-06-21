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
    // Cache each frame's successor list so `successors(u)` is called once
    // per node instead of once per visited edge.
    let succ_stack : Array[Array[N]] = [successors(v)]
    index_map[v] = idx
    lowlink[v] = idx
    idx += 1
    stack.push(v)
    on_stack[v] = true
    //
    // 循环不变式（R10.1 · Tarjan 迭代 DFS 主循环 · 谓词见 @proofs.scc_partition_post）:
    //
    //   (布尔陈述) 对栈上每个节点 u，index_map[u] 为其 DFS 发现序号、lowlink[u] 不大于
    //       index_map[u] 且等于「u 经其 DFS 子树及至多一条回边可达的最小发现序号」的当前
    //       下界；on_stack[w]==true 当且仅当 w 已被发现但其所属 SCC 尚未输出；tarjan 栈
    //       中节点的发现序号自底向上严格递增。
    //
    //   (初始化成立) 进入循环前 call_stack=[(v,0)]，index_map[v]=lowlink[v]=当前 idx，
    //       v 已压入 tarjan 栈且 on_stack[v]=true：单节点平凡满足 lowlink≤index 与栈序递增。
    //
    //   (迭代保持) 处理 u 的下一条边 (u,w)：若 w 未发现则压栈递归（建立 w 的序号并维持
    //       栈序递增）；若 w 在 tarjan 栈上则用 index_map[w] 收紧 lowlink[u]。某帧子节点
    //       全部处理完后，若 lowlink[u]==index_map[u]，则 u 为 SCC 根，弹出 tarjan 栈直至
    //       u 构成一个完整 SCC（其成员 on_stack 置 false 并移出），否则把 lowlink[u] 上传
    //       父节点。故 lowlink 与栈序不变式在每次迭代后保持，且每节点恰被输出到一个 SCC。
    //
    while call_stack.length() > 0 {
      let (u, i) = call_stack[call_stack.length() - 1]
      let neighbors = succ_stack[succ_stack.length() - 1]
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
          succ_stack.push(successors(w))
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
        ignore(succ_stack.pop())
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
