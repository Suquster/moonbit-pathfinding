// hdr_histogram_test.mbt —— HdrHistogram 黑盒测试：低值段精确 / 分位
// 边界 / 合并定向 + 误差界证明式 PBT（任意分位相对误差 ≤ 2^-p）。

///|
test "hdr basic: empty / low-value exactness / max tracking" {
  let h = @infra_metrics.HdrHistogram::new(7)
  assert_true(h.value_at_percentile(50.0) == None)
  // 低值段（< 2^p = 128）逐值精确。
  for v in [0L, 1L, 5L, 100L, 127L] {
    h.record(v)
  }
  assert_eq(h.count(), 5)
  assert_true(h.value_at_percentile(0.0) == Some(0L))
  assert_true(h.value_at_percentile(100.0) == Some(127L))
  assert_eq(h.max_value(), 127L)
  // 负值归 0。
  h.record(-9L)
  assert_true(h.value_at_percentile(0.0) == Some(0L))
}

///|
test "hdr merge: same precision adds counts, quantiles stay bounded" {
  let a = @infra_metrics.HdrHistogram::new(7)
  let b = @infra_metrics.HdrHistogram::new(7)
  for i in 1..<=1000 {
    a.record(i.to_int64())
  }
  for i in 1001..<=2000 {
    b.record(i.to_int64())
  }
  a.merge_with(b)
  assert_eq(a.count(), 2000)
  assert_eq(a.max_value(), 2000L)
  let v = match a.value_at_percentile(50.0) {
    Some(x) => x.to_double()
    None => -1.0
  }
  // p50 ≈ 1000，相对误差 ≤ 2^-7。
  let rel = if v > 1000.0 { v / 1000.0 - 1.0 } else { 1.0 - v / 1000.0 }
  assert_true(rel <= 1.0 / 128.0 + 1.0e-9)
}

///|
/// 精确分位（排序取 rank = round(pct/100*n) 的第 rank 小，与直方图语义一致）。
fn exact_pct(data : Array[Int64], pct : Double) -> Int64 {
  let s = data.copy()
  s.sort()
  let mut rank = (pct / 100.0 * s.length().to_double() + 0.5).to_int()
  if rank < 1 {
    rank = 1
  }
  if rank > s.length() {
    rank = s.length()
  }
  s[rank - 1]
}

///|
test "E5 property: hdr percentile relative error ≤ 2^-p (60 iters)" {
  let rng = @infra_pbt.rng_new(20260716)
  for _iter in 0..<60 {
    let ps = [4, 7, 10]
    let p = ps[rng.next_below(3)]
    let bound = 1.0 / (1 << p).to_double()
    let h = @infra_metrics.HdrHistogram::new(p)
    let data : Array[Int64] = []
    let n = 500 + rng.next_below(1500)
    // 混合值域：微秒级延迟 1..10^3 与重尾 10^6..10^9。
    for _ in 0..<n {
      let heavy = rng.next_below(4) == 0
      let v = if heavy {
        (1_000_000 + rng.next_below(1_000_000_000)).to_int64()
      } else {
        (1 + rng.next_below(1000)).to_int64()
      }
      data.push(v)
      h.record(v)
    }
    assert_eq(h.count(), n)
    for pct in [1.0, 25.0, 50.0, 75.0, 90.0, 99.0, 99.9, 100.0] {
      let approx = match h.value_at_percentile(pct) {
        Some(x) => x.to_double()
        None => -1.0
      }
      let exact = exact_pct(data, pct).to_double()
      let rel = if approx > exact {
        approx / exact - 1.0
      } else {
        1.0 - approx / exact
      }
      assert_true(rel <= bound + 1.0e-9)
    }
  }
}
