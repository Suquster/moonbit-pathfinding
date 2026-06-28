// enhancement_prop_test.mbt —— PBT 增强属性测试（task 2.4）。
//
// 设计依据（design.md §「Property 11: R11 收缩与分布」，Requirement 11.1 /
// 11.2 / 11.4 / 11.5）。本文件承载组合子（task 2.1）、收缩（task 2.2）、
// 统计（task 2.3）三项增强的「属性级」校验，每条属性 `iters >= 100`：
//
//   * Property 11a（AC2）：`check_with_shrink` 收缩产物仍使被测属性失败，
//     且收缩朝最小方向逼近（最小失败反例 == 触发阈值 + 1）。
//   * Property 11b（AC1/AC2 支撑）：`shrink_int` 候选严格更接近 0 且不含原值。
//   * Property 11c（AC4）：`frequency` 大样本下各分支占比趋近配置权重比例。
//   * Property 11d（AC5）：`holds_for_all_stats` 的统计计数与样本分类一致。
//
// 约定：
//   * 复用本包内部 API（`@infra_pbt` 内测，直接调用）。
//   * 不在循环内做字符串 `+`；构造期望文本一律 Array + join。
//   * 测试注释统一标注 `Feature: production-hardening, Property 11: {text}`，
//     并附 `**Validates: Requirements 11.x**`。
//   * 占比类断言使用确定性默认种子（`holds_for_all_stats` 内部即用
//     `default_seed`）并配足够样本量与合理容差，确保三后端稳定复现。

///|
/// `frequency` 占比趋近性判定的容差（绝对偏差上界）。
///
/// 统计趋近为概率收敛，需留出有限样本的波动余量；命名常量以规避 magic
/// number。在 `frequency_sample_count` 样本量下，固定种子的实际偏差远小于
/// 该容差，故三后端均稳定通过。
let ratio_tolerance : Double = 0.1

///|
/// `frequency` 占比测试所用的大样本量（>= 100，满足质量门禁迭代基线）。
///
/// 取 4000 以使权重比例的统计趋近足够稳定（大数定律），同时保持三后端运行
/// 开销可控。
let frequency_sample_count : Int = 4000

///|
/// 内部工具：整数绝对值（生成器区间有界，无 `-min_int` 溢出风险）。
fn int_abs(x : Int) -> Int {
  if x < 0 {
    -x
  } else {
    x
  }
}

