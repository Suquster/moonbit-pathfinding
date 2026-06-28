// clock_test.mbt —— 逻辑时钟 / 时钟偏移单元测试（任务 1.2）。
//
// 覆盖 `skewed_time` 正偏移、负偏移下钳到 0、零偏移恒等的具体见证（R3.5）。

///|
/// 正偏移：向未来推移。
test "skewed_time applies positive offset" {
  @test.assert_eq(skewed_time(10UL, 5L), 15UL)
  @test.assert_eq(skewed_time(0UL, 7L), 7UL)
}

///|
/// 负偏移：向过去推移，但下钳到 0（不回退为非法值）。
test "skewed_time clamps negative offset to zero" {
  @test.assert_eq(skewed_time(10UL, -4L), 6UL)
  @test.assert_eq(skewed_time(3UL, -10L), 0UL)
  @test.assert_eq(skewed_time(0UL, -1L), 0UL)
}

///|
/// 零偏移：恒等。
test "skewed_time with zero offset is identity" {
  @test.assert_eq(skewed_time(42UL, 0L), 42UL)
}
