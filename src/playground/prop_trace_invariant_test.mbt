// Feature: championship-v1-upgrade, Property 1: 逐步轨迹结构不变量
//
// 本文件以属性测试（property-based test）校验逐步执行引擎 `trace_search`
// 产出的 `StepTrace` 的结构不变量（design.md §「Property 1」/ Requirement
// 1.2、2.6）。形式化属性为：
//
//   *对任意* 网格、起点 / 终点与所选算法（BFS / DFS / Dijkstra / A\* / JPS），
//   `trace_search` 产出的 `StepTrace` 满足以下四条结构不变量：
//     1. 每帧 `StepState.current`（若非 None）属于网格的「自起点可达节点」
//        集合（即合法、可通行、且经 4-邻接从起点可达）；
//     2. `visited` 沿帧序 **单调不减**——前一帧的 `visited` 是后一帧的前缀
//        （已访问节点不会消失、不会被重排）；
//     3. 轨迹最后一帧 `done == true`，且仅最后一帧为 `true`（单点终止）；
//     4. 最后一帧 `found == reachable`，且 `reachable` 等于独立计算的
//        「终点是否自起点可达」的真值（口径自洽）。
//
// 网格模型在本测试内自洽构造（不依赖尚在并行开发的 `grid.mbt`）：以 R×C
// 网格的线性下标 `r*C + c` 为节点，successor 为 4-邻接可通行邻居（边权恒
// 为 1 的 Int），启发式取到终点的曼哈顿距离（Int）。`@core.Weight` 已为
// `Int` 提供实例，故权重类型直接取 `Int`。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。迭代次数取 128（≥100 基线），
// 每个用例随机选取五种算法之一，覆盖全部算法档。

///|
/// 单个随机用例：一张带障碍的 R×C 网格 + 起点 / 终点 + 所选算法。
///
/// 不变量：`start` 与 `goal` 恒为可通行格（生成时强制从障碍集合中剔除），
/// 故 successor 在起点处定义良好、`trace_search` 必有非空轨迹。
struct P1Case {
  /// 网格行数。
  rows : Int
  /// 网格列数。
  cols : Int
  /// 障碍格线性下标集合（不含起点 / 终点）。
  blocked : Map[Int, Unit]
  /// 起点线性下标（可通行）。
  start : Int
  /// 终点线性下标（可通行）。
  goal : Int
  /// 所选算法档。
  algo : PlaygroundAlgo
}

///|
/// 将算法码 0..4 映射为 `PlaygroundAlgo`（与 design.md / 导出层整型码一致）。
fn p1_algo_of(code : Int) -> PlaygroundAlgo {
  match code {
    0 => BFS
    1 => DFS
    2 => Dijkstra
    3 => AStar
    _ => JPS
  }
}

///|
/// 随机用例生成器：先定网格规模 `R, C ∈ [2, 8]`，再以约 30% 概率标记障碍，
/// 最后从全体格子中随机选起点 / 终点并强制其可通行，算法码取 0..4。
///
/// 设计要点：
///   * 障碍概率适中，使「可达」与「不可达」两类用例都能高频出现，从而同时
///     检验 `reachable == true` 与 `reachable == false` 两条分支。
///   * 起点 / 终点允许相等（覆盖「起点即终点」边界：轨迹仅一帧且即命中）。
fn p1_gen() -> @infra_pbt.Gen[P1Case] {
  @infra_pbt.Gen::new(fn(rng) {
    let rows = rng.next_range(2, 8)
    let cols = rng.next_range(2, 8)
    let n = rows * cols
    let start = rng.next_below(n)
    let goal = rng.next_below(n)
    let blocked : Map[Int, Unit] = Map([])
    for cell in 0..<n {
      // 约 30% 概率为障碍；起点 / 终点恒保持可通行。
      if cell != start && cell != goal && rng.next_below(10) < 3 {
        blocked[cell] = ()
      }
    }
    let algo = p1_algo_of(rng.next_below(5))
    P1Case::{ rows, cols, blocked, start, goal, algo }
  })
}

///|
/// 构造某用例的 successor function：返回 `cell` 的 4-邻接可通行邻居，边权恒 1。
///
/// 邻居以 上 / 下 / 左 / 右 固定顺序枚举，越界或落入障碍者剔除，保证确定性。
fn p1_successors(case : P1Case) -> (Int) -> Array[(Int, Int)] {
  fn(cell) {
    let r = cell / case.cols
    let c = cell % case.cols
    let out : Array[(Int, Int)] = []
    // 上
    if r > 0 {
      let nb = (r - 1) * case.cols + c
      if !case.blocked.contains(nb) {
        out.push((nb, 1))
      }
    }
    // 下
    if r < case.rows - 1 {
      let nb = (r + 1) * case.cols + c
      if !case.blocked.contains(nb) {
        out.push((nb, 1))
      }
    }
    // 左
    if c > 0 {
      let nb = r * case.cols + (c - 1)
      if !case.blocked.contains(nb) {
        out.push((nb, 1))
      }
    }
    // 右
    if c < case.cols - 1 {
      let nb = r * case.cols + (c + 1)
      if !case.blocked.contains(nb) {
        out.push((nb, 1))
      }
    }
    out
  }
}

///|
/// 到终点的曼哈顿距离启发式（Int，A\* / JPS 用；对 4-邻接均匀网格可采纳）。
fn p1_heuristic(case : P1Case) -> (Int) -> Int {
  fn(cell) {
    let r = cell / case.cols
    let c = cell % case.cols
    let gr = case.goal / case.cols
    let gc = case.goal % case.cols
    let dr = if r >= gr { r - gr } else { gr - r }
    let dc = if c >= gc { c - gc } else { gc - c }
    dr + dc
  }
}

