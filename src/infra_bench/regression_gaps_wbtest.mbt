// 白盒测试：覆盖率审计收口（INFRA 第六十三批）——
// 回归判定加速比零中位数、基线重名去重与当前侧缺失算法余支。

///|
fn gaps_stats(median : Double) -> BenchStats {
  {
    min: median,
    max: median,
    median,
    mean: median,
    p95: median,
    stddev: 0.0,
    sample_count: 1,
  }
}

///|
fn gaps_case(algorithm : String, median : Double) -> BenchCase {
  {
    algorithm,
    graph_size: 1,
    edge_count: 1,
    query_count: 1,
    seed: 1UL,
    raw_ns: [median],
    stats: gaps_stats(median),
  }
}

///|
fn gaps_report(cases : Array[BenchCase]) -> BenchReport {
  {
    moon_version: "test",
    backend: "wasm-gc",
    os: "linux",
    cpu: "test",
    generator: "test",
    warmup_count: 0,
    cases,
  }
}

///|
test "regression_check：当前中位数为零时加速比为 None" {
  let verdicts = regression_check(
    gaps_report([gaps_case("a", 0.0)]),
    gaps_report([gaps_case("a", 0.0)]),
    10.0,
  )
  assert_eq(verdicts.length(), 1)
  // baseline_median 为零 → regression_pct 取 0.0 分支。
  assert_eq(verdicts[0].regression_pct, 0.0)
  assert_true(verdicts[0].speedup() is None)
}

///|
test "regression_check：基线重名仅取首个且当前缺失算法跳过" {
  let baseline = gaps_report([
    gaps_case("a", 10.0),
    gaps_case("a", 20.0),
    gaps_case("missing", 5.0),
  ])
  let current = gaps_report([gaps_case("a", 11.0)])
  let verdicts = regression_check(baseline, current, 50.0)
  assert_eq(verdicts.length(), 1)
  assert_eq(verdicts[0].baseline_median, 10.0)
  assert_true(verdicts[0].speedup() is Some(_))
}
