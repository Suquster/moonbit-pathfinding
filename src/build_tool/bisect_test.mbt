// bisect_test.mbt —— 自动二分定位引擎黑盒测试（H-3）。
//
// 覆盖：无 Skip 精确定位、探测次数对数上界、Skip 邻域扩散、
// 全 Skip 返回 None、探测日志幂等（同下标不重复探测）、PBT。

///|
test "auto_bisect：无 Skip 精确定位首个 Bad" {
  let first_bad = 13
  let report = @build_tool.auto_bisect(40, fn(i) {
    if i >= first_bad {
      @build_tool.BisectBad
    } else {
      @build_tool.BisectGood
    }
  })
  assert_true(report.first_bad == Some(13))
  // 探测次数 ≤ 2 * ceil(log2(40)) + 2 = 14（实际应远小于）。
  assert_true(report.probes.length() <= 14)
}

///|
test "auto_bisect：首位即 Bad 与末位才 Bad 的边界" {
  let all_bad = @build_tool.auto_bisect(10, fn(_i) { @build_tool.BisectBad })
  assert_true(all_bad.first_bad == Some(0))
  let last_bad = @build_tool.auto_bisect(10, fn(i) {
    if i == 9 {
      @build_tool.BisectBad
    } else {
      @build_tool.BisectGood
    }
  })
  assert_true(last_bad.first_bad == Some(9))
}

///|
test "auto_bisect：Skip 邻域扩散仍定位到可判定的首个 Bad" {
  // 15/16/17 构建失败（Skip），真实首个 Bad 为 18。
  let report = @build_tool.auto_bisect(32, fn(i) {
    if i >= 15 && i <= 17 {
      @build_tool.BisectSkip
    } else if i >= 18 {
      @build_tool.BisectBad
    } else {
      @build_tool.BisectGood
    }
  })
  assert_true(report.first_bad == Some(18))
}

///|
test "auto_bisect：全 Skip 无法定位，显式返回 None" {
  let report = @build_tool.auto_bisect(8, fn(_i) { @build_tool.BisectSkip })
  assert_true(report.first_bad is None)
  // 每个下标至多探测一次（幂等 memo）。
  assert_true(report.probes.length() <= 8)
}

///|
test "PBT：随机回归点的定位正确性与对数探测上界（100 迭代）" {
  let gen : @infra_pbt.Gen[(Int, Int)] = @infra_pbt.Gen::new(fn(rng) {
    let n = 1 + rng.next_below(200)
    (n, rng.next_below(n))
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(case) {
    let (n, fb) = case
    let report = @build_tool.auto_bisect(n, fn(i) {
      if i >= fb {
        @build_tool.BisectBad
      } else {
        @build_tool.BisectGood
      }
    })
    // 对数上界：ceil(log2(n)) + 2 次探测内收敛。
    let mut bound = 2
    let mut m = n
    while m > 1 {
      bound = bound + 1
      m = (m + 1) / 2
    }
    report.first_bad == Some(fb) && report.probes.length() <= bound
  })
  assert_true(ok)
}
