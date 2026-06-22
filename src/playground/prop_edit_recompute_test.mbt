// Feature: championship-v1-upgrade, Property 2: 合法端点/障碍编辑更新布局并据此重算
//
// 本文件以属性测试（property-based test）校验网格编辑操作（`set_start` /
// `set_goal` / `toggle_obstacle`）的「编辑即重算」契约（design.md §「方向 1 ·
// Property 2」/ Requirement 2.1、2.2、2.4）。形式化属性为：
//
//   *对任意* 网格与任一合法编辑（把起点 / 终点移动到某可通行目标格，或在某
//   非端点格切换障碍），编辑成功返回的 **新网格** 满足：
//     1. 对应字段已按编辑更新——`set_start` 后 `start == 目标格`；`set_goal`
//        后 `goal == 目标格`；`toggle_obstacle` 后 `blocked[目标格]` 取反；
//        且未被该编辑触及的字段（rows / cols / 另一端点 / 其余障碍位）保持不变；
//     2. 以新布局重算的 `StepTrace` 其 **起点帧对应新起点**——首帧
//        `current == Some(新起点)` 且 `visited == [新起点]`；
//     3. 当新终点可达时，回溯路径 `final_path` 的 **末节点等于新终点**
//        （首节点等于新起点）。
//
// 「合法编辑」由生成器在构造期保证：仅从「对该操作合法的目标格集合」中取样
// （见 `p2_legal_targets`），故 `Ok` 分支必然命中；任何 `Err` 都判失败。重算
// 在全部五种算法档（BFS / DFS / Dijkstra / A\* / JPS）上交叉验证，确保「编辑
// 后据新布局重算」的口径与所选算法无关。
//
// 网格模型复用任务 25.1 的生产实现 `@playground.Grid`：`Grid::new` 建立合法
// 初始网格，`set_start` / `set_goal` / `toggle_obstacle` 为纯变换（值语义），
// `to_successors` / `manhattan` 提供 4-邻接 successor 与曼哈顿启发，直接喂给
// 逐步执行引擎 `trace_search`。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。迭代次数取 128（≥100 基线）。
//
// **Validates: Requirements 2.1, 2.2, 2.4**

///|
/// 单个随机用例：一张随机化的合法网格 + 一次合法编辑（操作码 + 目标格）。
///
/// `op` 取值：`0` = `set_start`，`1` = `set_goal`，`2` = `toggle_obstacle`。
/// `target` 恒为对 `op` 合法的目标格（由生成器从合法集合中取样保证）。
struct P2Case {
  /// 随机化后的合法网格（满足 Grid 全部不变量）。
  grid : @playground.Grid
  /// 编辑操作码（0 = set_start，1 = set_goal，2 = toggle_obstacle）。
  op : Int
  /// 合法编辑目标格的线性下标。
  target : Int
}

///|
/// 收集对操作 `op` 合法的全部目标格线性下标。
///
/// - `set_start`（op=0）：界内、非障碍、且不与当前终点重叠的格（当前起点自身
///   恒满足，故集合非空）；
/// - `set_goal`（op=1）：界内、非障碍、且不与当前起点重叠的格（当前终点自身
///   恒满足，故集合非空）；
/// - `toggle_obstacle`（op=2）：界内、且既非起点也非终点的格（网格至少 2×2 =
///   4 格，故非端点格至少 2 个，集合非空）。
fn p2_legal_targets(grid : @playground.Grid, op : Int) -> Array[Int] {
  let total = grid.cell_count()
  let out : Array[Int] = []
  for cell in 0..<total {
    let legal = match op {
      0 => cell != grid.goal && !grid.blocked[cell]
      1 => cell != grid.start && !grid.blocked[cell]
      _ => cell != grid.start && cell != grid.goal
    }
    if legal {
      out.push(cell)
    }
  }
  out
}

