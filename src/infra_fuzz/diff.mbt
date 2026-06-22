// diff.mbt —— 差分测试比较基元：浮点容差比较 `approx_eq` 与等价类枚举
// `EquivClass`（task 7.3）。
//
// 设计依据（design.md §5.2 Differential_Tester · Requirement 16.1/16.2/16.3）：
//
//   pub fn approx_eq(a : Double, b : Double, eps : Double) -> Bool  // |a-b| <= eps
//   pub enum EquivClass {
//     BfsVsDijkstraUnit          // 单位权图：BFS 代价 == Dijkstra 代价（精确 · R16.1）
//     DijkstraVsBellmanFord      // 非负权：两者代价偏差 ≤1e-9（R16.2）
//     FloydWarshallVsJohnson     // 全对最短距离矩阵逐元素 ≤1e-9（R16.3）
//   } derive(Eq, Show)
//
// 设计哲学：
//   * `approx_eq` 是差分判等的唯一数值口径：整数权 / 单位权场景以 `eps=0`
//     退化为精确相等（R16.1），浮点权场景以 `eps=default_eps`（1e-9）容许
//     微小数值偏差（R16.2/R16.3）。
//   * NaN / 无穷的健壮处理：最短路代价中「不可达」常以 +∞ 表示。任一操作数
//     为 NaN 时一律判不相等（NaN 不等于任何值，含自身）；同号无穷视为相等
//     （「同为不可达」即一致 · 配合 R16.4）；其余无穷组合差为无穷必然超出
//     任何有限容差。全过程不依赖可能缺失的库函数，差值取绝对值手工计算，
//     保证 total 且三后端逐位一致。
//   * `EquivClass` 以精确枚举表达三个等价类，严禁以字符串模拟结构化数据
//     （R22.6 / 反模式清单）；`derive(Eq, Show)` 使等价类可直接参与相等性
//     断言与快照校验。
//   * 命名常量替代 magic number：默认容差 1e-9 命名为 `default_eps`。

///|
/// 差分判等的默认浮点容差（design.md §5.2 / R16.2 / R16.3）：浮点最短路
/// 代价的逐值偏差不超过本容差即视为「相等」。整数权 / 单位权场景应改用
/// `eps = 0.0` 以要求精确相等（R16.1）。取值 `1e-9` 在浮点累加误差与
/// 误报之间取得平衡，适配 Dijkstra↔Bellman-Ford、Floyd-Warshall↔Johnson
/// 等等价类的全对矩阵比较。以命名常量替代散落字面量，避免 magic number。
pub let default_eps : Double = 1.0e-9

///|
/// 浮点最短路代价比较：当 `|a - b| <= eps` 时返回 `true`。
///
/// 数值口径（design.md §5.2 · R16.1/R16.2/R16.3）：
///   * 传入 `eps = 0.0` 即退化为精确相等，用于整数 / 单位权场景（R16.1）。
///   * 传入 `eps = default_eps`（1e-9）容许微小浮点偏差（R16.2/R16.3）。
///
/// NaN / 无穷的健壮处理（最短路常以 +∞ 表示「不可达」）：
///   * 任一操作数为 NaN（含自身不等于自身的判定）一律返回 `false`——NaN
///     不近似等于任何值，避免把「非数」误判为一致。
///   * 同号无穷（`+∞` 对 `+∞`、`-∞` 对 `-∞`）经精确相等判定返回 `true`，
///     即「两侧同为不可达」一致（配合 R16.4 的不可达一致性）。
///   * 异号无穷或「一侧无穷、一侧有限」时，差值为无穷，必然超出任何有限
///     容差而返回 `false`。
///
/// 实现为 total：差值绝对值手工计算（不调用可能缺失的库函数），且经上述
/// 前置判定后 `a - b` 不会产生 NaN，保证三后端结果逐位一致。
pub fn approx_eq(a : Double, b : Double, eps : Double) -> Bool {
  // NaN：任一为 NaN 即判不相等（NaN != NaN 恒为真）。
  if a != a || b != b {
    return false
  }
  // 精确相等：覆盖整数 / 单位权精确场景，以及同号无穷（同为不可达）。
  if a == b {
    return true
  }
  // 此处 a、b 均非 NaN 且不相等：差值至多为无穷而非 NaN，绝对值比较安全。
  let diff = if a >= b { a - b } else { b - a }
  diff <= eps
}

///|
/// 差分等价类（精确枚举 · design.md §5.2 · R22.6 禁止字符串模拟结构化数据）。
///
/// 每个变体刻画一组「在特定约束下结果必然一致」的算法对（Equivalence_Class），
/// 供 `Differential_Tester` 据此选择对应的图生成器与比较口径：
///
///   * `BfsVsDijkstraUnit`      —— 单位权图上 BFS 与 Dijkstra 的最短路代价
///     精确相等（整数单位权，eps=0 · R16.1）。
///   * `DijkstraVsBellmanFord`  —— 非负权图上 Dijkstra 与 Bellman-Ford 的
///     最短路代价偏差不超过 1e-9（R16.2）。
///   * `FloydWarshallVsJohnson` —— 带权图上 Floyd-Warshall 与 Johnson 的
///     全对最短距离矩阵逐元素偏差不超过 1e-9（R16.3）。
///
/// `derive(Eq, Show)` 使等价类可直接以相等性断言与快照（`Show`）校验，
/// 并可作为差分用例标识参与报告输出。
///
/// 可见性为 `pub(all)`：差分测试器（task 15.1 支撑逻辑 / task 15.2 属性测试）
/// 位于黑盒测试包中，需**构造**各等价类变体以「为每个 Equivalence_Class 跑
/// ≥100 随机实例」（R16.5），故变体须对外可构造（read-write）。这是对本特性
/// 自身新增类型的可见性加宽（bypass 新增语义，仅增不减），不影响任何既有 API。
pub(all) enum EquivClass {
  BfsVsDijkstraUnit
  DijkstraVsBellmanFord
  FloydWarshallVsJohnson
} derive(Eq, Show)
