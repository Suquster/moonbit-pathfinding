// regression.mbt —— 基准回归判定 `RegressionVerdict` 与纯函数 `regression_check`。
//
// 设计依据（design.md §「方向 2 · 2.3 Regression_Guard 设计」/ Requirement 5.5；
// 另见 §「Property 8: 回归判定与加速比口径正确」/ Requirement 6.6/6.7）：
//   回归门禁的核心是一个**纯函数**：给定「基线报告」与「当前报告」，按算法名
//   （`BenchCase.algorithm`）配对两侧用例，比较二者的**中位计时**（`BenchStats.median`），
//   当前中位相对基线中位回归超过声明容差 `tol_pct`（默认 10.0%）时，将该算法标记为
//   `failed`。脚本层 `scripts/regression_guard.ps1` 读入基线 JSON 与当前 JSON，调用
//   本函数，任一 `failed=true` 即以非零状态退出并记录算法名 / 基线中位 / 当前中位 /
//   回归百分比。
//
// 关键约定：
//   * 回归百分比口径：`regression_pct = (current_median - baseline_median) /
//     baseline_median * 100`（与 design.md 注释逐字一致）。
//   * 失败判定口径：**当且仅当** `current_median > baseline_median * (1 + tol_pct/100)`
//     时 `failed=true`。即「恰好等于容差上界」不算回归（严格大于才失败）。
//   * 加速比口径：统一以中位计时计算 `speedup = baseline_median / current_median`
//     （Requirement 6.6）。被标注为失败/超时/不一致的用例由脚本层在聚合阶段排除
//     （Requirement 6.7）；本纯函数对每一对配对用例给出确定性结果。
//   * 配对规则：只对「基线与当前**都存在**」的算法名产出 verdict。两侧重复同名用例时，
//     各取其**首次**出现的用例（确定性、与报告内用例顺序一致）。
//   * Requirement 22.6：以精确结构体表示判定结果，不以字符串模拟结构化数据；不在
//     循环体内做字符串 `+` 拼接（Requirement 22.4）。

///|
/// 默认回归容差（百分比）。当前中位计时相对基线中位回归超过该百分比即判失败。
/// 以命名常量替代散落字面量，避免 magic number（quality-enforcement 规则）。
/// 取值 `10.0` 表示允许 10% 的中位计时劣化，超过即标记 `failed=true`。该默认
/// 值可由 `regression_check` 的 `tol_pct` 参数覆盖，以适配不同噪声水平的环境。
/// 判定采用严格大于：恰好等于容差上界不算回归（见 `RegressionVerdict.failed`）。
pub let default_tol_pct : Double = 10.0

///|
/// 容差百分比换算的基数（百分数 → 比例的分母 100）。
let tol_percent_base : Double = 100.0

///|
/// 单个算法的回归判定结论（Requirement 5.5）。
///
/// 字段语义：
///
/// - `algorithm`：算法名称（来自配对的 `BenchCase.algorithm`）。
/// - `baseline_median`：基线报告中该算法用例的中位计时。
/// - `current_median`：当前报告中该算法用例的中位计时。
/// - `regression_pct`：回归百分比 `(current - baseline) / baseline * 100`。
///   正值表示变慢（回归），负值表示变快（改进）。
/// - `failed`：当且仅当 `current_median > baseline_median * (1 + tol_pct/100)`
///   时为 `true`。
///
/// 派生 `Eq` 以支持等值断言，派生 `Show` 以支持调试输出。
pub(all) struct RegressionVerdict {
  algorithm : String
  baseline_median : Double
  current_median : Double
  regression_pct : Double
  failed : Bool
} derive(Eq, Debug)

///|
/// 该判定对应的中位加速比 `baseline_median / current_median`（Requirement 6.6）。
///
/// 口径：以中位计时计算。`>1` 表示当前比基线更快（加速），`<1` 表示更慢。
/// 当 `current_median == 0` 时无法定义比值，返回 `None`（由调用方/脚本层按
/// 「不计入加速比聚合」处理，Requirement 6.7），避免除零产生非有限值。
/// 返回 `Some(ratio)` 时 `ratio` 恒为有限正数，可安全用于跨算法加速比聚合。
pub fn RegressionVerdict::speedup(self : RegressionVerdict) -> Double? {
  if self.current_median == 0.0 {
    None
  } else {
    Some(self.baseline_median / self.current_median)
  }
}

///|
/// 在报告用例中按算法名查找**首个**匹配用例的中位计时；不存在返回 `None`。
fn find_median_by_algorithm(
  report : BenchReport,
  algorithm : String,
) -> Double? {
  for c in report.cases {
    if c.algorithm == algorithm {
      return Some(c.stats.median)
    }
  }
  None
}

///|
/// 比较当前报告与基线报告，按算法名配对，对每一对配对用例计算回归百分比并据容差
/// `tol_pct` 给出失败判定（Requirement 5.5）。
///
/// 行为保证：
///
/// - **配对**：仅对「基线与当前都存在」的算法名产出 `RegressionVerdict`。遍历顺序
///   以基线报告的用例顺序为准（确定性）；两侧同名重复用例各取首次出现者。
/// - **回归百分比**：`regression_pct = (current_median - baseline_median) /
///   baseline_median * 100`。当 `baseline_median == 0` 时该比值无定义，约定
///   `regression_pct = 0.0`（避免除零产生非有限值；此时失败判定退化为
///   `current_median > 0`）。
/// - **失败判定**：当且仅当 `current_median > baseline_median * (1 + tol_pct/100)`
///   时 `failed=true`（严格大于；恰好等于容差上界不算回归）。
/// - **不修改入参**：仅读取两份报告，不改动任何外部状态。
///
/// 复杂度：对 `baseline.cases` × `current.cases` 的朴素配对为 O(b·c)；报告用例数为
/// 算法种类量级（远小于计时样本数），实践中规模很小。不在循环体内做字符串 `+`
/// 拼接（Requirement 22.4）。
pub fn regression_check(
  baseline : BenchReport,
  current : BenchReport,
  tol_pct : Double,
) -> Array[RegressionVerdict] {
  let verdicts : Array[RegressionVerdict] = []
  // 记录已产出的算法名，避免基线侧重复同名用例导致重复 verdict。
  let seen : Array[String] = []
  for bc in baseline.cases {
    let algorithm = bc.algorithm
    // 跳过已处理过的算法名（取基线首次出现者）。
    let mut already = false
    for s in seen {
      if s == algorithm {
        already = true
      }
    }
    if already {
      continue
    }
    match find_median_by_algorithm(current, algorithm) {
      None => continue
      Some(current_median) => {
        seen.push(algorithm)
        let baseline_median = bc.stats.median
        let regression_pct = if baseline_median == 0.0 {
          0.0
        } else {
          (current_median - baseline_median) /
          baseline_median *
          tol_percent_base
        }
        let threshold = baseline_median * (1.0 + tol_pct / tol_percent_base)
        let failed = current_median > threshold
        verdicts.push({
          algorithm,
          baseline_median,
          current_median,
          regression_pct,
          failed,
        })
      }
    }
  }
  verdicts
}
