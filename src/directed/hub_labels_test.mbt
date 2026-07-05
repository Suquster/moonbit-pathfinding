// hub_labels_test.mbt —— Hub Labeling 黑盒测试：基本用例 +
// 与 Dijkstra 的差分 PBT（大/小权、不可达全对拍）。

///|
test "HubLabels 基本链 + 不可达" {
  // 0→1→2→3 权 2/3/4，另 0→3 权 10（应取 9）。
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (1, 2, 3),
    (2, 3, 4),
    (0, 3, 10),
  ]
  let g = @directed.WeightedCsr::from_edges(4, edges)
  let ch = @directed.ContractionHierarchy::build(g)
  let hl = @directed.HubLabels::build(ch)
  assert_true(hl.query(0, 3) is Some(9L))
  assert_true(hl.query(0, 0) is Some(0L))
  assert_true(hl.query(3, 0) is None)
  assert_true(hl.avg_label_size() >= 1.0)
}

///|
test "HubLabels 差分 PBT：随机图 vs Dijkstra 全对拍（100 迭代，大/小权）" {
  let rng = @infra_pbt.rng_new(0xB0B1ABE15UL)
  for it in 0..<100 {
    let n = 2 + rng.next_below(40)
    let m = rng.next_below(4 * n + 1)
    let big = it % 3 == 0
    let edges : Array[(Int, Int, Int)] = []
    for _ in 0..<m {
      let u = rng.next_below(n)
      let v = rng.next_below(n)
      let w = if big {
        1 + rng.next_below(100000) * 97
      } else {
        1 + rng.next_below(64)
      }
      edges.push((u, v, w))
    }
    let g = @directed.WeightedCsr::from_edges(n, edges)
    let ch = @directed.ContractionHierarchy::build(g)
    let hl = @directed.HubLabels::build(ch)
    let ctx = @directed.SearchCtx::new(n)
    for _ in 0..<8 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      let base = @directed.dijkstra_indexed_ctx(g, ctx, s, t)
      let got = hl.query(s, t)
      match (base, got) {
        (Some((_, c)), Some(d)) => assert_eq(c.to_int64(), d)
        (None, None) => ()
        _ => abort("HL 可达性与 Dijkstra 不一致")
      }
    }
  }
}
