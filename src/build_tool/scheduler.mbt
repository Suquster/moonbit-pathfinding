// scheduler.mbt —— 并行调度增强：关键路径与最小批次层数（旗舰深化，旁路新增）。
//
// paper-to-code（design.md §4.5 / §「算法说明」）：DAG **最长路径**（关键路径）
// 经**拓扑序动态规划**求解（Kahn 拓扑序上 `longest[v] = 1 + max(longest[u])`，
// O(V+E)）。对无环图，关键路径长度（节点数）恰等于不限并行度（`jobs <= 0`）下
// `schedule` 产出的批次层数——每层剥离入度为 0 节点对应一层关键路径推进，
// 故 `critical_path_length(g) == len(schedule(g, 0))`（正确性属性 12）。
//
// 既有 `schedule` 冻结复用（R13）：本文件**不改** `schedule`，仅新增关键路径
// 分析。`schedule` 的拓扑 / 批内独立 / 确定性 / jobs 约束四项不变量由属性测试
// （属性 8–11）固化。

///|
/// 关键路径长度：构建图最长依赖链的节点数。
///
/// 等于不限并行度（`jobs <= 0`）下完成构建所需的最小批次层数（R7.4）。环图
/// 无定义的关键路径，返回 0。
pub fn critical_path_length(g : BuildGraph) -> Int {
  match topo_order(g) {
    Err(_) => 0
    Ok(order) => {
      // 预建邻接表（source → 后继列表）一次，避免对每个节点都全扫描整个边集
      // （消除 O(V·E)，降为 O(V+E)）。
      let adj : Map[Target, Array[Target]] = Map([])
      for edge in g.edges {
        let (a, b) = edge
        let lst = adj.get(a).unwrap_or([])
        lst.push(b)
        adj[a] = lst
      }
      let longest : Map[Target, Int] = Map([])
      for n in g.nodes {
        longest[n] = 1
      }
      // 拓扑序保证前驱先于后继处理：对每条边 (u, v) 用 longest[u]+1 松弛 v。
      for u in order {
        let lu = longest.get(u).unwrap_or(1)
        for b in adj.get(u).unwrap_or([]) {
          let lb = longest.get(b).unwrap_or(1)
          if lu + 1 > lb {
            longest[b] = lu + 1
          }
        }
      }
      let mut maxv = 0
      for n in g.nodes {
        let l = longest.get(n).unwrap_or(1)
        if l > maxv {
          maxv = l
        }
      }
      maxv
    }
  }
}

///|
/// 不限并行度下完成构建所需的最小批次层数（= `critical_path_length`；对无环图
/// 等于 `len(schedule(g, 0))`，R7.4）。
pub fn min_layers(g : BuildGraph) -> Int {
  critical_path_length(g)
}

// ─────────────────── T6.2 关键路径优先列表调度 ────────────────────────

///|
/// 每个目标的「剩余关键路径长度」（downward rank）：`rank[v] = 1 +
/// max(rank[后继])`，无后继为 1。逆拓扑序动态规划，O(V+E)。环图返回空表。
fn remaining_rank(g : BuildGraph) -> Map[Target, Int] {
  let ranks : Map[Target, Int] = Map([])
  match topo_order(g) {
    Err(_) => ranks
    Ok(order) => {
      let adj : Map[Target, Array[Target]] = Map([])
      for edge in g.edges {
        let (a, b) = edge
        let lst = adj.get(a).unwrap_or([])
        lst.push(b)
        adj[a] = lst
      }
      // 逆拓扑序：后继先算，前驱取 1 + max。
      let mut i = order.length() - 1
      while i >= 0 {
        let u = order[i]
        let mut best = 0
        for v in adj.get(u).unwrap_or([]) {
          let rv = ranks.get(v).unwrap_or(1)
          if rv > best {
            best = rv
          }
        }
        ranks[u] = best + 1
        i = i - 1
      }
      ranks
    }
  }
}

