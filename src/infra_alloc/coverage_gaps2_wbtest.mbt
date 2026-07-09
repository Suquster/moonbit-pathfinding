// 白盒测试：Slab 越界键与双重释放防御。

///|
test "slab：越界键 get/set/free 拒绝" {
  let s : Slab[Int] = Slab::new()
  let k = s.alloc(7)
  let bad : SlabKey = { index: 99, generation: 0 }
  assert_true(s.get(bad) is None)
  assert_eq(s.set(bad, 1), false)
  assert_true(s.free(bad) is None)
  assert_true(s.free(k) is Some(7))
}
