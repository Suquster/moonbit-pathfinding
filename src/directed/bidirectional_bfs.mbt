// Bidirectional BFS: simultaneously expand from start and goal, meeting in
// the middle. Useful when both forward and backward successor functions are
// available — cuts the search space from O(b^d) to O(b^(d/2)).

///|
/// Bidirectional BFS between `start` and `goal`.
///
/// ## Parameters
/// - `start`: source node
/// - `goal`: target node
/// - `successors`: forward neighbors (edges u -> v)
/// - `predecessors`: backward neighbors (edges v -> u; needed for reverse BFS)
///
/// ## Returns
/// `Some(path)` from `start` to `goal`, or `None` if unreachable.
pub fn[N : Eq + Hash] bidirectional_bfs(
  start : N,
  goal : N,
  successors : (N) -> Array[N],
  predecessors : (N) -> Array[N],
) -> Array[N]? {
  if start == goal {
    return Some([start])
  }
  let fwd_parent : Map[N, N] = Map([])
  let bwd_parent : Map[N, N] = Map([])
  let fwd_visited : Map[N, Bool] = Map([])
  let bwd_visited : Map[N, Bool] = Map([])
  fwd_visited[start] = true
  bwd_visited[goal] = true
  let fwd_queue : Array[N] = [start]
  let bwd_queue : Array[N] = [goal]
  let mut fwd_head = 0
  let mut bwd_head = 0
  let mut meeting : N? = None
  //
  // 循环不变式（R10.1 · 双向 BFS 主循环 · 谓词见 @proofs.bidirectional_bfs_post）:
  //
  //   (布尔陈述) 两侧各自维持 BFS 不变式：fwd_visited 中每个节点都有从 start 出发的
  //       已知路径（由 fwd_parent 见证），bwd_visited 中每个节点都有到 goal 的已知
  //       路径（由 bwd_parent 见证）；meeting 为 None 当且仅当两侧已访问集尚无交点。
  //
  //   (初始化成立) 进入循环前 fwd_visited={start}、bwd_visited={goal}，两队列分别为
  //       [start]、[goal]，meeting=None：start⇝start、goal⇝goal 为平凡路径；若
  //       start≠goal（已在函数开头处理 ==），两集合无交点。
  //
  //   (迭代保持) 每轮扩展较小前沿一层：对未访问后继置 visited 与 parent 再入队，保持
  //       各侧路径见证；一旦某新节点同时落入对侧 visited，即记 meeting 并 break——此时
  //       start⇝m（fwd_parent）拼接 m⇝goal（bwd_parent）构成合法 start→goal 路径。
  //
  while fwd_head < fwd_queue.length() && bwd_head < bwd_queue.length() {
    // Expand the smaller frontier first (cheaper).
    if fwd_queue.length() - fwd_head <= bwd_queue.length() - bwd_head {
      let cur = fwd_queue[fwd_head]
      fwd_head += 1
      for next in successors(cur) {
        if fwd_visited.contains(next) {
          continue
        }
        fwd_visited[next] = true
        fwd_parent[next] = cur
        if bwd_visited.contains(next) {
          meeting = Some(next)
          break
        }
        fwd_queue.push(next)
      }
    } else {
      let cur = bwd_queue[bwd_head]
      bwd_head += 1
      for next in predecessors(cur) {
        if bwd_visited.contains(next) {
          continue
        }
        bwd_visited[next] = true
        bwd_parent[next] = cur
        if fwd_visited.contains(next) {
          meeting = Some(next)
          break
        }
        bwd_queue.push(next)
      }
    }
    if meeting is Some(_) {
      break
    }
  }
  match meeting {
    Some(m) => {
      // Reconstruct: start -> ... -> m via fwd_parent, then m -> ... -> goal via bwd_parent.
      let left : Array[N] = [m]
      let mut n = m
      while n != start {
        match fwd_parent.get(n) {
          Some(p) => {
            n = p
            left.push(n)
          }
          None => break
        }
      }
      left.rev_in_place()
      let mut n2 = m
      while n2 != goal {
        match bwd_parent.get(n2) {
          Some(p) => {
            n2 = p
            left.push(n2)
          }
          None => break
        }
      }
      Some(left)
    }
    None => None
  }
}
