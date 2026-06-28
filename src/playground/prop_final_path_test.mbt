// Property 4「终止路径合法性与可达一致性」属性测试（任务 24.3）。
//
// 在随机 4-邻接网格上，以 successor function 驱动逐步执行引擎 `trace_search`，
// 校验其终止口径（`StepTrace.final_path` 与 `StepTrace.reachable`）满足
// design.md §「方向 1 · Property 4」的全称约束：
//   * 目标可达时：`final_path` 为合法路径——非空、首节点=起点、末节点=终点、
//     每相邻对为 4-邻接边（曼哈顿距离恰为 1）；
//   * 目标不可达时：`final_path == None` 且 `reachable == false`。
//
// 「是否可达」由本测试在网格上自跑一遍参考 BFS 求得真值，再与引擎输出交叉
// 校验；五种算法档（BFS/DFS/Dijkstra/A\*/JPS）均为完备搜索，故对同一网格的
// 可达判定必与参考 BFS 一致，且可达时各自回溯出的路径都应合法。
//
// 复用共享 PBT 包 @infra_pbt 的 Gen / Rng / holds_for_all 模板（默认迭代
// 100 次，满足 Requirement 11.3「每条属性 ≥100 次迭代」基线）。
//
// **Validates: Requirements 3.3, 3.4**

///|
/// 随机网格用例：`rows × cols` 的 4-邻接栅格 + 障碍位图 + 起点/终点。
///
/// `blocked[r * cols + c]` 为真表示该格不可通行；起点 `start` 与终点 `goal`
/// 以线性下标表示，构造时保证二者所在格均不被障碍占据。
struct GridCase {
  rows : Int
  cols : Int
  blocked : Array[Bool]
  start : Int
  goal : Int
}

///|
/// 生成随机网格用例：尺寸 `[2,6] × [2,6]`，每格约 30% 概率为障碍，起点/终点
/// 在格集内随机取并强制清除其障碍标记（保证起点可出发、终点可作为目标）。
///
/// 约 30% 的障碍密度使「可达 / 不可达」两种情形都能以可观比例被采样到，从而
/// 同时覆盖 Property 4 的两个分支（Requirements 3.3 与 3.4）。
fn gen_grid_case() -> @infra_pbt.Gen[GridCase] {
  @infra_pbt.Gen::new(fn(rng) {
    let rows = rng.next_range(2, 6)
    let cols = rng.next_range(2, 6)
    let n = rows * cols
    let blocked = Array::make(n, false)
    for i in 0..<n {
      // 每格独立约 30% 概率设为障碍。
      blocked[i] = rng.next_below(10) < 3
    }
    let start = rng.next_below(n)
    let goal = rng.next_below(n)
    // 端点格必须可通行：清除其障碍标记。
    blocked[start] = false
    blocked[goal] = false
    { rows, cols, blocked, start, goal }
  })
}

///|
/// 构造网格的 4-邻接 successor function：对线性下标 `node`，返回上/下/左/右
/// 四个在界内且未被障碍占据的邻格，边权恒为 1。
fn grid_successors(grid : GridCase) -> (Int) -> Array[(Int, Int)] {
  fn(node) {
    let out : Array[(Int, Int)] = []
    if node < 0 || node >= grid.rows * grid.cols {
      return out
    }
    let r = node / grid.cols
    let c = node % grid.cols
    // 上邻。
    if r > 0 && !grid.blocked[node - grid.cols] {
      out.push((node - grid.cols, 1))
    }
    // 下邻。
    if r < grid.rows - 1 && !grid.blocked[node + grid.cols] {
      out.push((node + grid.cols, 1))
    }
    // 左邻。
    if c > 0 && !grid.blocked[node - 1] {
      out.push((node - 1, 1))
    }
    // 右邻。
    if c < grid.cols - 1 && !grid.blocked[node + 1] {
      out.push((node + 1, 1))
    }
    out
  }
}

///|
/// 曼哈顿距离启发式（A\*/JPS 用）：到终点的 |Δrow| + |Δcol|，在 4-邻接均匀
/// 网格上可采纳（admissible）。
fn manhattan_to(grid : GridCase) -> (Int) -> Int {
  let gr = grid.goal / grid.cols
  let gc = grid.goal % grid.cols
  fn(node) {
    let r = node / grid.cols
    let c = node % grid.cols
    (r - gr).abs() + (c - gc).abs()
  }
}

///|
/// 参考 BFS：在网格上从 `start` 求是否能抵达 `goal`，作为「可达性」真值。
/// 不依赖被测引擎，纯粹基于 successor 邻接关系，故可独立交叉校验。
fn grid_reachable(grid : GridCase) -> Bool {
  let n = grid.rows * grid.cols
  let succ = grid_successors(grid)
  let seen = Array::make(n, false)
  seen[grid.start] = true
  let queue : Array[Int] = [grid.start]
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head += 1
    if u == grid.goal {
      return true
    }
    for pair in succ(u) {
      let (v, _w) = pair
      if !seen[v] {
        seen[v] = true
        queue.push(v)
      }
    }
  }
  grid.start == grid.goal
}

