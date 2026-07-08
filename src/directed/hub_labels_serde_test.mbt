// hub_labels_serde_test.mbt —— 压缩标签序列化黑盒测试：
// 无损往返 + 查询语义保持（差分 PBT）+ 畸形/翻位输入拒绝。

///|
test "CompressedHubLabels 序列化基本往返" {
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
  let bytes = chl.to_bytes()
  guard @directed.CompressedHubLabels::from_bytes(bytes) is Some(back)
  assert_true(back.query(0, 3) is Some(9L))
  assert_true(back.query(0, 0) is Some(0L))
  assert_true(back.query(3, 0) is None)
  assert_eq(back.label_bytes(), chl.label_bytes())
}

///|
test "CompressedHubLabels 序列化差分 PBT：往返后与原标签全对拍（100 迭代）" {
  let rng = @infra_pbt.rng_new(0x5EEDCAFEUL)
  for it in 0..<100 {
    let n = 2 + rng.next_below(32)
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
    guard @directed.CompressedHubLabels::from_bytes(chl.to_bytes())
      is Some(back)
    for _ in 0..<12 {
      let s = rng.next_below(n)
      let t = rng.next_below(n)
      assert_true(back.query(s, t) == chl.query(s, t))
    }
  }
}

///|
test "CompressedHubLabels 序列化拒绝畸形输入" {
  // 太短 / 空流。
  assert_true(@directed.CompressedHubLabels::from_bytes([]) is None)
  assert_true(@directed.CompressedHubLabels::from_bytes([72, 76, 67]) is None)
  let edges : Array[(Int, Int, Int)] = [(0, 1, 5), (1, 2, 7)]
  let g = @directed.WeightedCsr::from_edges(3, edges)
  let ch = @directed.ContractionHierarchy::build(g)
  let chl = @directed.HubLabels::build(ch).compress()
  let good = chl.to_bytes()
  // magic 破坏。
  let bad_magic = good.copy()
  bad_magic[0] = 88
  assert_true(@directed.CompressedHubLabels::from_bytes(bad_magic) is None)
  // 截断（去掉尾部校验和之前的一个字节）。
  let truncated = good.copy()
  let _ = truncated.pop()
  assert_true(@directed.CompressedHubLabels::from_bytes(truncated) is None)
  // 逐位翻转体内每个字节，必须全部被校验和拒绝或解出同义标签——
  // 这里断言更强的性质：任何单字节 +1 翻改都被拒绝。
  let rng = @infra_pbt.rng_new(0xB17F11BUL)
  for _ in 0..<40 {
    let mutated = good.copy()
    let idx = rng.next_below(mutated.length())
    mutated[idx] = (mutated[idx] + 1) % 256
    assert_true(@directed.CompressedHubLabels::from_bytes(mutated) is None)
  }
}
