// stats.mbt —— 基准汇总统计量 `BenchStats` 与纯函数 `compute_stats`。
//
// 设计依据（design.md §「方向 2 · 2.1 Benchmark_Framework」/ Requirement 5.2）：
//   基准框架的统计量计算是 **纯函数**，由原始计时样本（单位无关，通常为
//   纳秒 `Double`）确定性地导出最小值 / 最大值 / 中位数 / 算术平均 / p95 /
//   总体标准差六个汇总量，外加样本量。此处与脚本层（计时采集、机器信息）
//   通过 JSON 工件衔接，本文件只承担「样本 → 统计量」这一步。
//
// 关键约定：
//   * Requirement 5.2：汇总统计量包含 min / max / median / mean / p95 / stddev。
//   * p95 采用「最近秩」(nearest-rank) 定义：对升序样本，秩
//     `rank = ceil(p/100 * n)`（1-based），取第 `rank` 个样本；秩落在
//     `[1, n]` 内（边界钳制）。
//   * stddev 采用 **总体标准差**（分母为 n，而非样本标准差的 n-1）。
//   * 空样本属非法输入：返回 `Err(@graph.PathError::InvalidArgument(...))`，
//     与既有结构化错误类型对齐（Requirement 5.2）。
//   * Requirement 22.6：以精确结构体表示统计量，不用字符串模拟。

///|
/// p95 百分位的分子（百分数表示）。最近秩公式 `rank = ceil(P/100 * n)`
/// 中的 `P`。命名常量以避免硬编码 magic number（quality-enforcement 规则）。
let p95_percentile_numerator : Double = 95.0

///|
/// 百分位公式中的分母（百分数的基数 100）。
let percent_denominator : Double = 100.0

///|
/// 自包含平方根（Newton–Raphson 迭代）。用于总体标准差的开方。
///
/// 选择自包含实现而非依赖外部数学库，是为了保证 `wasm-gc` / `js` /
/// `native` 三后端上 **逐位确定性一致**（Requirement 22.2 三后端一致），
/// 不引入跨后端浮点库差异。迭代次数为命名常量，收敛为二次（每步约翻倍
/// 有效位数），对基准计时量级（非负、有限）已远超双精度精度需求。
///
/// 约定：对 `x <= 0` 返回 `0.0`（标准差的被开方数恒非负，`0` 对应零方差）。
fn double_sqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  // 以 x 自身为初值；对正数收敛稳健。
  let mut guess = x
  for _ in 0..<sqrt_newton_iterations {
    guess = (guess + x / guess) * 0.5
  }
  guess
}

///|
/// Newton–Raphson 求平方根的迭代次数。60 次远超双精度收敛所需，
/// 既保证精度又保持确定性（命名常量，避免 magic number）。
let sqrt_newton_iterations : Int = 60

///|
/// 向上取整为整数（仅用于非负的最近秩计算）。
///
/// `Double::to_int` 对正数向零截断；若截断值小于原值说明存在小数部分，
/// 需再 +1 以实现向上取整。用于把实数秩 `p/100 * n` 转为整数秩。
fn ceil_to_int(x : Double) -> Int {
  let truncated = x.to_int()
  if truncated.to_double() < x {
    truncated + 1
  } else {
    truncated
  }
}

///|
/// 基准汇总统计量（Requirement 5.2）。全部由原始计时样本纯计算得出。
///
/// 字段语义（单位与输入样本一致，通常为纳秒）：
///
/// - `min`：样本最小值。
/// - `max`：样本最大值。
/// - `median`：中位数。样本量为奇数时取正中元素；为偶数时取居中两元素的
///   算术平均。
/// - `mean`：算术平均值（样本和除以样本量）。
/// - `p95`：第 95 百分位，采用最近秩定义（见本文件顶部说明）。
/// - `stddev`：总体标准差（分母为样本量 n）。
/// - `sample_count`：样本量 n（恒 ≥ 1，因空样本被 `compute_stats` 拒绝）。
///
/// 派生 `Eq` 以支持等值断言，派生 `Show` 以支持调试输出。
pub struct BenchStats {
  min : Double
  max : Double
  median : Double
  mean : Double
  p95 : Double
  stddev : Double
  sample_count : Int
} derive(Eq, Show)

///|
/// 由原始计时样本计算汇总统计量（Requirement 5.2）。
///
/// 行为保证：
///
/// - **空样本拒绝**：`samples` 为空时返回
///   `Err(@graph.PathError::InvalidArgument(...))`，不构造任何部分结果。
/// - **不修改入参**：内部对样本做副本后排序，调用方传入的数组保持不变。
/// - **min / max**：分别为升序样本的首元素与末元素。
/// - **median**：奇数取正中，偶数取居中两元素均值。
/// - **mean**：样本和除以样本量。
/// - **p95**：最近秩 `rank = ceil(95/100 * n)`，钳制到 `[1, n]` 后取第
///   `rank` 个升序样本。
/// - **stddev**：总体标准差 `sqrt( Σ(x - mean)² / n )`，恒 `≥ 0`；当所有
///   样本相等时为 `0`。
///
/// 复杂度：排序 O(n log n) + 单遍统计 O(n)；不在循环体内做字符串 `+` 拼接
/// （Requirement 22.4）。
pub fn compute_stats(
  samples : Array[Double],
) -> Result[BenchStats, @graph.PathError] {
  let n = samples.length()
  if n == 0 {
    return Err(
      @graph.PathError::InvalidArgument(
        "compute_stats: 样本数组为空，至少需要一个计时样本",
      ),
    )
  }
  // 副本排序，避免修改调用方数组（不修改入参约定）。
  let sorted = samples.copy()
  sorted.sort()
  let min = sorted[0]
  let max = sorted[n - 1]
  // 中位数：奇数取正中，偶数取居中两元素均值。
  let median = if n % 2 == 1 {
    sorted[n / 2]
  } else {
    (sorted[n / 2 - 1] + sorted[n / 2]) * 0.5
  }
  // 均值：单遍求和。
  let mut sum = 0.0
  for x in sorted {
    sum = sum + x
  }
  let mean = sum / n.to_double()
  // p95：最近秩 rank = ceil(P/100 * n)，钳制到 [1, n]。
  let rank_real = p95_percentile_numerator / percent_denominator * n.to_double()
  let mut rank = ceil_to_int(rank_real)
  if rank < 1 {
    rank = 1
  }
  if rank > n {
    rank = n
  }
  let p95 = sorted[rank - 1]
  // 总体标准差：分母为 n。单遍累加平方偏差。
  let mut sq_dev_sum = 0.0
  for x in sorted {
    let dev = x - mean
    sq_dev_sum = sq_dev_sum + dev * dev
  }
  let variance = sq_dev_sum / n.to_double()
  let stddev = double_sqrt(variance)
  Ok({ min, max, median, mean, p95, stddev, sample_count: n })
}
