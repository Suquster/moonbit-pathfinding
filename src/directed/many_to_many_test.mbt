// many_to_many_test.mbt —— many-to-many 距离表：基本用例 +
// 与逐对 Dijkstra 的差分 PBT。

///|
test "many_to_many 基本用例" {
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (1, 2, 3),
    (2, 3, 4),
    (0, 3, 100),
    (3, 4, 1),
  ]
  let g = @directed.WeightedCsr::from_edges(5, edges)
  let ch = @directed.ContractionHierarchy::build(g)
  let s = [0, 1]
  let t = [3, 4, 0]
  let d = ch.many_to_many(s, t)
  // 行主序：行 i=0（源 0）
  assert_eq(d[0], 9L) // 0->3
  assert_eq(d[1], 10L) // 0->4
  assert_eq(d[2], 0L) // 0->0
  // 行 i=1（源 1）
  assert_eq(d[3], 7L) // 1->3
  assert_eq(d[4], 8L) // 1->4
  assert_true(@directed.ContractionHierarchy::is_unreachable(d[5])) // 1->0
}

///|
test "many_to_many 差分 PBT：随机图 vs 逐对 Dijkstra（60 迭代）" {
  let rng = @infra_pbt.rng_new(0x2E44_2026UL)
  for it in 0..<60 {
    let n = 2 + rng.next_below(36)
    let m = rng.next_below(4 * n + 1)
    let big = it % 3 == 0
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<m {
      let u = rng.next_below(n)
      let v = rng.next_below(n)
      let w = if big {
        1 + rng.next_below(100000) * 89
      } else {
        1 + rng.next_below(64)
      }
      edges.push((u, v, w))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let ch = @directed.ContractionHierarchy::build(g)
    let ctx = @directed.SearchCtx::new(n)
    let ss : Array[Int] = []
    let ts : Array[Int] = []
    let nsrc = 1 + rng.next_below(4)
    let ntgt = 1 + rng.next_below(4)
    for _ in 0..<nsrc {
      ss.push(rng.next_below(n))
    }
    for _ in 0..<ntgt {
      ts.push(rng.next_below(n))
    }
    let d = ch.many_to_many(ss, ts)
    for i in 0..<ss.length() {
      for j in 0..<ts.length() {
        let got = d[i * ts.length() + j]
        match @directed.dijkstra_indexed_ctx(g, ctx, ss[i], ts[j]) {
          Some((_, c)) => assert_eq(got, c.to_int64())
          None =>
            assert_true(@directed.ContractionHierarchy::is_unreachable(got))
        }
      }
    }
  }
}
