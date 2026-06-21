// Prim's Minimum Spanning Tree algorithm.
//
// Complements Kruskal: Prim grows a single tree from a seed node using a
// priority queue, which performs better on dense adjacency-list graphs.
//
// Reference: Prim, R. C. (1957). "Shortest connection networks and some
// generalizations". Bell System Technical Journal, 36(6), 1389-1401.

///|
/// Compute a minimum spanning tree (MST) of an undirected weighted graph
/// using Prim's algorithm (lazy variant with a binary min-heap).
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `neighbors`: function returning `(neighbor, edge_weight)` pairs; the
///   graph is undirected, so if `v` is a neighbor of `u`, `u` must also be
///   reported as a neighbor of `v`
///
/// ## Returns
/// An array of `(u, v, weight)` edges forming the MST, where `u` is the
/// tree-side endpoint. For a connected graph of |V| nodes the result has
/// exactly |V| - 1 edges; for disconnected graphs each component yields its
/// own spanning tree (minimum spanning forest).
///
/// ## Complexity
/// Time: O(E log E). Space: O(V + E).
pub fn[N : Eq + Hash, W : @core.Weight] prim_mst(
  nodes : Array[N],
  neighbors : (N) -> Array[(N, W)],
) -> Array[(N, N, W)] {
  let in_tree : Map[N, Bool] = Map([])
  let result : Array[(N, N, W)] = []
  for seed in nodes {
    if in_tree.get(seed) is Some(_) {
      continue
    }
    // Grow a new tree from this component's seed.
    in_tree[seed] = true
    let pq : @core.PQueue[(N, N), W] = @core.PQueue::new()
    for pair in neighbors(seed) {
      let (v, w) = pair
      pq.push(w, (seed, v))
    }
    //
    // 循环不变式（R10.1 · Prim 生长主循环 · 谓词见 @proofs.mst_post）:
    //
    //   (布尔陈述) in_tree 中的节点构成一棵已生长的树 T，result 中对应的边恰为 T 的
    //       树边，且 T 是当前连通分量某棵最小生成树的子树；优先队列 pq 含且仅含「一端
    //       在 T 内、一端在 T 外」的横切边（含已失效的陈旧项，弹出时按 in_tree 检验）。
    //
    //   (初始化成立) 进入循环前 in_tree={seed}，result 未加本分量边，pq 已装入 seed 的
    //       全部关联边：单节点树平凡是 MST 子树，pq 恰为该树的横切边集合。
    //
    //   (迭代保持) 每次弹出当前最轻横切边 (u,v)。若 v 已在树中（陈旧项）则跳过；否则由
    //       Cut Property，连接 T 与 T 外的最小横切边属于某棵包含 T 的 MST，将 v 并入树、
    //       (u,v,w) 记入 result，并把 v 的新横切边入队。树规模严格 +1，故循环终止；结束
    //       时 T 为该分量的最小生成树。
    //
    while !pq.is_empty() {
      let (w, edge) = pq.pop().unwrap()
      let (u, v) = edge
      if in_tree.get(v) is Some(_) {
        continue
      }
      in_tree[v] = true
      result.push((u, v, w))
      for pair in neighbors(v) {
        let (next, nw) = pair
        if in_tree.get(next) is None {
          pq.push(nw, (v, next))
        }
      }
    }
  }
  result
}
