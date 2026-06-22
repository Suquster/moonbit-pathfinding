// 网格模型与端点编辑（grid.mbt）—— Playground 的可视化输入层（任务 25.1）。
//
// 设计依据：design.md §「方向 1 · 1.2 网格模型与端点编辑」。
//
// 核心设计决策（编辑即纯变换 · 值语义）：
//   * `Grid` 采用行优先线性存储，格子线性下标 `cell = row * cols + col`。
//   * 所有编辑操作（`set_start` / `set_goal` / `toggle_obstacle`）均为纯函数：
//     成功时返回一个 **全新的 `Grid`**（深拷贝 `blocked` 数组），失败时返回
//     `Err(@graph.PathError)` 且 **绝不改动入参 self**。这使「拒绝放置并恢复
//     到最后有效位置」成为调用方的纯逻辑（Requirement 2.3 / 2.5），亦便于
//     属性测试断言「非法编辑后状态不变」（任务 25.3 / Property 3）。
//   * 「可通行单元格」定义为：位于网格边界内（`0 <= cell < rows*cols`）且非
//     障碍的单元格（Requirement 2.1）。
//
// 错误类型选型（@graph.PathError）：依 design.md 接口草图，网格编辑的结构化
// 错误统一采用 `@graph.PathError`。越界 / 落在障碍上 / 与另一端点重叠 / 在端点
// 格上切障碍等「非法放置」均归入 `InvalidArgument(detail)` 变体，并以互异的
// 中文诊断细节区分原因（PathError 不含「单元格被占用」之类的专用变体，故以
// 携带细节的 InvalidArgument 表达，符合 R2.3 / 2.5 的「拒绝并反馈」语义）。

///|
/// 网格模型：行优先线性存储，格子线性下标 = `row * cols + col`。
///
/// 字段含义（design.md 数据模型表 · R2）：
/// - `rows` / `cols`：网格行数与列数，均为正整数。
/// - `blocked`：长度恒为 `rows * cols` 的布尔数组；`blocked[cell] == true`
///   表示该单元格为障碍（不可通行）。
/// - `start` / `goal`：起点与终点的线性下标，恒满足「在界内、非障碍、互异」。
///
/// 不变量（由 `new` 建立、由各编辑操作保持）：
///   I1. `0 <= start < rows*cols` 且 `blocked[start] == false`；
///   I2. `0 <= goal  < rows*cols` 且 `blocked[goal]  == false`；
///   I3. `start != goal`；
///   I4. `blocked.length() == rows * cols`。
///
/// 派生 `Eq` 以支持值相等比较（属性测试断言「状态不变」），派生 `Show` 以
/// 支持调试输出。
pub(all) struct Grid {
  rows : Int
  cols : Int
  blocked : Array[Bool]
  start : Int
  goal : Int
} derive(Eq, Show)

///|
/// 构造一个无障碍的合法网格：起点置于左上角（下标 0），终点置于右下角
/// （下标 `rows*cols - 1`），全部单元格初始可通行。
///
/// 合法性校验（失败返回 `Err(@graph.PathError::InvalidArgument)` 且不产出
/// 部分构造结果）：
/// - 行数或列数非正（`rows <= 0` 或 `cols <= 0`）→ 拒绝；
/// - 单元格总数不足 2（无法容纳互异的起点与终点，违反不变量 I3）→ 拒绝。
///
/// 成功时返回的 `Grid` 满足全部不变量 I1–I4。
pub fn Grid::new(rows : Int, cols : Int) -> Result[Grid, @graph.PathError] {
  if rows <= 0 || cols <= 0 {
    return Err(
      @graph.PathError::InvalidArgument(
        "网格行数与列数必须均为正整数",
      ),
    )
  }
  let total = rows * cols
  if total < 2 {
    return Err(
      @graph.PathError::InvalidArgument(
        "网格至少需要 2 个单元格以容纳互异的起点与终点",
      ),
    )
  }
  let blocked = Array::make(total, false)
  Ok({ rows, cols, blocked, start: 0, goal: total - 1 })
}

///|
/// 返回网格单元格总数，等于 `rows * cols`。
///
/// 该值同时是合法线性下标的上界：任意单元下标 `cell` 满足
/// `0 <= cell < cell_count()`。常用于编辑接口（`set_start` / `set_goal` /
/// `toggle_obstacle`）的越界校验，以及导出层 `pg_*` 的下标范围检查。
/// 纯查询，不修改网格状态。
pub fn Grid::cell_count(self : Grid) -> Int {
  self.rows * self.cols
}

///|
/// 判定 `cell` 是否为合法的界内下标（`0 <= cell < rows*cols`）。
fn Grid::in_bounds(self : Grid, cell : Int) -> Bool {
  cell >= 0 && cell < self.rows * self.cols
}

///|
/// 深拷贝 `blocked` 数组，保证编辑返回的新 `Grid` 与入参互不共享可变状态
/// （值语义的实现要点）。
fn Grid::clone_blocked(self : Grid) -> Array[Bool] {
  self.blocked.copy()
}