///|
/// Feature: production-hardening, Property 11a: 收缩产物仍使属性失败且最小
///
/// 对随机阈值 `k`，在区间 `[0, k + spread]` 上以谓词 `x <= k` 运行
/// `check_with_shrink`：区间右端足够大以保证 100 次采样内必现失败样本
/// （`x > k`）。校验三项不变量：
///   1. 属性确被证伪（`passed == false`），即检查到了反例；
///   2. 收缩产物仍使属性失败（`!pred(c)`，即 `c > k`）——AC2 的核心不变量；
///   3. 收缩朝 0 单调逼近至最小失败反例：`c == k + 1`（首个使 `x <= k` 为
///      假的非负整数），体现「不大于初始触发值且达到合理最小界」。
///
/// 外层 `holds_for_all` 以默认 100 次迭代随机化阈值 `k`，每次内部再跑一轮
/// `check_with_shrink`（其默认 `iters == default_iters >= 100`）。
///
/// **Validates: Requirements 11.1, 11.2**
test "Feature: production-hardening, Property 11a: shrink result still fails and is minimal" {
  // 阈值 k ∈ [0, 30]；区间右端 = k + spread，spread 足够大以保证出现失败样本。
  let k_gen = gen_int_range(0, 30)
  let spread = 50
  let ok = holds_for_all(k_gen, fn(k) {
    let g = gen_int_range(0, k + spread)
    let pred = fn(x : Int) -> Bool { x <= k }
    let result = check_with_shrink(g, pred, shrink_int)
    // 必须检测到反例（区间右端足够大，100 次采样内必现 x > k）。
    if result.passed {
      return false
    }
    match result.counterexample {
      Some(c) =>
        // 不变量：收缩产物仍使属性失败；且达到最小失败反例 k+1。
        !pred(c) && c == k + 1
      None => false
    }
  })
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 11b: shrink_int 候选更接近 0 且不含原值
///
/// 对随机整数 `v`（含正、负、零）：
///   * `v == 0` 时无可收缩，候选集为空；
///   * `v != 0` 时每个候选 `c` 满足 `abs(c) < abs(v)`（严格更接近 0），
///     从而必然 `c != v`（不含原值）。
///
/// 该性质是收缩单调终止与「最小反例」可达性的基础（支撑 AC1/AC2）。外层
/// `holds_for_all` 以默认 100 次迭代随机化 `v`。
///
/// **Validates: Requirements 11.1, 11.2**
test "Feature: production-hardening, Property 11b: shrink_int candidates strictly approach zero" {
  let v_gen = gen_int_range(-1000, 1000)
  let ok = holds_for_all(v_gen, fn(v) {
    let candidates = shrink_int(v)
    if v == 0 {
      // 零已是绝对值最小，无候选。
      return candidates.length() == 0
    }
    let abs_v = int_abs(v)
    for c in candidates {
      // 严格更接近 0，蕴含 c != v。
      if int_abs(c) >= abs_v {
        return false
      }
    }
    true
  })
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 11c: frequency 大样本占比趋近配置权重
///
/// 以可区分分支构造 `frequency`：分支 A 恒生成 `0`、分支 B 恒生成 `1`，分类
/// 函数据此区分。对两组权重配置（1:3 与 2:1）各采样
/// `frequency_sample_count`（>= 100）个样本，断言各分支实际占比与理论权重
/// 比例（A=w_a/(w_a+w_b)，B=w_b/(w_a+w_b)）的绝对偏差不超过 `ratio_tolerance`。
///
/// 采样经 `holds_for_all_stats` 完成，其内部使用确定性 `default_seed`，故
/// 结果可复现且三后端一致（`Rng` 逐位一致）。
///
/// **Validates: Requirements 11.4**
test "Feature: production-hardening, Property 11c: frequency ratios approach configured weights" {
  // 谓词恒真：本属性只关注分布占比，不证伪属性本身。
  let always_true = fn(_x : Int) -> Bool { true }
  // 分类：分支 A 的样本恒为 0，分支 B 的样本恒为 1。
  let classify = fn(x : Int) -> String { if x == 0 { "A" } else { "B" } }

  // 校验单组权重配置 (w_a : w_b) 的占比趋近性。
  let check_weights = fn(w_a : Int, w_b : Int) -> Bool {
    let g = frequency([(w_a, gen_int_range(0, 0)), (w_b, gen_int_range(1, 1))])
    let (_passed, stats) = holds_for_all_stats(
      g,
      always_true,
      classify,
      iters=frequency_sample_count,
    )
    // 理论占比。
    let denom = (w_a + w_b).to_double()
    let expect_a = w_a.to_double() / denom
    let expect_b = w_b.to_double() / denom
    let dev_a = (stats.ratio("A") - expect_a).abs()
    let dev_b = (stats.ratio("B") - expect_b).abs()
    // 总数应等于样本量（与 AC5 一致），且各分支偏差在容差内。
    stats.total() == frequency_sample_count &&
    dev_a <= ratio_tolerance &&
    dev_b <= ratio_tolerance
  }

  // 配置一：1:3 —— 期望 A≈0.25、B≈0.75。
  assert_true(check_weights(1, 3))
  // 配置二：2:1 —— 期望 A≈0.667、B≈0.333。
  assert_true(check_weights(2, 1))
}

///|
/// Feature: production-hardening, Property 11d: 统计计数与样本分类一致
///
/// 对若干样本量 `n`（均 >= 100），用 `holds_for_all_stats` 将每个样本按
/// `n % 5` 归入 5 个互斥分类之一，校验：
///   * `stats.total() == n`（恰好记录 n 个样本，每次迭代记录一个）；
///   * 5 个互斥分类的计数之和 `== stats.total()`（无样本落在分类之外，
///     计数与分类完全一致）。
///
/// 分类标签为字面常量，求和不在循环内做字符串拼接（满足约束）。
///
/// **Validates: Requirements 11.5**
test "Feature: production-hardening, Property 11d: stats counts consistent with classification" {
  // 5 个互斥分类标签（预先固定，循环内只读取、不拼接）。
  let labels = ["m0", "m1", "m2", "m3", "m4"]
  // 分类函数：非负样本按 mod 5 归类。
  let classify = fn(x : Int) -> String { labels[x % labels.length()] }
  let always_true = fn(_x : Int) -> Bool { true }
  // 多个样本量，均 >= 100。
  let sample_counts = [100, 250, 500, 1000]
  for n in sample_counts {
    let g = gen_int_range(0, 10_000)
    let (_passed, stats) = holds_for_all_stats(
      g,
      always_true,
      classify,
      iters=n,
    )
    // 总数等于迭代次数。
    @test.assert_eq(stats.total(), n)
    // 各分类计数之和等于 total。
    let mut sum = 0
    for label in labels {
      sum += stats.count(label)
    }
    @test.assert_eq(sum, n)
    @test.assert_eq(sum, stats.total())
  }
}
