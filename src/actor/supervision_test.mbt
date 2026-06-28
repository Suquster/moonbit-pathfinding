// supervision_test.mbt —— supervision.mbt 单元测试（任务 3.6）。
//
// 覆盖：三策略范围见证、强度窗口边界见证。
// _Requirements: 1.1, 2.5_

///|
/// 三策略处置范围见证（child_count = 5, failed = 2）。
test "affected_children covers the three strategies (witness)" {
  // OneForOne：仅失败者。
  @test.assert_eq(affected_children(OneForOne, 5, 2), [2])
  // OneForAll：全部。
  @test.assert_eq(affected_children(OneForAll, 5, 2), [0, 1, 2, 3, 4])
  // RestForOne：失败者及其后。
  @test.assert_eq(affected_children(RestForOne, 5, 2), [2, 3, 4])
}

///|
/// 越界失败下标返回空范围。
test "affected_children with out-of-range index yields empty" {
  @test.assert_eq(affected_children(OneForOne, 3, -1), [])
  @test.assert_eq(affected_children(OneForAll, 3, 5), [])
}

///|
/// 强度窗口边界见证：窗口 (clock-window, clock]，恰在窗口外的旧重启不计入。
test "within_intensity respects the sliding window boundary (witness)" {
  // max_restarts = 2, window = 5。
  // 历史重启发生在时钟 1 与 3。当前时钟 6：窗口为 (1, 6]，含 3（不含 1）→ recent=1 < 2 → 可重启。
  assert_true(within_intensity([1, 3], 6, 5, 2))
  // 历史重启 3 与 5，当前时钟 6：窗口 (1,6] 含 3、5 → recent=2 >= 2 → 不可重启。
  assert_false(within_intensity([3, 5], 6, 5, 2))
  // max_restarts <= 0：恒不可重启。
  assert_false(within_intensity([], 0, 5, 0))
  // window <= 0：统计全部历史。
  assert_true(within_intensity([1], 100, 0, 2))
  assert_false(within_intensity([1, 2], 100, 0, 2))
}

///|
/// RestartIntensity / SupervisorSpec 构造与派生见证。
test "RestartIntensity and SupervisorSpec construct and derive Eq/Show" {
  let intensity = RestartIntensity::new(3, 10)
  @test.assert_eq(intensity, RestartIntensity::new(3, 10))
  let spec = SupervisorSpec::new(OneForOne, intensity, Restart)
  @test.assert_eq(spec.strategy, OneForOne)
  @test.assert_eq(spec.default_directive, Restart)
  @test.assert_eq(spec.intensity.max_restarts, 3)
}