///|
/// 独立参考实现：以 BFS 计算「自起点可达」的全部格子集合（地面真值）。
///
/// 与被测引擎解耦（裸队列遍历、不调用 `trace_search`），用于交叉校验
/// 「current 属于可达节点」与「reachable 真值」两条不变量。
fn p1_reachable_set(case : P1Case) -> Map[Int, Unit] {
  let succ = p1_successors(case)
  let seen : Map[Int, Unit] = Map([])
  let queue : Array[Int] = [case.start]
  seen[case.start] = ()
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head = head + 1
    for pair in succ(u) {
      let (v, _w) = pair
      if !seen.contains(v) {
        seen[v] = ()
        queue.push(v)
      }
    }
  }
  seen
}

///|
/// 校验单个用例：运行 `trace_search` 并逐条验证 Property 1 的四类结构不变量。
fn p1_check(case : P1Case) -> Bool {
  let succ = p1_successors(case)
  let heur = p1_heuristic(case)
  let trace = trace_search(case.algo, case.start, case.goal, succ, heur)
  let steps = trace.steps
  // 起点必被弹出一次，故轨迹恒非空。
  if steps.length() == 0 {
    return false
  }
  let reachable_set = p1_reachable_set(case)

  // 不变量 1 & 2：逐帧检查 current 可达、visited 单调不减（前缀关系）。
  let mut prev_visited : Array[Int] = []
  for i in 0..<steps.length() {
    let frame = steps[i]
    // (1) current（若非 None）须属于自起点可达节点集合。
    match frame.current {
      Some(c) => if !reachable_set.contains(c) { return false }
      None => ()
    }
    // (2) 前一帧 visited 必为本帧 visited 的前缀：长度不减且共享前缀逐元素相等。
    let cur_visited = frame.visited
    if cur_visited.length() < prev_visited.length() {
      return false
    }
    for j in 0..<prev_visited.length() {
      if prev_visited[j] != cur_visited[j] {
        return false
      }
    }
    prev_visited = cur_visited
  }

  // 不变量 3：仅最后一帧 done == true。
  for i in 0..<steps.length() {
    let is_last = i == steps.length() - 1
    if steps[i].done != is_last {
      return false
    }
  }

  // 不变量 4：最后一帧 found == reachable，且 reachable 等于地面真值。
  let last = steps[steps.length() - 1]
  if last.found != trace.reachable {
    return false
  }
  let truth = reachable_set.contains(case.goal)
  if trace.reachable != truth {
    return false
  }
  true
}

///|
/// Feature: championship-v1-upgrade, Property 1: 逐步轨迹结构不变量
///
/// 对任意网格、起点 / 终点与所选算法，`trace_search` 产出的 `StepTrace`
/// 满足：每帧 `current`（若非 None）属于自起点可达节点；`visited` 沿帧序
/// 单调不减（前缀关系）；仅最后一帧 `done == true`；最后一帧
/// `found == reachable`，且 `reachable` 等于独立 BFS 计算的终点可达真值。
///
/// 另以两个确定性锚点固定典型形态：
///   * 锚点 A（可达）：3×3 无障碍网格、起点 0、终点 8，BFS 必命中——末帧
///     `done && found && reachable`，且首帧仅含起点。
///   * 锚点 B（不可达）：3×3 网格、用障碍把终点完全围死——末帧 `done`、
///     `!found && !reachable`。
///
/// **Validates: Requirements 1.2, 2.6**
test "Feature: championship-v1-upgrade, Property 1: step trace structural invariants" {
  // 锚点 A：3×3 无障碍，起点 0、终点 8，A\* 必可达。
  let case_a = P1Case::{
    rows: 3,
    cols: 3,
    blocked: Map([]),
    start: 0,
    goal: 8,
    algo: AStar,
  }
  let trace_a = trace_search(
    case_a.algo,
    case_a.start,
    case_a.goal,
    p1_successors(case_a),
    p1_heuristic(case_a),
  )
  assert_true(trace_a.reachable)
  let steps_a = trace_a.steps
  assert_true(steps_a.length() > 0)
  // 首帧 visited 仅含起点。
  assert_eq(steps_a[0].visited, [0])
  // 末帧终止且命中。
  let last_a = steps_a[steps_a.length() - 1]
  assert_true(last_a.done)
  assert_true(last_a.found)
  assert_true(p1_check(case_a))

  // 锚点 B：3×3，用障碍 {5, 7} 把终点 8 的两个邻居封死 → 8 不可达。
  let blocked_b : Map[Int, Unit] = Map([])
  blocked_b[5] = ()
  blocked_b[7] = ()
  let case_b = P1Case::{
    rows: 3,
    cols: 3,
    blocked: blocked_b,
    start: 0,
    goal: 8,
    algo: BFS,
  }
  let trace_b = trace_search(
    case_b.algo,
    case_b.start,
    case_b.goal,
    p1_successors(case_b),
    p1_heuristic(case_b),
  )
  assert_true(!trace_b.reachable)
  let last_b = trace_b.steps[trace_b.steps.length() - 1]
  assert_true(last_b.done)
  assert_true(!last_b.found)
  assert_true(p1_check(case_b))

  // 属性：随机网格 × 五种算法上，四类结构不变量恒成立。迭代 128 次。
  let ok = @infra_pbt.holds_for_all(p1_gen(), p1_check, iters=128)
  assert_true(ok)
}