///|
/// 关键路径优先列表调度（list scheduling with critical-path priority，
/// 对标 HLFET / Bazel 关键路径调度）：在 `jobs > 0` 并行度约束下，每一波
/// 从**全体就绪目标**中选剩余关键路径最长的至多 `jobs` 个执行——
/// 与 `schedule` 的「先分层、层内按原序切块」不同，本调度：
///   1. 波与波之间允许跨层混排（前一波释放的新就绪目标立即参与竞争）；
///   2. 同波内按 `remaining_rank` 降序（并列按图内原序）优先关键链。
/// 两者均保持拓扑不变量（任一目标严格晚于其全部依赖）；对单位时长任务，
/// 本调度的批次数（makespan）**不大于** `schedule` 且不小于
/// `critical_path_length`。`jobs <= 0` 时退化为整层一批（与 `schedule` 一致）。
/// 环图返回可调度前缀（与 `schedule` 同款语义）。
pub fn schedule_critical_path(
  g : BuildGraph,
  jobs : Int,
) -> Array[Array[Target]] {
  if jobs <= 0 {
    return schedule(g, 0)
  }
  let ranks = remaining_rank(g)
  let in_degree : Map[Target, Int] = Map([])
  for n in g.nodes {
    in_degree[n] = 0
  }
  let adj : Map[Target, Array[Target]] = Map([])
  let index_of : Map[Target, Int] = Map([])
  for i in 0..<g.nodes.length() {
    index_of[g.nodes[i]] = i
  }
  for edge in g.edges {
    let (u, v) = edge
    match in_degree.get(v) {
      Some(d) => {
        in_degree[v] = d + 1
        let lst = adj.get(u).unwrap_or([])
        lst.push(v)
        adj[u] = lst
      }
      None => ()
    }
  }
  // 就绪集以二叉堆维护优先序（rank 降序，并列按原序升序），push/pop 均
  // O(log R)，整体 O((V+E)·log V)——避免每波重排序的 O(R²) 热路径。
  let heap : Array[Target] = []
  fn less(a : Target, b : Target) -> Bool {
    // a 的优先级是否严格高于 b。
    let ra = ranks.get(a).unwrap_or(1)
    let rb = ranks.get(b).unwrap_or(1)
    if ra != rb {
      ra > rb
    } else {
      index_of.get(a).unwrap_or(0) < index_of.get(b).unwrap_or(0)
    }
  }

  fn heap_push(t : Target) -> Unit {
    heap.push(t)
    let mut i = heap.length() - 1
    while i > 0 {
      let parent = (i - 1) / 2
      if less(heap[i], heap[parent]) {
        let tmp = heap[parent]
        heap[parent] = heap[i]
        heap[i] = tmp
        i = parent
      } else {
        break
      }
    }
  }

  fn heap_pop() -> Target {
    let top = heap[0]
    let last = heap.unsafe_pop()
    if heap.length() > 0 {
      heap[0] = last
      let mut i = 0
      while true {
        let l = 2 * i + 1
        let r = 2 * i + 2
        let mut best = i
        if l < heap.length() && less(heap[l], heap[best]) {
          best = l
        }
        if r < heap.length() && less(heap[r], heap[best]) {
          best = r
        }
        if best == i {
          break
        }
        let tmp = heap[best]
        heap[best] = heap[i]
        heap[i] = tmp
        i = best
      }
    }
    top
  }

  for n in g.nodes {
    if in_degree.get(n).unwrap_or(0) == 0 {
      heap_push(n)
    }
  }
  let batches : Array[Array[Target]] = []
  while heap.length() > 0 {
    // 本波：弹出优先序最高的至多 jobs 个。
    let wave : Array[Target] = []
    while wave.length() < jobs && heap.length() > 0 {
      wave.push(heap_pop())
    }
    batches.push(wave)
    // 释放后继：本波完成后新就绪目标加入竞争。
    for n in wave {
      for v in adj.get(n).unwrap_or([]) {
        let d = in_degree.get(v).unwrap_or(0)
        in_degree[v] = d - 1
        if d - 1 == 0 {
          heap_push(v)
        }
      }
    }
  }
  batches
}
