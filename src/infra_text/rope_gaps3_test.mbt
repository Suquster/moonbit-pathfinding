// rope_gaps3_test.mbt —— 多叶 rope 的 UTF-16→UTF-8 偏移右子树下降收口
// （INFRA 第二十九批）。

///|
test "utf16_to_utf8：多叶 rope 偏移跨越左子树累加右下降" {
  let r = @infra_text.Rope::from_string("héllo")
  // 追加多个大段使根为 Concat（多叶结构，超过叶容量阈值）。
  let sb = StringBuilder::new()
  for _ in 0..<400 {
    sb.write_string("段落\u{1F600}chunk")
  }
  let big = sb.to_string()
  for _ in 0..<4 {
    r.insert(r.len(), big)
  }
  assert_true(r.leaf_count() > 1)
  // 偏移落在末尾附近 → 必然穿越左子树（acc + lm.u8 右下降路径）。
  let n = r.len()
  let full = r.utf16_to_utf8(n)
  assert_eq(full, r.utf8_len())
  let mid = r.utf16_to_utf8(n - 2)
  assert_true(mid > 0 && mid <= full)
  // 往返一致性（字符边界处）。
  assert_eq(r.utf8_to_utf16(full), n)
}

///|
test "slice：空区间与全区间边界" {
  let r = @infra_text.Rope::from_string("abcdef")
  assert_eq(r.slice(3, 3), "")
  assert_eq(r.slice(0, 6), "abcdef")
}
