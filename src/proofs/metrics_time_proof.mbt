// metrics_time_proof.mbt —— INFRA 家族第三批证明谓词：延迟指标聚合
// （infra_metrics：HdrHistogram / DDSketch）与时间运算（infra_time：
// civil↔days、ISO8601）的不变量接入。
//
// 复用约定：与其余 `*_proof.mbt` 相同——每条不变量编码为纯、全（total）的
// `Bool` 谓词，proofs 生产代码不引入新依赖（仅 @core），跨包驱动只发生在
// 测试期（metrics_time_proof_test.mbt 以真实包实现接地）。
//
// 覆盖的不变量家族：
//   * 分位数单调（q1 ≤ q2 ⟹ quantile(q1) ≤ quantile(q2)，Int64/Double 两种值域）；
//   * 分位数夹逼（任意分位点落在已记录样本的 [min, max] 区间内）；
//   * 计数守恒（merge 后 total == 各方 total 之和）；
//   * 往返恒等（civil↔days、format∘parse，复用 predicates.mbt 的 round_trip_eq）。

///|
/// `non_decreasing64(xs)` —— `non_decreasing` 的 Int64 值域版本：序列逐对
/// 非降。用于 HdrHistogram `value_at_percentile` 随百分位单调等性质。
/// 纯、全函数（长度 < 2 平凡为真）。
pub fn non_decreasing64(xs : Array[Int64]) -> Bool {
  let mut i = 0
  while i + 1 < xs.length() {
    if xs[i] > xs[i + 1] {
      return false
    }
    i += 1
  }
  true
}

///|
/// `non_decreasing_f(xs)` —— `non_decreasing` 的 Double 值域版本。用于
/// DDSketch `quantile` 随 q 单调等性质。纯、全函数（长度 < 2 平凡为真）。
pub fn non_decreasing_f(xs : Array[Double]) -> Bool {
  let mut i = 0
  while i + 1 < xs.length() {
    if xs[i] > xs[i + 1] {
      return false
    }
    i += 1
  }
  true
}

///|
/// `all_within64(xs, lo, hi)` —— `all_within` 的 Int64 值域版本：每个元素
/// 均落在闭区间 `[lo, hi]`。用于「分位点必落在已记录样本 [min, max] 内」的
/// 夹逼不变量。纯、全函数（空序列平凡为真）。
pub fn all_within64(xs : Array[Int64], lo : Int64, hi : Int64) -> Bool {
  let mut i = 0
  while i < xs.length() {
    if xs[i] < lo || xs[i] > hi {
      return false
    }
    i += 1
  }
  true
}

///|
/// `count_conserved(total, parts)` —— 计数守恒谓词：聚合后的总计数恰为各
/// 分片计数之和。用于直方图/摘要 `merge_with` 的样本数守恒（合并不得丢失
/// 或虚增样本）。纯、全函数（空分片时要求 total == 0）。
pub fn count_conserved(total : Int, parts : Array[Int]) -> Bool {
  let mut sum = 0
  let mut i = 0
  while i < parts.length() {
    sum += parts[i]
    i += 1
  }
  total == sum
}
