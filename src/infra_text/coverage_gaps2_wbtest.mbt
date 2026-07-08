// 白盒测试：piece_table 删除钳制、unicode 零码点宽度、rope 空串叶子。

///|
test "piece_table：负偏移钳制与空区间删除直返" {
  let pt = PieceTable::from_string("hello")
  pt.delete(-3, 2) // lo 钳制到 0。
  assert_eq(pt.to_string(), "llo")
  pt.delete(1, 0) // 空区间：直接返回。
  assert_eq(pt.to_string(), "llo")
  pt.delete(2, 99) // hi 钳制到 total。
  assert_eq(pt.to_string(), "ll")
}

///|
test "unicode：NUL 码点宽度为 0" {
  assert_eq(codepoint_width(0), 0)
  assert_eq(codepoint_width(0x41), 1)
}

///|
test "rope：空串切叶与平衡构建" {
  let leaves = chunk_leaves("")
  assert_eq(leaves.length(), 1)
  let r : Rope = { root: build_balanced(leaves) }
  assert_eq(r.to_string(), "")
}
