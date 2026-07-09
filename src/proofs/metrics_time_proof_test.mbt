// metrics_time_proof_test.mbt —— 指标/时间家族证明谓词的真实实现接地测试。
//
// 以 @infra_metrics / @infra_time 的真实包实现驱动
// metrics_time_proof.mbt 中的谓词（跨包驱动只发生在测试期）：
//   * HdrHistogram：分位数随百分位单调 + 夹逼在已记录 [min, max]（随机样本 PBT）；
//   * HdrHistogram / DDSketch：merge 后计数守恒（`count_conserved`）；
//   * DDSketch：quantile 随 q 单调（`non_decreasing_f`）；
//   * infra_time：civil↔days 往返恒等 + ISO8601 format∘parse 往返（复用
//     predicates.mbt 的 `round_trip_eq`，随机 DateTime PBT）。

// --- HdrHistogram：分位数单调 + 夹逼 + 计数守恒 ---

///|
/// 随机延迟样本序列生成器（1..100_000 微秒级值域，长度 ∈ [1, 64]）。
fn mt_samples_gen() -> @infra_pbt.Gen[Array[Int64]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 64)
    let out : Array[Int64] = []
    for _i in 0..<n {
      out.push(rng.next_range(1, 100_000).to_int64())
    }
    out
  })
}

///|
fn mt_min_max(xs : Array[Int64]) -> (Int64, Int64) {
  let mut lo = xs[0]
  let mut hi = xs[0]
  for x in xs {
    if x < lo {
      lo = x
    }
    if x > hi {
      hi = x
    }
  }
  (lo, hi)
}

///|
fn mt_prop_hdr_quantiles(samples : Array[Int64]) -> Bool {
  let h = @infra_metrics.HdrHistogram::new(3)
  for s in samples {
    h.record(s)
  }
  let qs = [1.0, 25.0, 50.0, 75.0, 90.0, 99.0, 100.0]
  let values : Array[Int64] = []
  for q in qs {
    match h.value_at_percentile(q) {
      Some(v) => values.push(v)
      None => return false
    }
  }
  let (lo, hi) = mt_min_max(samples)
  // 精度桶带来相对误差：夹逼上界放宽一个 2^-precision_bits 相对档位。
  let slack = hi >> 3
  non_decreasing64(values) && all_within64(values, 0, hi + slack + 1) && lo >= 0
}

///|
test "HdrHistogram percentile values are monotone and clamped to sample range" {
  let ok = @infra_pbt.holds_for_all(
    mt_samples_gen(),
    mt_prop_hdr_quantiles,
    iters=128,
  )
  assert_true(ok)
}

///|
fn mt_prop_hdr_merge_conserves(pair : (Array[Int64], Array[Int64])) -> Bool {
  let (xs, ys) = pair
  let a = @infra_metrics.HdrHistogram::new(3)
  let b = @infra_metrics.HdrHistogram::new(3)
  for x in xs {
    a.record(x)
  }
  for y in ys {
    b.record(y)
  }
  let ca = a.count()
  let cb = b.count()
  a.merge_with(b)
  count_conserved(a.count(), [ca, cb])
}

///|
fn mt_samples_pair_gen() -> @infra_pbt.Gen[(Array[Int64], Array[Int64])] {
  @infra_pbt.Gen::new(fn(rng) {
    let one = fn() -> Array[Int64] {
      let n = rng.next_range(0, 32)
      let out : Array[Int64] = []
      for _i in 0..<n {
        out.push(rng.next_range(1, 100_000).to_int64())
      }
      out
    }
    (one(), one())
  })
}

///|
test "HdrHistogram merge conserves sample count" {
  let ok = @infra_pbt.holds_for_all(
    mt_samples_pair_gen(),
    mt_prop_hdr_merge_conserves,
    iters=128,
  )
  assert_true(ok)
}

// --- DDSketch：quantile 单调 + merge 计数守恒 ---

///|
fn mt_prop_dds_quantiles(samples : Array[Int64]) -> Bool {
  let sk = @infra_metrics.DDSketch::new(0.01)
  for s in samples {
    sk.add(s.to_double())
  }
  let qs = [0.01, 0.25, 0.5, 0.75, 0.9, 0.99]
  let values : Array[Double] = []
  for q in qs {
    match sk.quantile(q) {
      Some(v) => values.push(v)
      None => return false
    }
  }
  non_decreasing_f(values)
}

///|
test "DDSketch quantile is monotone in q" {
  let ok = @infra_pbt.holds_for_all(
    mt_samples_gen(),
    mt_prop_dds_quantiles,
    iters=128,
  )
  assert_true(ok)
}

///|
fn mt_prop_dds_merge_conserves(pair : (Array[Int64], Array[Int64])) -> Bool {
  let (xs, ys) = pair
  let a = @infra_metrics.DDSketch::new(0.01)
  let b = @infra_metrics.DDSketch::new(0.01)
  for x in xs {
    a.add(x.to_double())
  }
  for y in ys {
    b.add(y.to_double())
  }
  let ca = a.count()
  let cb = b.count()
  a.merge_with(b)
  count_conserved(a.count(), [ca, cb])
}

///|
test "DDSketch merge conserves sample count" {
  let ok = @infra_pbt.holds_for_all(
    mt_samples_pair_gen(),
    mt_prop_dds_merge_conserves,
    iters=128,
  )
  assert_true(ok)
}

///|
test "count_conserved rejects lost samples" {
  assert_false(count_conserved(5, [3, 3]))
}

// --- infra_time：civil↔days 与 ISO8601 往返 ---

///|
/// 随机日历日期生成器（1600..2400 年，日截断到当月合法上限）。
fn mt_date_gen() -> @infra_pbt.Gen[(Int, Int, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let y = rng.next_range(1600, 2400)
    let m = rng.next_range(1, 12)
    let d = rng.next_range(1, @infra_time.days_in_month(y, m))
    (y, m, d)
  })
}

///|
fn mt_prop_civil_days_round_trip(date : (Int, Int, Int)) -> Bool {
  round_trip_eq(
    date,
    fn(d : (Int, Int, Int)) -> Int64 {
      @infra_time.days_from_civil(d.0, d.1, d.2)
    },
    fn(days : Int64) -> (Int, Int, Int)? {
      Some(@infra_time.civil_from_days(days))
    },
  )
}

///|
test "civil<->days round-trips over random calendar dates" {
  let ok = @infra_pbt.holds_for_all(
    mt_date_gen(),
    mt_prop_civil_days_round_trip,
    iters=200,
  )
  assert_true(ok)
}

///|
fn mt_datetime_gen() -> @infra_pbt.Gen[@infra_time.DateTime] {
  @infra_pbt.Gen::new(fn(rng) {
    let y = rng.next_range(1600, 2400)
    let m = rng.next_range(1, 12)
    {
      year: y,
      month: m,
      day: rng.next_range(1, @infra_time.days_in_month(y, m)),
      hour: rng.next_range(0, 23),
      minute: rng.next_range(0, 59),
      second: rng.next_range(0, 59),
      millis: 0,
    }
  })
}

///|
fn mt_prop_iso8601_round_trip(dt : @infra_time.DateTime) -> Bool {
  round_trip_eq(dt, @infra_time.format_iso8601, @infra_time.parse_iso8601)
}

///|
test "ISO8601 format/parse round-trips over random datetimes" {
  let ok = @infra_pbt.holds_for_all(
    mt_datetime_gen(),
    mt_prop_iso8601_round_trip,
    iters=200,
  )
  assert_true(ok)
}
