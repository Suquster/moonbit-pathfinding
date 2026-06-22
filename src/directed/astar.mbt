// A* search with an admissible heuristic.
//
// Reference: Hart, P. E., Nilsson, N. J., & Raphael, B. (1968).
// "A Formal Basis for the Heuristic Determination of Minimum Cost Paths".
// IEEE Transactions on Systems Science and Cybernetics, 4(2), 100-107.

///|
/// A* shortest path from `start` to the first node satisfying `goal`,
/// using a priority queue keyed by `f(n) = g(n) + h(n)` where:
/// - `g(n)` is the known cost from `start` to `n`
/// - `h(n)` is a user-supplied heuristic estimate of remaining cost
///
/// ## Correctness
/// If `heuristic` is admissible (never overestimates), A* returns an optimal
/// path — see Hart et al. 1968 Theorem 1.
/// When `heuristic` returns `zero()` for every node, A* degenerates to
/// Dijkstra's algorithm.
///
/// ## Parameters
/// - `start`: starting node
/// - `successors`: function returning `(neighbor, edge_weight)` pairs
/// - `heuristic`: admissible estimate of remaining cost to goal
/// - `goal`: predicate testing whether a node is the target
///
/// ## Returns
/// `Some((path, total_cost))` if reachable, `None` otherwise.
///
/// ## Complexity
/// Time: O((V + E) log V) worst case; often much better with a good heuristic.
///
/// ## ASCII 示意（5×5 网格，启发式引导）
/// A* 以 `f(n) = g(n) + h(n)` 引导搜索朝终点 `G` 方向优先扩展。下图 `*`
/// 标出一条受启发式牵引、近似阶梯走向终点的最优路径：
///
///     S*...
///     .**..
///     ..**.
///     ...**
///     ....G
///
/// 图例：S=起点 G=终点 #=障碍 *=路径 .=空闲
pub fn[N : Eq + Hash, W : @core.Weight + Compare] astar(
  start : N,
  successors : (N) -> Array[(N, W)],
  heuristic : (N) -> W,
  goal : (N) -> Bool,
) -> (Array[N], W)? {
  let g_cost : Map[N, W] = Map([])
  let parents : Map[N, N] = Map([])
  // The queue payload carries the `g` value recorded when the entry was
  // pushed, so we can perform lazy deletion of superseded (stale) entries on
  // pop — avoiding redundant node re-expansions. This is the standard
  // duplicate-detection technique used by production A* implementations and
  // is correct for both consistent and merely-admissible heuristics.
  let pq : @core.PQueue[(N, W), W] = @core.PQueue::new()
  let zero = @core.Weight::zero()
  g_cost[start] = zero
  pq.push(heuristic(start), (start, zero))
  //
  // 循环不变式（R10.1 · A* 主循环 · 谓词见 @proofs.astar_post / dijkstra_pop_monotonic）:
  //
  //   (布尔陈述) f 值下界单调 + g 最优见证：在 heuristic 可采纳（不高估）前提下，
  //       连续两次「非陈旧」弹出的 f = g + h 键单调非降；且对任意 g_cost[v] 有限的
  //       节点 v，存在一条从 start 到 v、总权恰为 g_cost[v] 的实际游走（由 parents
  //       链见证）。
  //
  //   (初始化成立) 进入循环前仅 (heuristic(start), (start, zero)) 入队，g_cost[start]
  //       = zero：单元素序列单调非降平凡成立；start 自身即长度为 0 的平凡见证游走。
  //
  //   (迭代保持) 最小堆每次弹出当前最小 f 键；可采纳启发式保证后续松弛产生的
  //       f' = (g+w) + h(v) 不会使「非陈旧弹出」键下降。松弛仅在 tentative < 现有
  //       g_cost[v] 时更新 g_cost[v]、parents[v]，从而新的有限 g_cost[v] 仍由
  //       start ⇝ u → v 的具体游走见证。陈旧条目（gu_entry > best）被 continue
  //       跳过，不破坏单调性。
  //
  while !pq.is_empty() {
    let (_f, (u, gu_entry)) = pq.pop().unwrap()
    // Skip stale entries: if a strictly better path to `u` was discovered
    // after this entry was queued, the recorded `g` is worse than the current
    // best and this expansion would be wasted work.
    match g_cost.get(u) {
      Some(best) => if gu_entry > best { continue }
      None => continue
    }
    if goal(u) {
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
      let total = g_cost.get(u).unwrap()
      return Some((path, total))
    }
    let gu = gu_entry
    for pair in successors(u) {
      let (v, w) = pair
      let tentative = @core.Weight::add(gu, w)
      let improve = match g_cost.get(v) {
        Some(existing) => tentative < existing
        None => true
      }
      if improve {
        g_cost[v] = tentative
        parents[v] = u
        let f = @core.Weight::add(tentative, heuristic(v))
        pq.push(f, (v, tentative))
      }
    }
  }
  None
}
