// Feature: championship-v1-upgrade, Property 3: 非法编辑被拒绝且状态不变
//
// 本文件以属性测试（property-based test）校验网格编辑层 `grid.mbt` 的「非法
// 编辑被拒绝且入参网格不变」语义（design.md §「方向 1 · 1.2」/ Property 3 /
// Requirement 2.3、2.5）。形式化属性为：
//
//   *对任意* 合法网格与任一非法编辑操作，相应编辑函数返回 `Err(PathError)`
//   且 **绝不修改入参网格**。这里覆盖四类非法操作：
//     1. 越界：目标单元格线性下标 < 0 或 >= rows*cols；
//     2. 落在障碍：把起点 / 终点放到障碍单元格上；
//     3. 与另一端点重叠：把起点放到终点格、或把终点放到起点格；
//     4. 端点格切障碍：在起点或终点所在单元格上切换障碍状态。
//
// 「入参不变」的判定方式（关键）：在执行编辑前对入参网格做一份 **深拷贝快照**
// （独立复制 `blocked` 数组），编辑返回 `Err` 后再用派生的 `==` 比较入参与快照
// 是否逐字段相等。由于快照与入参互不共享可变状态，一旦编辑函数原地改动了入参
// 的 `blocked` 数组，该比较即会失败 —— 从而真正检验值语义而非自反真。
//
// 网格构造（保证落在合法不变量空间内）：以 `Grid::new` 建立无障碍合法网格，
// 再施加随机的 **合法** 编辑（合法移动起点 / 终点、在非端点格切换障碍）来引入
// 多样的障碍布局与端点位置；任何一步合法编辑失败则回退保持原网格。这样得到的
// 入参网格恒满足 grid.mbt 的不变量 I1–I4。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。迭代次数取 128（≥100 基线）。

///|
/// 单个随机用例：一张合法网格 + 一类待施加的非法编辑（由 `category` 选择，
/// `which` / `oob` 提供子选择与越界目标）。
struct P3Case {
  /// 满足全部不变量的合法入参网格。
  grid : Grid
  /// 非法操作类别：0 越界 / 1 落在障碍 / 2 与端点重叠 / 3 端点格切障碍。
  category : Int
  /// 子选择种子：用于在同类别内挑选具体操作（起点 / 终点）与具体障碍格。
  which : Int
  /// 越界目标线性下标（< 0 或 >= rows*cols），仅 `category == 0` 使用。
  oob : Int
}

///|
/// 随机用例生成器：先定网格规模 `R, C ∈ [2, 8]`，以 `Grid::new` 建立无障碍
/// 合法网格，再随机施加合法编辑（移动起点 / 终点、约 40% 概率在非端点格切障碍）
/// 来丰富布局；最后随机选取非法操作类别与子选择，并构造一个越界目标。
fn p3_gen() -> @infra_pbt.Gen[P3Case] {
  @infra_pbt.Gen::new(fn(rng) {
    let rows = rng.next_range(2, 8)
    let cols = rng.next_range(2, 8)
    let n = rows * cols
    let mut g = Grid::new(rows, cols).unwrap()
    // 随机合法移动起点（失败则保持原网格）。
    g = match g.set_start(rng.next_below(n)) {
      Ok(ng) => ng
      Err(_) => g
    }
    // 随机合法移动终点（失败则保持原网格）。
    g = match g.set_goal(rng.next_below(n)) {
      Ok(ng) => ng
      Err(_) => g
    }
    // 约 40% 概率在每个非端点格切换障碍，引入多样障碍布局。
    for cell in 0..<n {
      if cell != g.start && cell != g.goal && rng.next_below(10) < 4 {
        g = match g.toggle_obstacle(cell) {
          Ok(ng) => ng
          Err(_) => g
        }
      }
    }
    let category = rng.next_below(4)
    let which = rng.next_below(6)
    // 越界目标：等概率取「负向越界」或「上溢越界」。
    let oob = if rng.next_below(2) == 0 {
      -1 - rng.next_below(3)
    } else {
      n + rng.next_below(3)
    }
    P3Case::{ grid: g, category, which, oob }
  })
}

///|
/// 对入参网格做深拷贝快照（独立复制 `blocked` 数组），用于「编辑后状态不变」
/// 的比较基准。
fn p3_snapshot(g : Grid) -> Grid {
  Grid::{
    rows: g.rows,
    cols: g.cols,
    blocked: g.blocked.copy(),
    start: g.start,
    goal: g.goal,
  }
}

///|
/// 收集网格中全部障碍格的线性下标（用于类别 1：把端点放到障碍上）。
fn p3_blocked_cells(g : Grid) -> Array[Int] {
  let cells : Array[Int] = []
  for i in 0..<g.blocked.length() {
    if g.blocked[i] {
      cells.push(i)
    }
  }
  cells
}

