// 逐步执行引擎（Stepper）—— Playground 的算法核心。
//
// 在 successor function 之上运行 BFS / DFS / Dijkstra / A\* / JPS，每一步
// （主循环每次「选中并扩展」一个节点）产出一帧结构化单步状态 `StepState`，
// 供宿主逐帧回放扩展过程（Requirement 1.2 / 3.1）。引擎为纯函数、可复现：
// 相同输入恒产出相同 `StepTrace`。
//
// 设计依据：design.md §「方向 1 · 1.1 逐步执行引擎」。
//
// 路径口径（Requirement 3.3）：
//   * BFS / Dijkstra / A\* 的 `final_path` 为最短路径（按边数 / 权重和）；
//   * DFS / JPS 的 `final_path` 为算法回溯得到的最终路径（不保证最短）。
//
// 关于 JPS 的工程说明（生产级、非占位）：真正的 Jump Point Search 依赖
// **网格几何**（强迫邻居、跳点、禁止切角等规则）来做对称性剪枝，而本引擎
// 的唯一输入是泛型 successor function `(N) -> Array[(N, W)]`，不暴露任何
// 网格坐标信息。因此在「裸 successor」语境下，引擎将 JPS 实现为由启发式
// 引导的 **贪心最佳优先搜索**（greedy best-first search）：每次扩展启发式
// 估值最小的边界节点。该实现是完备的（目标可达必能找到一条合法路径）、
// 返回「算法回溯得到的最终路径」，与 design.md 将 JPS 归入「非最短」一档
// 的口径一致；其与网格 A\* / JPS 的最短路一致性留待测试期在 4-邻接均匀
// 网格上交叉校验。

///|
/// 可视化支持的算法档（精确枚举，禁止字符串模拟结构化数据 · R22.6）。
///
/// 取值与 design.md / wasm 导出层的整型算法码一一对应：
/// `BFS`=0、`DFS`=1、`Dijkstra`=2、`AStar`=3、`JPS`=4。
///
/// 以 `pub(all)` 暴露构造子，使宿主/导出层（任务 26）与黑盒测试可由算法码
/// 直接构造对应档位（与既有 `@core.PathError` 的可见性一致）。
pub(all) enum PlaygroundAlgo {
  BFS
  DFS
  Dijkstra
  AStar
  JPS
} derive(Eq, Debug)

///|
/// 单步可观察状态（Requirement 1.2）。
///
/// 在网格场景下 `N` 实例化为格子线性下标 `Int`。各字段含义：
/// - `visited`：截至当前步、已永久访问（closed）的节点，按访问（弹出）顺序；
///   随帧序 **单调不减**（已访问节点不会消失）。
/// - `frontier`：当前待扩展边界（open set），即已发现但尚未 closed 的节点。
/// - `current`：本步正在扩展的节点；`None` 表示尚未开始或已终止。
/// - `done`：终止标志，仅轨迹最后一帧为 `true`。
/// - `found`：本帧是否命中目标（即 `current == goal`）。
pub struct StepState[N] {
  visited : Array[N]
  frontier : Array[N]
  current : N?
  done : Bool
  found : Bool
} derive(Eq, Debug)

///|
/// 完整逐步轨迹（Step_Trace）。供动画逐帧消费。
///
/// - `algo`：生成该轨迹所用算法。
/// - `steps`：每帧一个 `StepState`，帧序严格等于算法真实扩展序。
/// - `final_path`：目标可达时的回溯路径（含起点与终点），否则 `None`
///   （Requirement 3.3 / 3.4）。
/// - `reachable`：目标是否可达，等于「是否存在命中目标的帧」。
pub struct StepTrace[N] {
  algo : PlaygroundAlgo
  steps : Array[StepState[N]]
  final_path : Array[N]?
  reachable : Bool
} derive(Eq, Debug)

