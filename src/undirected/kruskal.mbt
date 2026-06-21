// Kruskal's Minimum Spanning Tree algorithm.
//
// Reference: Kruskal, J. B. (1956). "On the shortest spanning subtree of a
// graph and the traveling salesman problem". Proceedings of the American
// Mathematical Society, 7(1), 48-50.

///|
/// Compute a minimum spanning tree (MST) of an undirected weighted graph
/// using Kruskal's algorithm (sort edges by weight, use DSU for cycle check).
///
/// ## Parameters
/// - `nodes`: all graph nodes
/// - `edges`: list of `(u, v, weight)` edges (undirected; each edge listed once)
///
/// ## Returns
/// An array of edges that form the MST. For a connected graph of |V| nodes,
/// the result contains exactly |V| - 1 edges. For disconnected graphs, the
/// result is a minimum spanning forest (fewer edges).
///
/// ## Complexity
/// Time: O(E log E). Space: O(V + E).
pub fn[N : Eq + Hash, W : @core.Weight] kruskal_mst(
  nodes : Array[N],
  edges : Array[(N, N, W)],
) -> Array[(N, N, W)] {
  let sorted_edges = edges.copy()
  sorted_edges.sort_by(fn(a, b) {
    let (_, _, wa) = a
    let (_, _, wb) = b
    if wa < wb {
      -1
    } else if wa > wb {
      1
    } else {
      0
    }
  })
  let dsu : @core.DSU[N] = @core.DSU::new()
  for n in nodes {
    dsu.make_set(n)
  }
  let result : Array[(N, N, W)] = []
  //
  // 循环不变式（R10.1 · Kruskal 主循环 · 谓词见 @proofs.mst_post）:
  //
  //   (布尔陈述) 已按权升序处理前若干条边后，result 中的边构成原图的一个无环子集
  //       （森林），且是某棵最小生成树（森林）的子集；DSU 的连通分量恰为 result
  //       所诱导的顶点划分。
  //
  //   (初始化成立) 进入循环前 result 为空、DSU 中每个节点自成一集：空边集平凡无环，
  //       且是任意 MST 的子集；划分为全体单点集，与空 result 一致。
  //
  //   (迭代保持) 边已按权非降枚举。对当前最轻的跨分量边 (u,v)（dsu.union 返回 true）
  //       由 Cut Property（割性质）知其属于某棵包含当前森林的 MST，加入后仍无环、
  //       仍是 MST 子集，并合并两分量保持划分一致；同分量边（union 返回 false）会成环，
  //       被跳过。集满 |V|-1 条边即生成树完成，提前 break。
  //
  for edge in sorted_edges {
    let (u, v, _w) = edge
    if dsu.union(u, v) {
      result.push(edge)
      if result.length() == nodes.length() - 1 {
        break
      }
    }
  }
  result
}
