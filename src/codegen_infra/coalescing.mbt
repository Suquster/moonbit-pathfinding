// coalescing.mbt —— 寄存器合并（coalescing），旗舰深化旁路新增。
//
// paper-to-code：George-Appel 1996 迭代合并；Briggs 1994 保守判据。仅在两个传送
// 相关变量互不干涉、且满足保守判据（合并不增加着色难度）时执行合并。
//
// 设计落点（design.md §4.9，R2）：
//   * George 保守：`a` 的每个邻居要么与 `b` 干涉、要么度 `< k`（R2.3）；
//   * Briggs 保守：合并后节点的「度 `≥ k` 的邻居数」少于 `k`（R2.3）；
//   * 存在干涉边即拒绝合并（R2.4）。
// 复用同包私有 `build_adjacency`。

///|
/// 传送相关（move / copy）变量对集合。
pub(all) struct MoveSet {
  moves : Array[(Var, Var)]
} derive(Show)

///|
/// 合并策略：George 或 Briggs 保守判据。
pub(all) enum CoalesceStrategy {
  George
  Briggs
} derive(Eq, Show)

///|
/// 两变量是否在图中干涉（存在无向边）。
fn interferes(adj : Map[Var, Array[Var]], a : Var, b : Var) -> Bool {
  for u in adj.get(a).unwrap_or([]) {
    if u.id == b.id {
      return true
    }
  }
  false
}

///|
/// 节点在图中的度。
fn degree_of(adj : Map[Var, Array[Var]], v : Var) -> Int {
  adj.get(v).unwrap_or([]).length()
}

///|
/// George 保守判据：`a`/`b` 互不干涉，且 `a` 的每个邻居要么与 `b` 干涉、要么度 `< k`。
pub fn can_coalesce_george(
  g : InterferenceGraph,
  a : Var,
  b : Var,
  k : Int,
) -> Bool {
  let adj = build_adjacency(g)
  if interferes(adj, a, b) {
    return false
  }
  for t in adj.get(a).unwrap_or([]) {
    if t.id == b.id {
      continue
    }
    if degree_of(adj, t) >= k && not(interferes(adj, t, b)) {
      return false
    }
  }
  true
}

///|
/// Briggs 保守判据：`a`/`b` 互不干涉，且合并后节点的「度 `≥ k` 邻居数」少于 `k`。
pub fn can_coalesce_briggs(
  g : InterferenceGraph,
  a : Var,
  b : Var,
  k : Int,
) -> Bool {
  let adj = build_adjacency(g)
  if interferes(adj, a, b) {
    return false
  }
  // 合并后邻居集合 = adj[a] ∪ adj[b] \ {a, b}。
  let union : Map[Int, Bool] = Map([])
  for t in adj.get(a).unwrap_or([]) {
    if t.id != a.id && t.id != b.id {
      union[t.id] = true
    }
  }
  for t in adj.get(b).unwrap_or([]) {
    if t.id != a.id && t.id != b.id {
      union[t.id] = true
    }
  }
  let mut significant = 0
  for kv in union {
    let (tid, _) = kv
    if degree_of(adj, { id: tid }) >= k {
      significant = significant + 1
    }
  }
  significant < k
}

///|
/// 节点是否在图节点集合中。
fn nodes_contain(g : InterferenceGraph, v : Var) -> Bool {
  for n in g.nodes {
    if n.id == v.id {
      return true
    }
  }
  false
}

///|
/// 将 `b` 合并入 `a`：所有 `b` 的引用改写为 `a`，去自环与重边，返回新图。
fn merge_nodes(g : InterferenceGraph, a : Var, b : Var) -> InterferenceGraph {
  let nodes : Array[Var] = []
  for n in g.nodes {
    if n.id != b.id {
      nodes.push(n)
    }
  }
  let edge_set : Map[(Int, Int), Bool] = Map([])
  for e in g.edges {
    let (u, v) = e
    let nu = if u.id == b.id { a.id } else { u.id }
    let nv = if v.id == b.id { a.id } else { v.id }
    if nu == nv {
      continue // 自环
    }
    let lo = if nu < nv { nu } else { nv }
    let hi = if nu < nv { nv } else { nu }
    edge_set[(lo, hi)] = true
  }
  let edges : Array[(Var, Var)] = []
  for kv in edge_set {
    let ((lo, hi), _) = kv
    edges.push(({ id: lo }, { id: hi }))
  }
  edges.sort_by(fn(e1, e2) {
    let (a1, b1) = e1
    let (a2, b2) = e2
    if a1.id != a2.id {
      a1.id - a2.id
    } else {
      b1.id - b2.id
    }
  })
  { nodes, edges }
}

///|
/// 在保守判据下合并传送相关且互不干涉的变量对，返回合并后的干涉图。
///
/// 顺序处理 `moves`，以并查代表追踪已合并节点；仅在两端互不干涉且满足所选保守
/// 判据时合并（`b` 并入 `a`）。存在干涉边或判据不满足即跳过该对（R2.2/2.4）。
pub fn coalesce(
  g : InterferenceGraph,
  moves : MoveSet,
  k : Int,
  strategy? : CoalesceStrategy = George,
) -> InterferenceGraph {
  let mut cur = g
  let rep : Map[Int, Int] = Map([])
  fn find(x : Int) -> Int {
    let mut c = x
    let mut steps = 0
    while steps < 100000 {
      match rep.get(c) {
        Some(p) => c = p
        None => return c
      }
      steps = steps + 1
    }
    c
  }

  for mv in moves.moves {
    let (ra, rb) = mv
    let a : Var = { id: find(ra.id) }
    let b : Var = { id: find(rb.id) }
    if a.id == b.id {
      continue
    }
    if not(nodes_contain(cur, a)) || not(nodes_contain(cur, b)) {
      continue
    }
    let ok = match strategy {
      George => can_coalesce_george(cur, a, b, k)
      Briggs => can_coalesce_briggs(cur, a, b, k)
    }
    if ok {
      cur = merge_nodes(cur, a, b)
      rep[b.id] = a.id
    }
  }
  cur
}
