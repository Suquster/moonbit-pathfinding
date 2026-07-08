// 白盒测试：roaring 位图内部位运算边界与位图容器重复路径。

///|
test "roaring：trailing_zeros 零输入与 popcount64 全量" {
  assert_eq(trailing_zeros(0UL), 64)
  assert_eq(trailing_zeros(1UL), 0)
  assert_eq(popcount64(0UL), 0)
  assert_eq(popcount64(0xFFFFFFFFFFFFFFFFUL), 64)
  assert_eq(popcount64(0x8000000000000001UL), 2)
}

///|
test "roaring：位图容器重复 add / remove 命中分支" {
  let rb = RoaringBitmap::new()
  // 超过阈值升级为位图容器。
  let mut i = 0
  while i < 5000 {
    let _ = rb.add(i)
    i = i + 1
  }
  // 位图容器中重复 add 返回 false。
  assert_false(rb.add(100))
  assert_true(rb.contains(100))
  assert_true(rb.remove(100))
  assert_false(rb.contains(100))
  assert_true(rb.add(100))
}
