// roaring_gaps_test.mbt —— Roaring 位图容器两态转换与集合运算覆盖收口
// （INFRA 第十八批）：数组↔位图升降级、并/交各容器组合、块键归并尾段的
// 确定性见证。

///|
/// 造一个含 n 个偶数元素（0,2,4,...）的位图（n>4096 时为位图容器）。
fn rb_dense(n : Int, base : Int) -> RoaringBitmap {
  let r = RoaringBitmap::new()
  for i in 0..<n {
    let _ = r.add(base + i * 2)
  }
  r
}

///|
test "roaring 容器升降级与删除路径" {
  // 数组容器删除到空 → 容器移除。
  let r = RoaringBitmap::new()
  assert_true(r.add(5))
  assert_true(r.remove(5))
  assert_true(r.cardinality() == 0)
  assert_true(r.remove(5) == false)
  // 位图容器（>4096 元素）删除一个 → 降级判定路径。
  let big = rb_dense(5000, 0)
  assert_true(big.cardinality() == 5000)
  assert_true(big.contains(4998))
  assert_true(big.remove(4998))
  assert_true(big.contains(4998) == false)
  // 位图容器中删除不存在位。
  assert_true(big.remove(4999) == false)
  // 降到阈值以下 → 数组容器化后仍语义一致。
  let shrink = rb_dense(4200, 0)
  for i in 0..<200 {
    assert_true(shrink.remove(i * 2))
  }
  assert_true(shrink.cardinality() == 4000)
  assert_true(shrink.contains(398) == false)
  assert_true(shrink.contains(400))
}

///|
test "roaring 并集各容器组合" {
  // 数组∪数组 溢出阈值 → 位图容器。
  let a = rb_dense(3000, 0)
  let b = rb_dense(3000, 1) // 奇数 → 与 a 互不相交
  let u = a.union_with(b)
  assert_true(u.cardinality() == 6000)
  assert_true(u.contains(0) && u.contains(1))
  // 位图∪位图 / 位图∪数组（container_to_words 两臂）。
  let big1 = rb_dense(5000, 0)
  let big2 = rb_dense(5000, 1)
  let uu = big1.union_with(big2)
  assert_true(uu.cardinality() == 10000)
  let small = rb_dense(10, 1)
  let mixed = big1.union_with(small)
  assert_true(mixed.cardinality() == 5010)
  // 不同块键的尾段拼接（65536 一块）。
  let hi = rb_dense(10, 65536 * 2)
  let tails = small.union_with(hi)
  assert_true(tails.cardinality() == 20)
  assert_true(hi.union_with(small).cardinality() == 20)
}

///|
test "roaring 交集各容器组合与空结果" {
  // 数组∩位图（混合臂）。
  let big = rb_dense(5000, 0)
  let small = rb_dense(100, 0)
  let x = small.intersect_with(big)
  assert_true(x.cardinality() == 100)
  assert_true(big.intersect_with(small).cardinality() == 100)
  // 位图∩位图：非空与全空（None 分支）。
  let big2 = rb_dense(5000, 0)
  assert_true(big.intersect_with(big2).cardinality() == 5000)
  let odd = rb_dense(5000, 1)
  assert_true(big.intersect_with(odd).cardinality() == 0)
  // 数组∩数组：全空 → 容器不产出。
  let a = rb_dense(10, 0)
  let b = rb_dense(10, 1)
  assert_true(a.intersect_with(b).cardinality() == 0)
  // 块键错位：仅同键块参与。
  let hi = rb_dense(10, 65536)
  assert_true(a.intersect_with(hi).cardinality() == 0)
  assert_true(hi.intersect_with(a).cardinality() == 0)
  // to_array 升序导出（位图容器路径）。
  let arr = rb_dense(5000, 0).to_array()
  assert_true(arr.length() == 5000)
  assert_true(arr[0] == 0 && arr[4999] == 9998)
}
