// samplers_test.mbt —— T7.3 OTel 采样器对标的黑盒验证。
//
// 覆盖 OTel SDK 规范内置采样器的关键语义：
//   * AlwaysOn / AlwaysOff 边界；
//   * TraceIdRatio：trace 一致性（同 trace 恒定）、决策确定性、
//     命中率分布收敛（10_000 条随机 trace 的命中率与 rate 偏差 < 2%）、
//     单调性（rate 越大保留集只增不减，同 seed 下）；
//   * ParentBased：父决策优先（父采则采、父弃则弃）、根 span 委托 root、
//     嵌套 ParentBased 下钻。

///|
test "Feature: logging, Contract: AlwaysOn/AlwaysOff samplers are constant" {
  let t : TraceId = { value: 7L }
  assert_true(Sampler::AlwaysOn.should_sample(None, t, 1UL))
  assert_true(Sampler::AlwaysOn.should_sample(Some(false), t, 1UL))
  assert_true(!Sampler::AlwaysOff.should_sample(None, t, 1UL))
  assert_true(!Sampler::AlwaysOff.should_sample(Some(true), t, 1UL))
}

///|
test "Feature: logging, Contract: ParentBased honors parent decision, delegates root" {
  let t : TraceId = { value: 99L }
  let pb = Sampler::ParentBased(AlwaysOff)
  // 父决策优先：父采则采（即使 root 恒弃），父弃则弃。
  assert_true(pb.should_sample(Some(true), t, 0UL))
  assert_true(!pb.should_sample(Some(false), t, 0UL))
  // 根 span 委托 root。
  assert_true(!pb.should_sample(None, t, 0UL))
  assert_true(Sampler::ParentBased(AlwaysOn).should_sample(None, t, 0UL))
  // 嵌套 ParentBased：一路下钻到非 ParentBased 根。
  let nested = Sampler::ParentBased(ParentBased(AlwaysOn))
  assert_true(nested.should_sample(None, t, 0UL))
}

///|
test "Feature: logging, Contract: TraceIdRatio is trace-coherent and deterministic" {
  let s = Sampler::TraceIdRatio(0.5)
  let rng = @infra_pbt.rng_new(7UL)
  for _ in 0..<200 {
    let t : TraceId = { value: rng.next_range(0, 1 << 30).to_int64() }
    let d1 = s.should_sample(None, t, 42UL)
    // 同 trace 恒定（父决策不参与 TraceIdRatio）且两次判定一致。
    assert_true(d1 == s.should_sample(None, t, 42UL))
    assert_true(d1 == s.should_sample(Some(!d1), t, 42UL))
  }
}

///|
test "Feature: logging, Property: TraceIdRatio hit rate converges to rate within 2%" {
  let rates = [0.1, 0.25, 0.5, 0.9]
  for rate in rates {
    let s = Sampler::TraceIdRatio(rate)
    let rng = @infra_pbt.rng_new(20260705UL)
    let n = 10_000
    let mut hits = 0
    for _ in 0..<n {
      let t : TraceId = { value: rng.next_range(0, 1 << 30).to_int64() }
      if s.should_sample(None, t, 1UL) {
        hits = hits + 1
      }
    }
    let observed = hits.to_double() / n.to_double()
    let diff = if observed > rate { observed - rate } else { rate - observed }
    assert_true(diff < 0.02)
  }
}

///|
test "Feature: logging, Property: TraceIdRatio retained set is monotone in rate" {
  // 同 seed 下 rate 越大保留集只增不减：keep(r1) ⊆ keep(r2) 当 r1 <= r2。
  // 这是 OTel TraceIdRatioBased 的可组合性基石（阈值比较的单调性）。
  let rng = @infra_pbt.rng_new(11UL)
  for _ in 0..<300 {
    let t : TraceId = { value: rng.next_range(0, 1 << 30).to_int64() }
    let mut prev = false
    for rate in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0] {
      let cur = Sampler::TraceIdRatio(rate).should_sample(None, t, 5UL)
      // prev=true 时 cur 必为 true（单调）。
      assert_true(!prev || cur)
      prev = cur
    }
  }
}
