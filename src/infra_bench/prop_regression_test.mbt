// Feature: championship-v1-upgrade, Property 8: 回归判定与加速比口径正确
//
// prop_regression_test.mbt —— 任务 6.6：回归判定 / 加速比口径属性测试。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 8「回归判定与加速比口径正确」（Validates: Requirements 5.5, 6.6, 6.7）：
//
//   *对任意* 基线中位、当前中位与容差 `tol_pct`，`regression_check` 满足：
//     1. 失败判定「当且仅当」：`failed == (current_median >
//        baseline_median * (1 + tol_pct/100))`（严格大于才失败）。
//     2. 回归百分比口径：`regression_pct == (current_median - baseline_median)
//        / baseline_median * 100`（浮点以容差比较）。
//     3. 加速比统一按中位计算：`speedup() == Some(baseline_median /
//        current_median)`（current_median > 0 时）。
//   被标注为失败 / 超时 / 不一致的用例由脚本层在「加速比聚合」阶段排除
//   （Requirement 6.7）；本纯函数对每对配对用例给出确定性 per-verdict 结果，
//   故本属性聚焦逐 verdict 的口径正确性。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板，每条属性
// 显式以 `iters=100` 驱动（满足「每条属性 ≥100 次迭代」基线）。
//
// 生成器约定：
//   * 随机构造一对 baseline / current `BenchReport`，二者拥有 **相同算法名集合**
//     （以索引命名 `alg0 / alg1 / ...` 保证名称两两不同，避免 `regression_check`
//     的同名去重影响「verdict 数 == 算法数」的统计）。
//   * 每个算法的 baseline / current 中位计时均为 **正浮点**（`> 0`）：经
//     `compute_stats([median])` 单样本计算确保 `stats.median` 精确等于设定值
//     （单样本时 min=max=median=mean=该值、stddev=0），从而 verdict 的两侧中位
//     与生成值逐位一致。
//   * 容差 `tol_pct` 随机取 `[0, 50]`。

// ---------------------------------------------------------------------------
// 测试内场景模型：携带生成的真值，便于逐 verdict 断言
// ---------------------------------------------------------------------------

///|
/// 单次属性迭代的随机场景：一对报告 + 容差 + 用于核验的算法名与两侧中位真值。
struct RegScenario {
  baseline : BenchReport
  current : BenchReport
  tol_pct : Double
  algorithms : Array[String]
  baseline_medians : Array[Double]
  current_medians : Array[Double]
}

// ---------------------------------------------------------------------------
// 随机生成器（generator）—— 复用 @infra_pbt 种子驱动随机源 Rng
// ---------------------------------------------------------------------------

///|
/// 生成一个有限的 **正** 浮点中位计时（含小数部分），保证 `> 0` 且不溢出为
/// 非有限值；整数部分取自 `[1, 1_000_000]` 确保严格为正。
fn reg_gen_positive_double(rng : @infra_pbt.Rng) -> Double {
  let whole = rng.next_range(1, 1_000_000).to_double()
  let frac = rng.next_below(1000).to_double() / 1000.0
  whole + frac
}

///|
/// 以单样本数组构造一个 `BenchCase`，其 `stats.median` 精确等于 `median`。
///
/// 单样本时 `compute_stats` 必为 `Ok`（仅空样本返回 `Err`），且 min=max=median=
/// mean=该样本、stddev=0，故中位口径与设定值逐位一致。
fn reg_mk_case(algorithm : String, median : Double) -> BenchCase {
  guard compute_stats([median]) is Ok(stats)
  {
    algorithm,
    graph_size: 0,
    edge_count: 0,
    query_count: 0,
    seed: 0,
    raw_ns: [median],
    stats,
  }
}

///|
/// 构造一个仅含元信息与给定用例集合的 `BenchReport`（元信息取固定占位值，
/// 不参与本属性断言）。
fn reg_mk_report(cases : Array[BenchCase]) -> BenchReport {
  {
    moon_version: "test",
    backend: "native",
    os: "linux",
    cpu: "x86_64",
    generator: "reg_prop",
    warmup_count: 3,
    cases,
  }
}