///|
/// 将起点移动到 `cell`，返回更新后的新网格（值语义）。
///
/// 非法放置一律返回 `Err` 且不改动入参（Requirement 2.3）：
/// - `cell` 越界 → `InvalidArgument`；
/// - `cell` 落在障碍上 → `InvalidArgument`；
/// - `cell` 与当前终点重叠 → `InvalidArgument`。
///
/// 成功时返回的网格保持全部不变量。
pub fn Grid::set_start(
  self : Grid,
  cell : Int,
) -> Result[Grid, @graph.PathError] {
  if not(self.in_bounds(cell)) {
    return Err(
      @graph.PathError::InvalidArgument(
        "起点目标单元格越界，无法放置",
      ),
    )
  }
  if self.blocked[cell] {
    return Err(
      @graph.PathError::InvalidArgument(
        "起点不能放置在障碍单元格上",
      ),
    )
  }
  if cell == self.goal {
    return Err(@graph.PathError::InvalidArgument("起点不能与终点重叠"))
  }
  Ok({
    rows: self.rows,
    cols: self.cols,
    blocked: self.clone_blocked(),
    start: cell,
    goal: self.goal,
  })
}

///|
/// 将终点移动到 `cell`，返回更新后的新网格（值语义）。
///
/// 非法放置一律返回 `Err` 且不改动入参（Requirement 2.3）：
/// - `cell` 越界 → `InvalidArgument`；
/// - `cell` 落在障碍上 → `InvalidArgument`；
/// - `cell` 与当前起点重叠 → `InvalidArgument`。
pub fn Grid::set_goal(
  self : Grid,
  cell : Int,
) -> Result[Grid, @graph.PathError] {
  if not(self.in_bounds(cell)) {
    return Err(
      @graph.PathError::InvalidArgument(
        "终点目标单元格越界，无法放置",
      ),
    )
  }
  if self.blocked[cell] {
    return Err(
      @graph.PathError::InvalidArgument(
        "终点不能放置在障碍单元格上",
      ),
    )
  }
  if cell == self.start {
    return Err(@graph.PathError::InvalidArgument("终点不能与起点重叠"))
  }
  Ok({
    rows: self.rows,
    cols: self.cols,
    blocked: self.clone_blocked(),
    start: self.start,
    goal: cell,
  })
}

///|
/// 切换 `cell` 的障碍状态（可通行↔障碍），返回更新后的新网格（值语义）。
///
/// 非法操作一律返回 `Err` 且不改动入参（Requirement 2.5）：
/// - `cell` 越界 → `InvalidArgument`；
/// - `cell` 为当前起点或终点（端点格切障碍）→ `InvalidArgument`。
///
/// 合法时：若该格原为可通行则置为障碍，反之置为可通行。由于起点/终点格被
/// 禁止切换，操作后不变量 I1/I2 仍成立。
pub fn Grid::toggle_obstacle(
  self : Grid,
  cell : Int,
) -> Result[Grid, @graph.PathError] {
  if not(self.in_bounds(cell)) {
    return Err(
      @graph.PathError::InvalidArgument("障碍切换目标单元格越界"),
    )
  }
  if cell == self.start || cell == self.goal {
    return Err(
      @graph.PathError::InvalidArgument(
        "不能在起点或终点单元格上切换障碍状态",
      ),
    )
  }
  let blocked = self.clone_blocked()
  blocked[cell] = not(blocked[cell])
  Ok({
    rows: self.rows,
    cols: self.cols,
    blocked,
    start: self.start,
    goal: self.goal,
  })
}

///|
/// 把网格转换为 4-邻接 successor 闭包（均匀单位权 1），供 `trace_search` 使用。
///
/// 对线性下标 `n`：先还原其 `(row, col)`，再按 **上、左、右、下** 顺序（亦即
/// 线性下标升序）枚举四个正交邻居；仅产出「界内且非障碍」的邻居，边权恒为
/// `1`。若 `n` 本身越界或为障碍，则返回空数组（不可通行单元格无出边）。
///
/// 闭包按值捕获 `rows` / `cols` 与（不可变的）`blocked` 数组，故对同一网格
/// 多次构造的 successor 行为一致、确定且可复现。
pub fn Grid::to_successors(self : Grid) -> (Int) -> Array[(Int, Int)] {
  let rows = self.rows
  let cols = self.cols
  let blocked = self.blocked
  let total = rows * cols
  fn passable(cell : Int) -> Bool {
    cell >= 0 && cell < total && not(blocked[cell])
  }

  fn(n : Int) -> Array[(Int, Int)] {
    if not(passable(n)) {
      return []
    }
    let row = n / cols
    let col = n % cols
    let result : Array[(Int, Int)] = []
    // 上邻居（row-1）：线性下标 n - cols。
    if row > 0 && passable(n - cols) {
      result.push((n - cols, 1))
    }
    // 左邻居（col-1）：线性下标 n - 1。
    if col > 0 && passable(n - 1) {
      result.push((n - 1, 1))
    }
    // 右邻居（col+1）：线性下标 n + 1。
    if col < cols - 1 && passable(n + 1) {
      result.push((n + 1, 1))
    }
    // 下邻居（row+1）：线性下标 n + cols。
    if row < rows - 1 && passable(n + cols) {
      result.push((n + cols, 1))
    }
    result
  }
}

///|
/// 网格曼哈顿距离启发式闭包（A\*/JPS 用）：返回从任意节点到 `goal` 的
/// `|Δrow| + |Δcol|`。
///
/// 该启发式在 4-邻接均匀单位权网格上是 **可采纳（admissible）且一致
/// （consistent）** 的，故 A\* 仍返回最短路径。闭包按值捕获 `cols` 与
/// `goal` 的行列分量，确定且可复现。
pub fn Grid::manhattan(self : Grid, goal : Int) -> (Int) -> Int {
  let cols = self.cols
  let goal_row = goal / cols
  let goal_col = goal % cols
  fn(n : Int) -> Int {
    let row = n / cols
    let col = n % cols
    (row - goal_row).abs() + (col - goal_col).abs()
  }
}
