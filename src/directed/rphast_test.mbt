// rphast_test.mbt —— RPHAST 黑盒测试：基本用例 + 与逐对
// Dijkstra 的差分 PBT（多源复用同一目标集预处理）。

///|
test "RPHAST 基本用例（多源复用目标集预处理）" {
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (1, 2, 3),
    (2, 3, 4),
    (0, 3, 100),
    (3, 4, 1),
  ]
  let g = @directed.WeightedCsr::from_edges(5, edges)
  let ch = @directed.ContractionHierarchy::build(g)
  let rt = ch.rphast_targets([3, 4, 0])
  let out = Array::make(3, 0L)
  ch.rphast_query(rt, 0, out)
  assert_eq(out[0], 9L)
  assert_eq(out[1], 10L)
  assert_eq(out[2], 0L)
  ch.rphast_query(rt, 1, out)
  assert_eq(out[0], 7L)
  assert_eq(out[1], 8L)
  assert_true(@directed.ContractionHierarchy::is_unreachable(out[2]))
}

///|
test "RPHAST 差分 PBT：随机图多源 vs 逐对 Dijkstra（60 迭代）" {
  let rng = @infra_pbt.rng_new(0x5271_2026UL)
  for it in 0..<60 {
    let n = 2 + rng.next_below(36)
    let m = rng.next_below(4 * n + 1)
    let big = it % 3 == 0
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<m {
      let u = rng.next_below(n)
      let v = rng.next_below(n)
      let w = if big {
        1 + rng.next_below(100000) * 83
      } else {
        1 + rng.next_below(64)
      }
      edges.push((u, v, w))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let ch = @directed.ContractionHierarchy::build(g)
    let ctx = @directed.SearchCtx::new(n)
    let ts : Array[Int] = []
    for _ in 0..<(1 + rng.next_below(4)) {
      ts.push(rng.next_below(n))
    }
    let rt = ch.rphast_targets(ts)
    let out = Array::make(ts.length(), 0L)
    for _ in 0..<3 {
      let s = rng.next_below(n)
      ch.rphast_query(rt, s, out)
      for j in 0..<ts.length() {
        match @directed.dijkstra_indexed_ctx(g, ctx, s, ts[j]) {
          Some((_, c)) => assert_eq(out[j], c.to_int64())
          None =>
            assert_true(@directed.ContractionHierarchy::is_unreachable(out[j]))
        }
      }
    }
  }
}
