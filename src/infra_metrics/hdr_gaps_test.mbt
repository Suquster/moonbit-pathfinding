// 黑盒测试：覆盖率审计收口（INFRA 第七十二批）——
// 百分位秩上钳与跨精度合并降级重记录。

///|
test "value_at_percentile：100 百分位秩钳制到 total" {
  let h = @infra_metrics.HdrHistogram::new(3)
  h.record(10L)
  h.record(20L)
  h.record(30L)
  guard h.value_at_percentile(100.0) is Some(v)
  assert_true(v >= 30L)
}

///|
test "merge_with：精度不同逐桶降级重记录" {
  let a = @infra_metrics.HdrHistogram::new(3)
  let b = @infra_metrics.HdrHistogram::new(5)
  b.record(100L)
  b.record(200L)
  a.merge_with(b)
  assert_eq(a.count(), 2)
}