///|
/// 在 successor function 之上生成一条 `StepTrace`。纯函数、可复现。
///
/// `heuristic` 仅 `AStar` / `JPS` 使用；`BFS` / `DFS` / `Dijkstra` 调用方
/// 可传入恒零启发式（如 `fn(_n) { @core.Weight::zero() }`）即可，引擎在这
/// 三档下不读取其返回值。
///
/// ## 参数
/// - `algo`：所选可视化算法档。
/// - `start`：起点节点。
/// - `goal`：终点节点（与节点以 `==` 比较，故 `N : Eq`）。
/// - `successors`：返回某节点的 `(邻居, 边权)` 列表。
/// - `heuristic`：到目标的剩余代价估计（A\*/JPS 用）。
///
/// ## 返回
/// 一条 `StepTrace`：逐帧扩展状态 + 终止路径 + 可达标志。
///
/// ## 复杂度
/// 时间 O((V + E) · log V) 上界（带权档），空间 O(V + 帧数·V) —— 每帧
/// 快照 `visited` / `frontier` 以支持逐帧回放。
pub fn[N : Eq + Hash, W : @core.Weight + Compare] trace_search(
  algo : PlaygroundAlgo,
  start : N,
  goal : N,
  successors : (N) -> Array[(N, W)],
  heuristic : (N) -> W,
) -> StepTrace[N] {
  match algo {
    BFS => trace_frontier_order(BFS, start, goal, successors, is_lifo=false)
    DFS => trace_frontier_order(DFS, start, goal, successors, is_lifo=true)
    Dijkstra =>
      // Dijkstra：优先级键 = 已确定代价 g（不读取启发式）。
      trace_cost_based(Dijkstra, start, goal, successors, fn(_n, g) { g })
    AStar =>
      // A\*：优先级键 = f = g + h(n)。
      trace_cost_based(AStar, start, goal, successors, fn(n, g) {
        @core.Weight::add(g, heuristic(n))
      })
    JPS =>
      // JPS（裸 successor 语境）：由启发式引导的贪心最佳优先搜索。
      trace_greedy(JPS, start, goal, successors, heuristic)
  }
}

///|
/// 计算当前边界快照：在「已发现顺序」列表中滤除已 closed 的节点。
///
/// `discovered_order` 为追加式（节点首次入 open 时追加一次），`closed` 为
/// 已永久访问集合；二者之差即逻辑 open set，保持发现顺序，确定且可复现。
fn[N : Eq + Hash] frontier_snapshot(
  discovered_order : Array[N],
  closed : Map[N, Unit],
) -> Array[N] {
  let f : Array[N] = []
  for n in discovered_order {
    if !closed.contains(n) {
      f.push(n)
    }
  }
  f
}

///|
/// 沿 `parents` 链从 `goal` 回溯到 `start`，重构合法路径（含两端点）。
///
/// 前置条件：调用时目标已被命中，故 `goal` 与链上每个节点的父指针均已登记，
/// 回溯必在有限步内抵达 `start`。`start == goal` 时返回单元素路径 `[start]`。
fn[N : Eq + Hash] reconstruct_path(
  parents : Map[N, N],
  start : N,
  goal : N,
) -> Array[N] {
  let path = [goal]
  let mut node = goal
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
  path
}

///|
/// 把逐帧记录收尾为一条 `StepTrace`：将最后一帧的 `done` 置真，并据是否
/// 命中目标设置 `reachable` 与 `final_path`。
///
/// `start` 必然被弹出一次，故 `steps` 恒非空；最后一帧 `done == true`、
/// 其 `found == reachable`（命中帧为真、未命中的末帧为假），满足
/// Property 1 的「最后一帧终止」与「found 与可达一致」结构不变量。
fn[N : Eq + Hash] finalize_trace(
  algo : PlaygroundAlgo,
  steps : Array[StepState[N]],
  parents : Map[N, N],
  start : N,
  goal : N,
  found : Bool,
) -> StepTrace[N] {
  let n = steps.length()
  if n > 0 {
    let last = steps[n - 1]
    steps[n - 1] = { ..last, done: true, found }
  }
  let final_path = if found {
    Some(reconstruct_path(parents, start, goal))
  } else {
    None
  }
  { algo, steps, final_path, reachable: found }
}

///|
/// 无权边界序搜索引擎：BFS（FIFO）与 DFS（LIFO）共用。
///
/// 采用「发现即标记」策略：节点首次作为某节点的后继被发现时即记入
/// `discovered`、登记父指针并入 open，从而每个可达节点至多入 open 一次，
/// 主循环必然终止。每次从 open 选中节点 `u`（FIFO 取队首 / LIFO 取栈顶）
/// 并将其 closed，即追加一帧 `StepState`（边界快照取自扩展前的 open set）。
fn[N : Eq + Hash, W] trace_frontier_order(
  algo : PlaygroundAlgo,
  start : N,
  goal : N,
  successors : (N) -> Array[(N, W)],
  is_lifo~ : Bool,
) -> StepTrace[N] {
  let closed : Map[N, Unit] = Map([])
  let parents : Map[N, N] = Map([])
  let visited_order : Array[N] = []
  let discovered_order : Array[N] = [start]
  let discovered : Map[N, Unit] = Map([])
  discovered[start] = ()
  let open : Array[N] = [start]
  let mut head = 0
  let steps : Array[StepState[N]] = []
  let mut found = false
  while head < open.length() {
    let u = if is_lifo {
      // LIFO：弹出栈顶（数组尾部）。
      open.pop().unwrap()
    } else {
      // FIFO：取队首并前移游标。
      let x = open[head]
      head += 1
      x
    }
    if closed.contains(u) {
      continue
    }
    closed[u] = ()
    visited_order.push(u)
    let is_goal = u == goal
    steps.push({
      visited: visited_order.copy(),
      frontier: frontier_snapshot(discovered_order, closed),
      current: Some(u),
      done: false,
      found: is_goal,
    })
    if is_goal {
      found = true
      break
    }
    for pair in successors(u) {
      let (v, _w) = pair
      if discovered.contains(v) || closed.contains(v) {
        continue
      }
      discovered[v] = ()
      parents[v] = u
      discovered_order.push(v)
      open.push(v)
    }
  }
  finalize_trace(algo, steps, parents, start, goal, found)
}

