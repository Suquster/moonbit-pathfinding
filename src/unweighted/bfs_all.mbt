// Single-source BFS producing the full distance and parent tables.
//
// Complements the goal-directed `bfs`: instead of stopping at the first goal
// node, it visits every reachable node, enabling cheap repeated path queries
// from one fixed source on unweighted graphs.

///|
/// Result of a full single-source BFS: hop counts and the BFS tree encoded
/// as a parent map.
pub struct BfsTree[N] {
  /// Source node the tree is rooted at.
  source : N
  /// `dist[v]` = number of edges from `source` to `v` (absent ⇒ unreachable).
  dist : Map[N, Int]
  /// `parent[v]` = predecessor of `v` on a shortest path (absent for `source`).
  parent : Map[N, N]
}

///|
/// Compute hop distances from `start` to **every** reachable node.
///
/// ## Parameters
/// - `start`: source node
/// - `successors`: function returning the neighbors of a node
///
/// ## Returns
/// A `BfsTree` with the hop-count table and the parent map.
///
/// ## Complexity
/// Time: O(V + E). Space: O(V).
pub fn[N : Eq + Hash] bfs_all(
  start : N,
  successors : (N) -> Array[N],
) -> BfsTree[N] {
  let dist : Map[N, Int] = Map([])
  let parent : Map[N, N] = Map([])
  let queue : Array[N] = [start]
  dist[start] = 0
  let mut head = 0
  //
  // 循环不变式（R10.1 · 全表 BFS 主循环 · 谓词见 @proofs.bfs_all_post / bfs_level_invariant）:
  //
  //   (布尔陈述) 队列中节点的层级（dist 值）非降且极差 ≤1（队列至多同时容纳相邻两层，
  //       即 @proofs.bfs_level_invariant(queue 层级) 成立）；凡 dist[v] 已赋值者，dist[v]
  //       恰为 start 到 v 的最短边数，且 parent[v] 见证最短路上的前驱。
  //
  //   (初始化成立) 进入循环前 queue=[start]、dist[start]=0、head=0：单元素队列层级极差为
  //       0≤1，start 到自身边数 0 即最短，parent 为空平凡成立。
  //
  //   (迭代保持) 出队队首 u（层级 du），对每个未赋值后继 v 置 dist[v]=du+1、parent[v]=u
  //       并入队尾。新入队节点层级恒为 du+1，而队列中现存节点层级 ∈{du, du+1}，故入队后
  //       极差仍 ≤1、层级非降保持；首次赋值即最短边数（BFS 按层扩展）。每节点至多入队一次，
  //       循环终止后得到完整 BFS 树。
  //
  while head < queue.length() {
    let u = queue[head]
    head += 1
    let du = dist.get(u).unwrap_or(0)
    for v in successors(u) {
      if dist.get(v) is None {
        dist[v] = du + 1
        parent[v] = u
        queue.push(v)
      }
    }
  }
  { source: start, dist, parent }
}

///|
/// Extract the shortest (fewest-edge) path from the tree's source to
/// `target`, or `None` when `target` was unreachable.
///
/// ## Complexity
/// Time: O(path length). Space: O(path length).
pub fn[N : Eq + Hash] BfsTree::path_to(
  self : BfsTree[N],
  target : N,
) -> Array[N]? {
  if self.dist.get(target) is None {
    return None
  }
  let path = [target]
  let mut node = target
  while node != self.source {
    match self.parent.get(node) {
      Some(p) => {
        node = p
        path.push(node)
      }
      None => break
    }
  }
  path.rev_in_place()
  Some(path)
}

///|
/// Hop count from the tree's source to `target`, or `None` when unreachable.
pub fn[N : Eq + Hash] BfsTree::distance_to(
  self : BfsTree[N],
  target : N,
) -> Int? {
  self.dist.get(target)
}
