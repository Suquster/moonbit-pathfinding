// rope_gaps2_test.mbt —— Rope 行列换算与切片余支收口（INFRA 第六十一批）。

///|
test "Rope：空串构造与空区间切片" {
  let r = @infra_text.Rope::from_string("")
  assert_eq(r.to_string(), "")
  let s = @infra_text.Rope::from_string("hello")
  assert_eq(s.slice(3, 3), "")
  assert_eq(s.slice(4, 2), "")
}

///|
test "Rope：大文本 Concat 结构下行列换算" {
  let sb = StringBuilder::new()
  for i in 0..<400 {
    sb.write_string("line-\{i} content padding\n")
  }
  let r = @infra_text.Rope::from_string(sb.to_string())
  let off = r.offset_of_line(300)
  let (line, col) = r.line_col_at(off)
  assert_eq(line, 300)
  assert_eq(col, 0)
  let (l2, c2) = r.line_col_at(off + 5)
  assert_eq(l2, 300)
  assert_eq(c2, 5)
}
