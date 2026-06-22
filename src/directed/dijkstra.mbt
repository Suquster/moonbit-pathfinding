// Dijkstra's single-source shortest-path algorithm for non-negative weights.
//
// Uses a binary min-heap priority queue with lazy deletion of stale entries.
//
// Reference: Dijkstra, E. W. (1959). "A note on two problems in connexion
// with graphs". Numerische Mathematik, 1(1), 269-271.

///|
/// Shortest path from `start` to the first node satisfying `goal`, using
/// Dijkstra's algorithm on non-negative edge weights.
///
/// Loop invariants (for future `moon prove` integration):
///   1. Every popped node has its final shortest distance assigned to `dist`.
///   2. For any node `v` with `dist[v] < infinity`, there exists a walk from
///      `start` to `v` of total weight `dist[v]`.
///   3. With all edge weights >= zero(), every dist value is >= zero().
///
/// ## Parameters
/// - `start`: starting node
/// - `successors`: function returning `(neighbor, edge_weight)` pairs
/// - `goal`: predicate testing whether a node is the target
///
/// ## Returns
/// `Some((path, total_cost))` if reachable, `None` otherwise.
///
/// ## Complexity
/// Time: O((V + E) log V). Space: O(V).
///
/// ## ASCII 示意（5×5 网格，非负权最短路径）
/// Dijkstra 以非负边权扩展，返回总权重最小的路径。将每步移动视为单位
/// 权重时，下图 `*` 标出一条绕过障碍 `#` 的最小代价路径：
///
///     S*...
///     .*#..
///     .***.
///     ##.*.
///     ...*G
///
/// 图例：S=起点 G=终点 #=障碍 *=路径 .=空闲
pub fn[N : Eq + Hash, W : @core.Weight + Compare] dijkstra(
  start : N,
  successors : (N) -> Array[(N, W)],
  goal : (N) -> Bool,
) -> (Array[N], W)? {
  let dist : Map[N, W] = Map([])
  let parents : Map[N, N] = Map([])
  let pq : @core.PQueue[N, W] = @core.PQueue::new()
  let zero = @core.Weight::zero()
  dist[start] = zero
  pq.push(zero, start)
  //
  // Loop invariant (R10.1 · 弹出单调性 · 谓词见 @proofs.dijkstra_pop_monotonic):
  //
  //   (布尔陈述) Pop-monotonicity:
  //       令 popped = [d_0, d_1, ..., d_k] 为「按弹出顺序记录的已确定距离」
  //       序列（每次成功出队且非陈旧时追加的 d）。则该序列单调非降：
  //         forall i, popped[i] <= popped[i+1]
  //       等价地 @proofs.dijkstra_pop_monotonic(popped) == true。
  //
  //   (初始化成立) 循环首次进入时 popped 为空序列，单调非降平凡成立；
  //       唯一入队元素为 (zero, start)，首个弹出值 d_0 = zero 也满足。
  //
  //   (迭代保持) 最小堆每次弹出当前最小键 d，且边权非负使得任何后续松弛产生
  //       的新键 new_dist = d + w >= d；因此后续入队键不小于当前弹出键，
  //       下一次弹出的非陈旧键 d_{k+1} >= d_k。陈旧条目（d > dist[u]）被
  //       `continue` 跳过、不追加到 popped，不破坏单调性。故不变式在每次
  //       迭代后保持。该不变式是「已弹出节点距离最终确定」定理的核心见证，
  //       由 12.2 的 prop_loop_invariant_test.mbt 以 ≥100 随机图驱动验证。
  //
  while !pq.is_empty() {
    let (d, u) = pq.pop().unwrap()
    // Skip stale entries: the popped distance may be worse than a later update.
    match dist.get(u) {
      Some(current) => if d > current { continue }
      None => continue
    }
    /// invariant: after this point `d == dist[u]` and `dist[u]` is the final
    ///            shortest distance from `start` to `u` — no future relaxation
    ///            can improve it (proof: heap yields non-decreasing keys and
    ///            edge weights are non-negative). Anchor for M4 `moon prove`.
    if goal(u) {
      // Reconstruct path.
      let path = [u]
      let mut node = u
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
      return Some((path, d))
    }
    for pair in successors(u) {
      let (v, w) = pair
      let new_dist = @core.Weight::add(d, w)
      /// invariant: `new_dist >= zero()` because `d >= zero()` holds for every
      ///            popped entry and all edge weights `w >= zero()` by the
      ///            Dijkstra precondition (Weight::add preserves non-negativity
      ///            for non-negative operands). Anchor for M4 `moon prove`.
      let improve = match dist.get(v) {
        Some(existing) => new_dist < existing
        None => true
      }
      if improve {
        /// invariant: whenever `dist[v] < infinity` becomes true, a concrete
        ///            walk `start ⇝ u → v` of total weight `new_dist` exists,
        ///            witnessed by `parents` chain set on the next line.
        ///            Anchor for M4 `moon prove` reachability lemma.
        dist[v] = new_dist
        parents[v] = u
        pq.push(new_dist, v)
      }
    }
  }
  None
}
