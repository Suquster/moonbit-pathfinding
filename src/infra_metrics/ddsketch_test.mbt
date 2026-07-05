// ddsketch_test.mbt —— DDSketch 黑盒测试：定向（零值/单调/合并）+ 误差界
// 证明式 PBT（随机分布下任意分位相对误差 ≤ α，对照精确排序分位）。

///|
test "ddsketch basic: empty / zeros / single value" {
  let s = @infra_metrics.DDSketch::new(0.01)
  assert_true(s.quantile(0.5) == None)
  assert_eq(s.count(), 0)
  s.add(0.0)
  s.add(-3.0) // 负值归 0
  assert_eq(s.count(), 2)
  assert_true(s.quantile(0.5) == Some(0.0))
  let t = @infra_metrics.DDSketch::new(0.01)
  t.add(100.0)
  let v = match t.quantile(0.5) {
    Some(x) => x
    None => -1.0
  }
  // 单值相对误差 ≤ α。
  let rel = if v > 100.0 { v / 100.0 - 1.0 } else { 1.0 - v / 100.0 }
  assert_true(rel <= 0.01 + 1.0e-9)
}

///|
test "ddsketch merge preserves counts and quantiles" {
  let a = @infra_metrics.DDSketch::new(0.02)
  let b = @infra_metrics.DDSketch::new(0.02)
  for i in 1..<=500 {
    a.add(i.to_double())
  }
  for i in 501..<=1000 {
    b.add(i.to_double())
  }
  a.merge_with(b)
  assert_eq(a.count(), 1000)
  // 合并后 p50 ≈ 500，相对误差 ≤ α。
  let v = match a.quantile(0.5) {
    Some(x) => x
    None => -1.0
  }
  let exact = 500.0
  let rel = if v > exact { v / exact - 1.0 } else { 1.0 - v / exact }
  assert_true(rel <= 0.02 + 1.0e-9)
}

///|
/// 精确分位（排序后取 rank = floor(q*(n-1))+1 的第 rank 小值，与 sketch 的
/// rank 语义一致）。
fn exact_quantile(data : Array[Double], q : Double) -> Double {
  let s = data.copy()
  s.sort()
  let rank = (q * (s.length() - 1).to_double()).to_int()
  s[rank]
}

///|
test "E5 property: ddsketch relative error ≤ α over random distributions (60 iters)" {
  let rng = @infra_pbt.rng_new(20260711)
  for _iter in 0..<60 {
    // α ∈ {0.005, 0.01, 0.02, 0.05}。
    let alphas = [0.005, 0.01, 0.02, 0.05]
    let alpha = alphas[rng.next_below(4)]
    let sk = @infra_metrics.DDSketch::new(alpha)
    let data : Array[Double] = []
    let n = 500 + rng.next_below(1500)
    // 混合分布：均匀 [1,10^4]、指数样重尾（幂次放大）。
    let heavy = rng.next_below(2) == 1
    for _ in 0..<n {
      let u = (1 + rng.next_below(10000)).to_double()
      let x = if heavy { u * u / 10000.0 + 1.0 } else { u }
      data.push(x)
      sk.add(x)
    }
    assert_eq(sk.count(), n)
    for q in [0.01, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99, 1.0] {
      let approx = match sk.quantile(q) {
        Some(v) => v
        None => -1.0
      }
      let exact = exact_quantile(data, q)
      let rel = if approx > exact {
        approx / exact - 1.0
      } else {
        1.0 - approx / exact
      }
      // 论文定理 1：相对误差 ≤ α（留 1e-9 浮点余量）。
      assert_true(rel <= alpha + 1.0e-9)
    }
  }
}

///|
test "E5 property: merged sketch keeps error bound (40 iters)" {
  let rng = @infra_pbt.rng_new(20260712)
  for _iter in 0..<40 {
    let alpha = 0.01
    let a = @infra_metrics.DDSketch::new(alpha)
    let b = @infra_metrics.DDSketch::new(alpha)
    let data : Array[Double] = []
    let n = 400 + rng.next_below(800)
    for i in 0..<n {
      let x = (1 + rng.next_below(100000)).to_double()
      data.push(x)
      if i % 2 == 0 {
        a.add(x)
      } else {
        b.add(x)
      }
    }
    a.merge_with(b)
    assert_eq(a.count(), n)
    for q in [0.5, 0.9, 0.99] {
      let approx = match a.quantile(q) {
        Some(v) => v
        None => -1.0
      }
      let exact = exact_quantile(data, q)
      let rel = if approx > exact {
        approx / exact - 1.0
      } else {
        1.0 - approx / exact
      }
      assert_true(rel <= alpha + 1.0e-9)
    }
  }
}