///|
/// 生成单个随机场景：随机 `1..5` 个算法，每个算法生成两侧正中位，随机容差。
fn reg_gen_scenario(rng : @infra_pbt.Rng) -> RegScenario {
  let count = rng.next_range(1, 5)
  let algorithms : Array[String] = []
  let baseline_medians : Array[Double] = []
  let current_medians : Array[Double] = []
  let baseline_cases : Array[BenchCase] = []
  let current_cases : Array[BenchCase] = []
  let mut i = 0
  while i < count {
    // 索引命名保证算法名两两不同（避免同名去重影响统计）。
    let alg = "alg" + i.to_string()
    let bm = reg_gen_positive_double(rng)
    let cm = reg_gen_positive_double(rng)
    algorithms.push(alg)
    baseline_medians.push(bm)
    current_medians.push(cm)
    baseline_cases.push(reg_mk_case(alg, bm))
    current_cases.push(reg_mk_case(alg, cm))
    i = i + 1
  }
  let tol_pct = rng.next_below(51).to_double()
  {
    baseline: reg_mk_report(baseline_cases),
    current: reg_mk_report(current_cases),
    tol_pct,
    algorithms,
    baseline_medians,
    current_medians,
  }
}

///|
/// 随机场景生成器（封装为 @infra_pbt.Gen，供断言模板驱动）。
fn reg_scenario_gen() -> @infra_pbt.Gen[RegScenario] {
  @infra_pbt.Gen::new(fn(rng) { reg_gen_scenario(rng) })
}

// ---------------------------------------------------------------------------
// 辅助
// ---------------------------------------------------------------------------

///|
/// 浮点绝对值（自包含，避免依赖标准库方法名差异）。
fn reg_abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
/// 浮点近似相等：绝对或相对偏差 `≤ 1e-9`（相对以两者量级较大者为尺度）。
fn reg_approx_eq(a : Double, b : Double) -> Bool {
  let diff = reg_abs(a - b)
  if diff <= 1.0e-9 {
    return true
  }
  let scale = if reg_abs(a) > reg_abs(b) { reg_abs(a) } else { reg_abs(b) }
  diff <= 1.0e-9 * scale
}

///|
/// 在 verdict 列表中按算法名查找首个匹配项；不存在返回 `None`。
fn reg_find_verdict(
  verdicts : Array[RegressionVerdict],
  alg : String,
) -> RegressionVerdict? {
  for v in verdicts {
    if v.algorithm == alg {
      return Some(v)
    }
  }
  None
}

// ---------------------------------------------------------------------------
// 属性断言（≥100 次迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: championship-v1-upgrade, Property 8: 回归判定与加速比口径正确
///
/// 对任意随机场景（一对同算法集合的报告 + 随机容差），`regression_check` 对每个
/// 配对算法的 verdict 满足：
///   - `failed == (current_median > baseline_median * (1 + tol_pct/100))`（当且仅当）；
///   - `regression_pct ≈ (current_median - baseline_median)/baseline_median*100`；
///   - `speedup() == Some(baseline_median / current_median)`（current_median > 0）。
/// 且 verdict 数量恰等于算法数量（名称两两不同、两侧均存在）。
///
/// **Validates: Requirements 5.5, 6.6, 6.7**
test "Feature: championship-v1-upgrade, Property 8: regression verdict and speedup calibration" {
  let ok = @infra_pbt.holds_for_all(
    reg_scenario_gen(),
    fn(s) {
      let verdicts = regression_check(s.baseline, s.current, s.tol_pct)
      // 名称两两不同且两侧均存在 → verdict 数应恰等于算法数。
      if verdicts.length() != s.algorithms.length() {
        return false
      }
      let mut all_ok = true
      let mut i = 0
      while i < s.algorithms.length() {
        let alg = s.algorithms[i]
        let bm = s.baseline_medians[i]
        let cm = s.current_medians[i]
        match reg_find_verdict(verdicts, alg) {
          None => all_ok = false
          Some(v) => {
            // 1. 失败判定「当且仅当」严格超过容差上界。
            let expected_failed = cm > bm * (1.0 + s.tol_pct / 100.0)
            let failed_ok = v.failed == expected_failed
            // 2. 回归百分比口径（浮点容差比较）。
            let expected_pct = (cm - bm) / bm * 100.0
            let pct_ok = reg_approx_eq(v.regression_pct, expected_pct)
            // 3. 加速比统一按中位计算（current_median > 0 必为 Some）。
            let speedup_ok = v.speedup() == Some(bm / cm)
            // 两侧中位口径应与设定值逐位一致。
            let median_ok = v.baseline_median == bm && v.current_median == cm
            if not(failed_ok && pct_ok && speedup_ok && median_ok) {
              all_ok = false
            }
          }
        }
        i = i + 1
      }
      all_ok
    },
    iters=100,
  )
  assert_true(ok)
}