///|
/// 随机用例生成器。
///
/// 构造步骤：
///   1. 取网格规模 `R, C ∈ [2, 8]`，以 `Grid::new` 建立合法初始网格；
///   2. 随机重定位起点与终点（仅在合法时采纳，保持互异与可通行不变量）；
///   3. 以约 25% 概率把非端点格切换为障碍（仅采纳合法切换）；
///   4. 随机选操作码 0..2，并从该操作的合法目标集合中随机取一个目标格。
///
/// 这样既覆盖「起点 / 终点位置任意」「障碍布局任意」的广泛输入空间，又保证
/// 每个用例的编辑都是 **合法** 的（落入 `Ok` 分支），从而专注校验 Property 2
/// 的「更新 + 重算」契约。
fn p2_gen() -> @infra_pbt.Gen[P2Case] {
  @infra_pbt.Gen::new(fn(rng) {
    let rows = rng.next_range(2, 8)
    let cols = rng.next_range(2, 8)
    let total = rows * cols
    let mut grid = @playground.Grid::new(rows, cols).unwrap()
    // 随机重定位起点：仅在目标格与当前终点互异时尝试，失败则保持原状。
    let s = rng.next_below(total)
    if s != grid.goal {
      match grid.set_start(s) {
        Ok(ng) => grid = ng
        Err(_) => ()
      }
    }
    // 随机重定位终点：仅在目标格与当前起点互异时尝试。
    let g = rng.next_below(total)
    if g != grid.start {
      match grid.set_goal(g) {
        Ok(ng) => grid = ng
        Err(_) => ()
      }
    }
    // 约 25% 概率把非端点格切换为障碍。
    for cell in 0..<total {
      if cell != grid.start && cell != grid.goal && rng.next_below(4) == 0 {
        match grid.toggle_obstacle(cell) {
          Ok(ng) => grid = ng
          Err(_) => ()
        }
      }
    }
    // 选操作码并从合法目标集合中取样（集合恒非空，见 p2_legal_targets）。
    let op = rng.next_below(3)
    let candidates = p2_legal_targets(grid, op)
    let target = candidates[rng.next_below(candidates.length())]
    P2Case::{ grid, op, target }
  })
}

///|
/// 校验编辑后「未被触及的字段保持不变」并返回新旧网格用于后续重算校验。
///
/// 对三种操作分别断言：
///   - `set_start`：`start == target`，`goal` / `blocked` / 规模不变；
///   - `set_goal`：`goal == target`，`start` / `blocked` / 规模不变；
///   - `toggle_obstacle`：`blocked[target]` 相对原值取反，且其余障碍位、
///     `start` / `goal` / 规模均不变（通过「把 target 翻回后整数组应相等」严格校验）。
fn p2_fields_updated(
  before : @playground.Grid,
  after : @playground.Grid,
  op : Int,
  target : Int,
) -> Bool {
  // 规模在任何编辑下都不应改变。
  if after.rows != before.rows || after.cols != before.cols {
    return false
  }
  match op {
    0 => {
      // set_start：起点更新为 target，其余不变。
      if after.start != target || after.goal != before.goal {
        return false
      }
      after.blocked == before.blocked
    }
    1 => {
      // set_goal：终点更新为 target，其余不变。
      if after.goal != target || after.start != before.start {
        return false
      }
      after.blocked == before.blocked
    }
    _ => {
      // toggle_obstacle：端点不变，target 处障碍位取反、其余障碍位不变。
      if after.start != before.start || after.goal != before.goal {
        return false
      }
      if after.blocked[target] != !before.blocked[target] {
        return false
      }
      // 严格校验「仅 target 改变」：把 target 翻回后应与原障碍数组逐位相等。
      let restored = after.blocked.copy()
      restored[target] = !restored[target]
      restored == before.blocked
    }
  }
}