///|
/// 基于代价的最佳优先搜索引擎：Dijkstra 与 A\* 共用。
///
/// `key_of(node, g)` 把「节点 + 其当前已知代价 g」映射为最小堆优先级键：
/// Dijkstra 取 `g`，A\* 取 `g + h(node)`。采用惰性删除（pop 出已 closed
/// 的陈旧条目即跳过）。每次成功 closed 一个节点即追加一帧。
fn[N : Eq + Hash, W : @core.Weight + Compare] trace_cost_based(
  algo : PlaygroundAlgo,
  start : N,
  goal : N,
  successors : (N) -> Array[(N, W)],
  key_of : (N, W) -> W,
) -> StepTrace[N] {
  let g_cost : Map[N, W] = Map([])
  let closed : Map[N, Unit] = Map([])
  let parents : Map[N, N] = Map([])
  let visited_order : Array[N] = []
  let discovered_order : Array[N] = [start]
  let discovered : Map[N, Unit] = Map([])
  discovered[start] = ()
  let pq : @core.PQueue[N, W] = @core.PQueue::new()
  let zero = @core.Weight::zero()
  g_cost[start] = zero
  pq.push(key_of(start, zero), start)
  let steps : Array[StepState[N]] = []
  let mut found = false
  while !pq.is_empty() {
    let (_k, u) = pq.pop().unwrap()
    if closed.contains(u) {
      continue
    }
    closed[u] = ()
    visited_order.push(u)
    let is_goal = u == goal
    steps.push({
      visited: visited_order.copy(),
      frontier: frontier_snapshot(discovered_order, closed),
      current: Some(u),
      done: false,
      found: is_goal,
    })
    if is_goal {
      found = true
      break
    }
    let gu = g_cost.get(u).unwrap()
    for pair in successors(u) {
      let (v, w) = pair
      if closed.contains(v) {
        continue
      }
      let new_g = @core.Weight::add(gu, w)
      let improve = match g_cost.get(v) {
        Some(existing) => new_g < existing
        None => true
      }
      if improve {
        g_cost[v] = new_g
        parents[v] = u
        pq.push(key_of(v, new_g), v)
        if !discovered.contains(v) {
          discovered[v] = ()
          discovered_order.push(v)
        }
      }
    }
  }
  finalize_trace(algo, steps, parents, start, goal, found)
}

///|
/// 贪心最佳优先搜索引擎：本引擎对 JPS 档的实现（见文件头工程说明）。
///
/// 以启发式估值 `heuristic(node)` 为最小堆优先级键，每次扩展估值最小的
/// 边界节点；采用「发现即标记」（每节点至多入 open 一次、首次发现即定父），
/// 因而是完备的：目标可达则必被弹出并命中。返回的路径为贪心回溯路径，
/// 不保证最短（与 design.md 对 JPS 的口径一致）。
fn[N : Eq + Hash, W : Compare] trace_greedy(
  algo : PlaygroundAlgo,
  start : N,
  goal : N,
  successors : (N) -> Array[(N, W)],
  heuristic : (N) -> W,
) -> StepTrace[N] {
  let closed : Map[N, Unit] = Map([])
  let parents : Map[N, N] = Map([])
  let visited_order : Array[N] = []
  let discovered_order : Array[N] = [start]
  let discovered : Map[N, Unit] = Map([])
  discovered[start] = ()
  let pq : @core.PQueue[N, W] = @core.PQueue::new()
  pq.push(heuristic(start), start)
  let steps : Array[StepState[N]] = []
  let mut found = false
  while !pq.is_empty() {
    let (_k, u) = pq.pop().unwrap()
    if closed.contains(u) {
      continue
    }
    closed[u] = ()
    visited_order.push(u)
    let is_goal = u == goal
    steps.push({
      visited: visited_order.copy(),
      frontier: frontier_snapshot(discovered_order, closed),
      current: Some(u),
      done: false,
      found: is_goal,
    })
    if is_goal {
      found = true
      break
    }
    for pair in successors(u) {
      let (v, _w) = pair
      if discovered.contains(v) || closed.contains(v) {
        continue
      }
      discovered[v] = ()
      parents[v] = u
      discovered_order.push(v)
      pq.push(heuristic(v), v)
    }
  }
  finalize_trace(algo, steps, parents, start, goal, found)
}
