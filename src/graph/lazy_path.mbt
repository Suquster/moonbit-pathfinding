// lazy_path.mbt —— 惰性路径迭代器 `LazyPath[N]`（按需逐个产出路径节点）。
//
// 设计依据（design.md §「方向 4 · 4.3 Lazy_Path_Iterator」/ Requirement 14）：
//   面向内存受限环境：调用方已持有单条路径（`Array[N]`），迭代器只在其上
//   维护一个 O(1) 游标 `pos`，按需逐个产出节点，而不复制路径、也不物化
//   多于一条候选路径（Requirement 14.5）。
//
// 关键不变量：
//   * Requirement 14.1：`next()` 逐个产出下一个节点，或在耗尽时返回不含
//     任何节点的终止值 `None`。
//   * Requirement 14.2：仍有未产出节点时，`next()` 产出下一个节点并将游标
//     前移一位。
//   * Requirement 14.3：已无未产出节点时，`next()` 返回 `None`。
//   * Requirement 14.5：额外状态仅游标 `pos`（O(1)），其值始终满足
//     `0 <= pos <= nodes.length()`；不二次物化路径。
//   * Requirement 14.6：无解场景由 `empty()` 表达，其首次 `next()` 即返回
//     `None`。
//   * Requirement 14.7：耗尽后重复调用 `next()` 恒返回 `None` 且不再推进、
//     不再产出节点（幂等终止）。

///|
/// 惰性路径迭代器：在调用方持有的单条路径之上按需逐个产出节点。
///
/// 字段语义：
///
/// - `nodes`：底层路径。由调用方提供并持有；迭代器不复制、不重建
///   （Requirement 14.5）。空数组表示「无解 / 空路径」。
/// - `pos`：唯一的额外状态——指向下一个待产出节点的游标。初始为 `0`，
///   每次成功产出后前移一位，恒满足 `0 <= pos <= nodes.length()`，
///   因此额外状态规模为 O(1)（Requirement 14.5）。
///
/// 该结构刻意只持有一个游标而非复制节点序列：完整消费产出的序列与一次性
/// 物化的完整路径逐元素相等且等长（Requirement 14.4，由属性测试 P22 验证）。
pub struct LazyPath[N] {
  /// 底层路径（调用方已持有的单条路径），迭代器不复制、不重建。
  nodes : Array[N]
  /// 游标：指向下一个待产出节点的下标，唯一的 O(1) 额外状态。
  mut pos : Int
}

///|
/// 由一条已物化的路径构造惰性迭代器。
///
/// 迭代器直接引用传入的 `path` 作为底层节点序列，不进行复制（Requirement
/// 14.5）。游标 `pos` 初始化为 `0`，使首次 `next()` 从路径首元素开始逐个
/// 产出（Requirement 14.1 / 14.2）。
///
/// 注意：若传入空数组，其行为与 `empty()` 等价——首次 `next()` 即返回
/// `None`。
pub fn[N] LazyPath::from_path(path : Array[N]) -> LazyPath[N] {
  { nodes: path, pos: 0 }
}

///|
/// 构造表示「无解」的空惰性迭代器。
///
/// 用于查询无解的场景（Requirement 14.6）：底层路径为空，游标为 `0`，
/// 因此首次调用 `next()` 即返回不含任何节点的终止值 `None`。该实现仅持
/// O(1) 游标状态，不分配路径存储。与 `from_path([])` 行为一致，但语义上
/// 显式表达「不存在路径」而非「长度为零的路径」，便于调用方区分两类结果。
/// 后续对耗尽迭代器重复调用 `next()` 幂等返回 `None`（R14.7）。
pub fn[N] LazyPath::empty() -> LazyPath[N] {
  { nodes: [], pos: 0 }
}

///|
/// 取值操作：产出路径中的下一个节点，或在路径耗尽时返回终止值 `None`。
///
/// 行为保证：
///
/// - **逐个产出并前移**（Requirement 14.2）：当 `pos` 仍在有效范围内
///   （`pos < nodes.length()`）时，返回 `Some(nodes[pos])` 并将 `pos`
///   前移一位。
/// - **耗尽即终止**（Requirement 14.1 / 14.3）：当 `pos` 已抵达路径末尾
///   （`pos >= nodes.length()`）时，返回 `None` 且**不**推进游标。
/// - **幂等终止**（Requirement 14.7）：由于耗尽后不再推进游标，重复调用
///   `next()` 恒返回相同的终止值 `None`，且不再产出任何节点；同时游标被
///   钳制在 `nodes.length()`，不会溢出。
/// - **无解首调即终止**（Requirement 14.6）：对 `empty()` 构造的迭代器，
///   `nodes.length()` 为 `0`，首次调用即落入耗尽分支返回 `None`。
///
/// 作为 `LazyPath::next` 方法定义（而非顶层 `next` 函数），以避免与内置
/// 迭代命名产生歧义，同时保持与设计文档一致的调用形态 `it.next()`。
pub fn[N] LazyPath::next(self : LazyPath[N]) -> N? {
  if self.pos < self.nodes.length() {
    let node = self.nodes[self.pos]
    self.pos = self.pos + 1
    Some(node)
  } else {
    // 耗尽：保持游标不变（幂等），恒返回终止值 None。
    None
  }
}