///|
/// 在编辑后的新网格上重算 `StepTrace`，校验「起点帧对应新起点」与「可达时
/// final_path 末节点等于新终点」。覆盖全部五种算法档。
fn p2_recompute_ok(after : @playground.Grid) -> Bool {
  let succ = after.to_successors()
  let heur = after.manhattan(after.goal)
  let algos = [
    @playground.PlaygroundAlgo::BFS,
    @playground.PlaygroundAlgo::DFS,
    @playground.PlaygroundAlgo::Dijkstra,
    @playground.PlaygroundAlgo::AStar,
    @playground.PlaygroundAlgo::JPS,
  ]
  for algo in algos {
    let trace = @playground.trace_search(
      algo,
      after.start,
      after.goal,
      succ,
      heur,
    )
    let steps = trace.steps
    // 起点必被弹出一次，故轨迹恒非空。
    if steps.length() == 0 {
      return false
    }
    // 起点帧对应新起点：首帧 current == Some(新起点) 且 visited == [新起点]。
    if steps[0].current != Some(after.start) {
      return false
    }
    if steps[0].visited != [after.start] {
      return false
    }
    // 终点可达时：final_path 非空、首=新起点、末=新终点。
    if trace.reachable {
      match trace.final_path {
        Some(path) => {
          let len = path.length()
          if len == 0 {
            return false
          }
          if path[0] != after.start || path[len - 1] != after.goal {
            return false
          }
        }
        None => return false
      }
    }
  }
  true
}

///|
/// 校验单个用例：执行合法编辑 → 断言字段更新 → 断言据新布局重算的口径正确。
fn p2_check(case : P2Case) -> Bool {
  let before = case.grid
  let result = match case.op {
    0 => before.set_start(case.target)
    1 => before.set_goal(case.target)
    _ => before.toggle_obstacle(case.target)
  }
  match result {
    // 生成器只产出合法编辑，故 Err 即违背契约。
    Err(_) => false
    Ok(after) =>
      p2_fields_updated(before, after, case.op, case.target) &&
      p2_recompute_ok(after)
  }
}

///|
/// Feature: championship-v1-upgrade, Property 2: 对任意网格与任一可通行目标格，set_start/set_goal/toggle_obstacle 成功后返回的新网格其对应字段已更新，且以新布局生成的 StepTrace 起点帧对应新起点（终点可达时 final_path 末节点等于新终点）。
///
/// 另以三个确定性锚点固定典型形态：
///   * 锚点 A（set_start）：3×3 无障碍网格，把起点从 0 移到中心 4——新网格
///     `start == 4`、`goal` 不变，重算首帧即新起点，且可达时末节点为终点 8。
///   * 锚点 B（set_goal）：3×3 网格，把终点从 8 移到 4——新网格 `goal == 4`，
///     重算末节点为 4。
///   * 锚点 C（toggle_obstacle）：3×3 网格，在非端点格 1 切障碍——`blocked[1]`
///     置真、端点不变，重算首帧仍为起点 0。
///
/// **Validates: Requirements 2.1, 2.2, 2.4**
test "Feature: championship-v1-upgrade, Property 2: legal edit updates layout and recomputes" {
  // 锚点 A：set_start 把起点移到中心。
  let base = @playground.Grid::new(3, 3).unwrap()
  let case_a = P2Case::{ grid: base, op: 0, target: 4 }
  let after_a = base.set_start(4).unwrap()
  assert_eq(after_a.start, 4)
  assert_eq(after_a.goal, 8)
  assert_true(p2_check(case_a))

  // 锚点 B：set_goal 把终点移到中心。
  let case_b = P2Case::{ grid: base, op: 1, target: 4 }
  let after_b = base.set_goal(4).unwrap()
  assert_eq(after_b.goal, 4)
  assert_eq(after_b.start, 0)
  assert_true(p2_check(case_b))

  // 锚点 C：toggle_obstacle 在非端点格 1 切障碍。
  let case_c = P2Case::{ grid: base, op: 2, target: 1 }
  let after_c = base.toggle_obstacle(1).unwrap()
  assert_eq(after_c.blocked[1], true)
  assert_eq(after_c.start, 0)
  assert_eq(after_c.goal, 8)
  assert_true(p2_check(case_c))

  // 属性：随机网格 × 三种合法编辑 × 五种算法重算上，契约恒成立。迭代 128 次。
  let ok = @infra_pbt.holds_for_all(p2_gen(), p2_check, iters=128)
  assert_true(ok)
}
