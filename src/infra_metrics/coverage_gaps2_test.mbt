// 黑盒测试：指标包边界钳制与越界防御分支。

///|
test "ddsketch：alpha 读取与分位钳制、总量兜底" {
  let s = DDSketch::new(0.01)
  assert_true(s.error_bound() > 0.0)
  s.add(1.0)
  s.add(2.0)
  // 分位越界钳制到 [0,1]。
  assert_true(s.quantile(-0.5) is Some(_))
  assert_true(s.quantile(1.5) is Some(_))
}

///|
test "hdr：精度位与百分位钳制" {
  let h0 = HdrHistogram::new(0)
  assert_true(h0.precision_bits == 1)
  let h13 = HdrHistogram::new(13)
  assert_true(h13.precision_bits == 12)
  let h = HdrHistogram::new(3)
  h.record(5L)
  h.record(10L)
  assert_true(h.value_at_percentile(-1.0) is Some(_))
  assert_true(h.value_at_percentile(120.0) is Some(_))
}

///|
test "span_tracer：越界 id 防御" {
  let t = SpanTracer::new()
  assert_eq(t.children_of(99).length(), 0)
  assert_true(t.span_name(-1) is None)
  assert_true(t.span_self(42) is None)
}
