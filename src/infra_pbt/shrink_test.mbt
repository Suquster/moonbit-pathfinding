// shrink_test.mbt —— 反例收缩机制（task 2.2）的极少量内联烟雾测试。
//
// 仅做「编译自洽 + 基本正确性」校验；Property 11「收缩产物仍使属性失败」
// 等属性测试由 task 2.4 单独承载，本文件不与其重复。

///|
/// shrink_int(0) 无可收缩，返回空数组。
test "shrink_int of zero is empty" {
  assert_eq(shrink_int(0).length(), 0)
}

///|
/// shrink_int 的所有候选都严格比原值更接近 0，且不含原值、首项为 0。
test "shrink_int candidates move toward zero" {
  let cs = shrink_int(8)
  assert_eq(cs[0], 0)
  for c in cs {
    assert_true(c != 8)
    // 落在 [0, 8) 内，即比原值更接近 0。
    assert_true(c >= 0 && c < 8)
  }
}

///|
/// shrink_int 对负值同样朝 0 收缩。
test "shrink_int handles negative values" {
  let cs = shrink_int(-8)
  assert_eq(cs[0], 0)
  for c in cs {
    assert_true(c != -8)
    // 落在 (-8, 0] 内，即比原值更接近 0。
    assert_true(c <= 0 && c > -8)
  }
}

///|
/// shrink_array 删除单个元素：长度 n 的数组至少产出 n 个长度 n-1 的候选。
test "shrink_array produces shorter candidates by deletion" {
  let arr = [1, 2, 3]
  let cs = shrink_array(arr, shrink_int)
  // 前 3 个候选为各删一个元素的结果（长度 2）。
  // 用 `Eq`（`==`）配合 `assert_true` 比较数组，避开已废弃的 `Show`（对 Array
  // 的调试格式化已被 `Debug` 取代）；语义与逐元素相等判定完全一致。
  assert_true(cs[0] == [2, 3])
  assert_true(cs[1] == [1, 3])
  assert_true(cs[2] == [1, 2])
}

///|
/// check_with_shrink：属性恒成立时返回 passed，无反例。
test "check_with_shrink passes when property always holds" {
  let g = gen_int_range(0, 50)
  let result = check_with_shrink(g, fn(x) { x >= 0 }, shrink_int)
  assert_true(result.passed)
  assert_true(result.counterexample is None)
}

///|
/// check_with_shrink：属性恒不成立（x < 100 对部分采样失败）时，
/// 返回的最小反例仍使属性失败（Property 11 / AC2 的烟雾验证）。
test "check_with_shrink returns a shrunk failing counterexample" {
  // 谓词「x <= 4」：对 [0,50] 的部分采样失败；收缩应逼近最小失败值。
  let g = gen_int_range(0, 50)
  let pred = fn(x) { x <= 4 }
  let result = check_with_shrink(g, pred, shrink_int)
  assert_true(!result.passed)
  match result.counterexample {
    Some(c) => {
      // 关键不变量：收缩产物仍使属性失败。
      assert_true(!pred(c))
      // 朝 0 收缩后，最小失败反例应为 5（首个使 x<=4 为假的非负整数）。
      assert_eq(c, 5)
    }
    None => assert_true(false)
  }
}

///|
/// Shrinkable：可携带值与惰性候选集，candidates 求值返回收缩候选。
test "shrinkable carries value and lazy candidates" {
  let s = Shrinkable::new(6, fn() { shrink_int(6) })
  assert_eq(s.value, 6)
  assert_true(s.candidates().length() > 0)
}
