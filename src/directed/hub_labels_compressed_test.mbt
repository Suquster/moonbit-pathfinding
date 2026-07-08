// hub_labels_compressed_test.mbt —— 压缩标签黑盒测试：
// 与未压缩 HubLabels 查询逐点一致 + 体积确实缩减。

///|
test "CompressedHubLabels 基本链与不可达" {
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (1, 2, 3),
    (2, 3, 4),
    (0, 3, 10),
  ]
  let g = @directed.WeightedCsr::from_edges(4, edges)
  let ch = @directed.ContractionHierarchy::build(g)
  let hl = @directed.HubLabels::build(ch)
  let chl = hl.compress()
  assert_true(chl.query(0, 3) is Some(9L))
  assert_true(chl.query(0, 0) is Some(0L))
  assert_true(chl.query(3, 0) is None)
}

///|
test "CompressedHubLabels 差分 PBT：与 HubLabels 全对拍（120 迭代）" {
  let rng = @infra_pbt.rng_new(0xC0FFEE42UL)
  for it in 0..<120 {
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
    let chl = hl.compress()
    for s in 0..<n {
      for t in 0..<n {
        assert_true(hl.query(s, t) == chl.query(s, t))
      }
    }
  }
}

///|
test "CompressedHubLabels 体积：字节流显著小于 8 字节/条打包存储" {
  // 网格图（路网形态近似）上验证压缩率。
  let side = 18
  let n = side * side
  let edges : Array[(Int, Int, Int)] = []
  for r in 0..<side {
    for c in 0..<side {
      let v = r * side + c
      if c + 1 < side {
        edges.push((v, v + 1, 1 + v * 7 % 13))
        edges.push((v + 1, v, 1 + v * 5 % 11))
      }
      if r + 1 < side {
        edges.push((v, v + side, 1 + v * 3 % 17))
        edges.push((v + side, v, 1 + v * 11 % 7))
      }
    }
  }
  let g = @directed.WeightedCsr::from_edges(n, edges)
  let ch = @directed.ContractionHierarchy::build(g)
  let hl = @directed.HubLabels::build(ch)
  let chl = hl.compress()
  let entries = (hl.avg_label_size() * (2 * n).to_double()).to_int()
  let packed_bytes = entries * 8
  // 至少压掉一半。
  assert_true(chl.label_bytes() * 2 < packed_bytes)
  // 抽样查询一致。
  let rng = @infra_pbt.rng_new(7UL)
  for _ in 0..<200 {
    let s = rng.next_below(n)
    let t = rng.next_below(n)
    assert_true(hl.query(s, t) == chl.query(s, t))
  }
}
