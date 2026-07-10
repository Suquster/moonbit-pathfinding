// sampling_gaps_wbtest.mbt —— 采样阈值量化/保留条数钳制分支收口
// （INFRA 第四十三批）。

///|
test "sampling_threshold：边界率量化与钳制" {
  assert_eq(sampling_threshold(0.0), 0UL)
  assert_eq(sampling_threshold(-1.0), 0UL)
  assert_eq(sampling_threshold(1.0), sampling_denom)
  assert_eq(sampling_threshold(2.0), sampling_denom)
  // 极小正率量化后 t<=0 → 钳为 0。
  assert_eq(sampling_threshold(1.0e-12), 0UL)
  // 常规率落于开区间。
  assert_true(sampling_threshold(0.5) > 0UL)
}
