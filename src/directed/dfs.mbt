// Depth-First Search on a directed graph (non-recursive, explicit stack).
//
// Uses an iterative stack-based implementation to avoid potential stack
// overflows on deep graphs (MoonBit's default stack depth is limited).

///|
/// DFS path from `start` to any node satisfying `goal`.
///
/// Returns `Some(path)` where `path` includes both endpoints, or `None` if
/// no path exists. The path is not guaranteed to be the shortest — DFS
/// prioritizes depth. For shortest-path semantics on unweighted graphs, use
/// `@unweighted.bfs` instead.
///
/// ## Parameters
/// - `start`: starting node
/// - `successors`: function returning neighbors of a node
/// - `goal`: predicate testing whether a node is the target
///
/// ## Complexity
/// Time: O(V + E). Space: O(V) for the explicit stack.
///
/// ## ASCII 示意（4×4 网格，深度优先路径）
/// DFS 沿一条分支一路深入，找到的路径不保证最短。下图 `*` 标出一条
/// 「先纵深、后折返」的可行路径，直观体现 DFS 偏好深度而非最短：
///
///     S..#
///     **.#
///     .*.#
///     .**G
///
/// 图例：S=起点 G=终点 #=障碍 *=路径 .=空闲
/// 若需无权图最短路径，请改用 `@unweighted.bfs`。
pub fn[N : Eq + Hash] dfs(
  start : N,
  successors : (N) -> Array[N],
  goal : (N) -> Bool,
) -> Array[N]? {
  if goal(start) {
    return Some([start])
  }
  // Stack entries are (node, parent_index_in_path_so_far).
  // We track parents via a Map to reconstruct the path on success.
  let stack : Array[N] = [start]
  let parents : Map[N, N] = Map([])
  let visited : Map[N, Bool] = Map([])
  visited[start] = true
  //
  // 循环不变式（R10.1 · DFS 主循环 · 谓词见 @proofs.is_valid_path / is_reachable）:
  //
  //   (布尔陈述) 栈-visited 一致性与父指针良构：
  //       forall n in stack, visited.contains(n) == true，且对任意 parents[n]=p
  //       有 visited.contains(p) == true（p 先于 n 被发现）。由此沿 parents 回溯
  //       必然在有限步内抵达 start，重构路径合法且不成环。
  //
  //   (初始化成立) 进入循环前 stack = [start]，visited 仅含 start，parents 为空：
  //       栈中唯一元素 start 已在 visited 中；父指针集合为空，良构平凡成立。
  //
  //   (迭代保持) 每次弹出 cur 后，仅对未访问的后继 next 置 visited[next]=true、
  //       parents[next]=cur 再压栈：next 入栈即已在 visited 中（保持一致性），
  //       其父 cur 此前已被发现（保持良构）。已访问后继被 continue 跳过，故每个
  //       可达节点至多入栈一次，循环必然终止。
  //
  while stack.length() > 0 {
    let cur = stack.pop().unwrap()
    for next in successors(cur) {
      if visited.contains(next) {
        continue
      }
      visited[next] = true
      parents[next] = cur
      if goal(next) {
        // Reconstruct path by walking parents back to start.
        let path = [next]
        let mut node = next
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
        return Some(path)
      }
      stack.push(next)
    }
  }
  None
}