///|
/// 判定两个线性下标在网格上是否为 4-邻接（曼哈顿距离恰为 1）。
fn cells_adjacent(a : Int, b : Int, cols : Int) -> Bool {
  let ra = a / cols
  let ca = a % cols
  let rb = b / cols
  let cb = b % cols
  (ra - rb).abs() + (ca - cb).abs() == 1
}

///|
/// 校验一条 `final_path` 在给定网格上对给定起/终点合法：
/// 非空、首=起点、末=终点、相邻对均为 4-邻接边、且路径上每格均不被障碍占据。
fn path_is_legal(grid : GridCase, path : Array[Int]) -> Bool {
  let len = path.length()
  if len == 0 {
    return false
  }
  if path[0] != grid.start || path[len - 1] != grid.goal {
    return false
  }
  for i in 0..<len {
    let node = path[i]
    if node < 0 || node >= grid.rows * grid.cols || grid.blocked[node] {
      return false
    }
    if i > 0 && !cells_adjacent(path[i - 1], node, grid.cols) {
      return false
    }
  }
  true
}

///|
/// 对单个算法档运行 `trace_search` 并校验 Property 4 的两个分支。
fn check_property4(
  grid : GridCase,
  algo : @playground.PlaygroundAlgo,
  reachable : Bool,
) -> Bool {
  let trace = @playground.trace_search(
    algo,
    grid.start,
    grid.goal,
    grid_successors(grid),
    manhattan_to(grid),
  )
  if reachable {
    // 可达分支（Requirement 3.3）：引擎须报告可达，且回溯出合法路径。
    if !trace.reachable {
      return false
    }
    match trace.final_path {
      Some(path) => path_is_legal(grid, path)
      None => false
    }
  } else {
    // 不可达分支（Requirement 3.4）：final_path == None 且 reachable == false。
    trace.final_path is None && trace.reachable == false
  }
}

///|
/// Feature: championship-v1-upgrade, Property 4: 对任意网格，当目标可达时 final_path 为合法路径（非空、首=起点、末=终点、每相邻对为 4-邻接边）；当目标不可达时 final_path == None 且 reachable == false。
///
/// **Validates: Requirements 3.3, 3.4**
test "Feature: championship-v1-upgrade, Property 4: final path legality and reachability consistency (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(gen_grid_case(), fn(grid) {
    // 以参考 BFS 求可达真值，再要求五种算法档对该网格的终止口径全部满足 Property 4。
    let reachable = grid_reachable(grid)
    let algos = [
      @playground.PlaygroundAlgo::BFS,
      @playground.PlaygroundAlgo::DFS,
      @playground.PlaygroundAlgo::Dijkstra,
      @playground.PlaygroundAlgo::AStar,
      @playground.PlaygroundAlgo::JPS,
    ]
    for algo in algos {
      if !check_property4(grid, algo, reachable) {
        return false
      }
    }
    true
  })
  assert_true(ok)
}

///|
/// 示例单元测试：一个无障碍 3×3 网格，目标可达，BFS 终止路径合法。
/// 作为属性测试的具体锚点（可读性 + 回归保护）。
test "Property 4 示例：3×3 无障碍网格 BFS 终止路径合法" {
  let grid = GridCase::{
    rows: 3,
    cols: 3,
    blocked: Array::make(9, false),
    start: 0,
    goal: 8,
  }
  @test.assert_eq(grid_reachable(grid), true)
  assert_true(check_property4(grid, @playground.PlaygroundAlgo::BFS, true))
}

///|
/// 示例单元测试：一行被障碍完全隔断的网格，目标不可达，应满足
/// `final_path == None` 且 `reachable == false`（Requirement 3.4）。
test "Property 4 示例：障碍隔断时目标不可达" {
  // 2×3 网格，中间一整列（下标 1、4）设障碍，将起点 0 与终点 2 隔开。
  // 列布局：行0 = [0,1,2]，行1 = [3,4,5]；阻断下标 1 与 4 后，0 仅能到 3，
  // 而 2 仅能到 5，二者互不连通。
  let blocked = Array::make(6, false)
  blocked[1] = true
  blocked[4] = true
  let grid = GridCase::{ rows: 2, cols: 3, blocked, start: 0, goal: 2 }
  @test.assert_eq(grid_reachable(grid), false)
  assert_true(
    check_property4(grid, @playground.PlaygroundAlgo::Dijkstra, false),
  )
}