///|
/// 依用例类别施加非法编辑，返回编辑结果（期望为 `Err`）。
///
/// 设计要点：类别 1（落在障碍）需要至少一个障碍格；若当前网格恰好无障碍，
/// 退化为类别 2（端点重叠）——该操作对任何合法网格恒非法（起点 ≠ 终点恒成立，
/// 故把一端放到另一端必越过「重叠」判定），保证本用例仍检验非法路径。
fn p3_apply_illegal(c : P3Case) -> Result[Grid, @graph.PathError] {
  let g = c.grid
  match c.category {
    // 类别 0：越界目标。三种编辑操作轮流施加，全部应被越界判定拒绝。
    0 =>
      match c.which % 3 {
        0 => g.set_start(c.oob)
        1 => g.set_goal(c.oob)
        _ => g.toggle_obstacle(c.oob)
      }
    // 类别 1：把起点 / 终点放到障碍格上。
    1 => {
      let blocked = p3_blocked_cells(g)
      if blocked.length() == 0 {
        // 无障碍可用 —— 退化为端点重叠（恒非法）。
        g.set_start(g.goal)
      } else {
        let cell = blocked[c.which % blocked.length()]
        if c.which % 2 == 0 {
          g.set_start(cell)
        } else {
          g.set_goal(cell)
        }
      }
    }
    // 类别 2：与另一端点重叠。
    2 =>
      if c.which % 2 == 0 {
        g.set_start(g.goal)
      } else {
        g.set_goal(g.start)
      }
    // 类别 3：在端点格上切换障碍。
    _ =>
      if c.which % 2 == 0 {
        g.toggle_obstacle(g.start)
      } else {
        g.toggle_obstacle(g.goal)
      }
  }
}

///|
/// 校验单个用例：施加非法编辑前先取入参快照，编辑后断言
/// (a) 返回 `Err`；(b) 入参网格与快照逐字段相等（未被原地修改）。
fn p3_check(c : P3Case) -> Bool {
  let before = p3_snapshot(c.grid)
  let result = p3_apply_illegal(c)
  // (a) 非法编辑必须被拒绝。
  guard result is Err(_) else { return false }
  // (b) 入参网格不得被修改（与编辑前的独立快照逐字段相等）。
  c.grid == before
}

///|
/// Feature: championship-v1-upgrade, Property 3: 非法编辑被拒绝且状态不变
///
/// 对任意合法网格与任一非法编辑操作（越界 / 落在障碍 / 与另一端点重叠 /
/// 在端点格切换障碍），相应编辑函数返回 `Err(PathError)` 且不修改入参网格
/// （编辑后入参与编辑前的深拷贝快照逐字段相等）。
///
/// 另以四个确定性锚点固定四类非法操作的典型形态（3×3 网格、起点 0、终点 8）：
///   * 越界：`set_start(9)` / `set_goal(-1)` / `toggle_obstacle(100)` 均 `Err`；
///   * 落在障碍：在下标 4 置障碍后 `set_start(4)` `Err`；
///   * 端点重叠：`set_start(8)`（终点）/ `set_goal(0)`（起点）均 `Err`；
///   * 端点切障碍：`toggle_obstacle(0)` / `toggle_obstacle(8)` 均 `Err`，
///     且以上每例均不改动入参网格。
///
/// **Validates: Requirements 2.3, 2.5**
test "Feature: championship-v1-upgrade, Property 3: illegal edits are rejected and leave the grid unchanged" {
  // 锚点：3×3 全通网格，起点 0、终点 8。
  let base = Grid::new(3, 3).unwrap()
  let snap = p3_snapshot(base)

  // 越界（三种操作）。
  assert_true(base.set_start(9) is Err(_))
  assert_true(base.set_goal(-1) is Err(_))
  assert_true(base.toggle_obstacle(100) is Err(_))
  // 端点重叠。
  assert_true(base.set_start(8) is Err(_))
  assert_true(base.set_goal(0) is Err(_))
  // 端点切障碍。
  assert_true(base.toggle_obstacle(0) is Err(_))
  assert_true(base.toggle_obstacle(8) is Err(_))
  // 以上非法操作均未改动入参网格。
  @test.assert_eq(base, snap)

  // 落在障碍：先在下标 4 合法置障碍，再尝试把起点放上去。
  let withobs = base.toggle_obstacle(4).unwrap()
  let withobs_snap = p3_snapshot(withobs)
  assert_true(withobs.set_start(4) is Err(_))
  assert_true(withobs.set_goal(4) is Err(_))
  @test.assert_eq(withobs, withobs_snap)

  // 属性：随机合法网格 × 四类非法操作上，恒「被拒且状态不变」。迭代 128 次。
  let ok = @infra_pbt.holds_for_all(p3_gen(), p3_check, iters=128)
  assert_true(ok)
}
