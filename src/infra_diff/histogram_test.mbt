// patience / histogram diff 测试。

///|
/// patience diff：经典案例——唯一行锚点产生比 Myers 更符合直觉的对齐。
test "patience diff basic correctness" {
  let old = ["a", "b", "c", "d"]
  let new = ["a", "x", "c", "d"]
  let ops = diff_patience(old, new)
  assert_true(patch_apply(old, ops) == Some(new))
  assert_true(edit_distance(ops) == 2) // 一删一插
}

///|
/// patience diff：git 文档经典例（函数块移动场景对齐锚点）。
test "patience diff aligns unique anchor lines" {
  let old = [
    "void func1() {", "  x += 1", "}", "", "void func2() {", "  y += 2", "}",
  ]
  let new = [
    "void func2() {", "  y += 2", "}", "", "void func1() {", "  x += 1", "}",
  ]
  let ops = diff_patience(old, new)
  assert_true(patch_apply(old, ops) == Some(new))
}

///|
/// patience：无唯一公共行时回退 Myers 仍正确。
test "patience falls back to myers when no unique lines" {
  let old = ["a", "a", "a", "b", "b"]
  let new = ["b", "a", "a", "b", "a"]
  let ops = diff_patience(old, new)
  assert_true(patch_apply(old, ops) == Some(new))
}

///|
/// histogram diff：正确性 + 低频锚点分治。
test "histogram diff basic correctness" {
  let old = ["h1", "common", "h2", "common", "unique", "h3"]
  let new = ["h2", "common", "unique", "h1", "common", "h3"]
  let ops = diff_histogram(old, new)
  assert_true(patch_apply(old, ops) == Some(new))
  // 空/单侧输入。
  assert_true(patch_apply([], diff_histogram([], ["x"])) == Some(["x"]))
  assert_true(patch_apply(["x"], diff_histogram(["x"], [])) == Some([]))
  assert_true(diff_histogram([], []) == [])
}

///|
/// 两种算法与 unified diff 管线兼容（hunks_of → format → parse → apply）。
test "patience and histogram compose with unified pipeline" {
  let old = ["line1", "line2", "line3", "line4", "line5", "line6", "line7"]
  let new = [
    "line1", "line2", "changed", "line4", "line5", "added", "line6", "line7",
  ]
  for ops in [diff_patience(old, new), diff_histogram(old, new)] {
    let hunks = hunks_of(ops)
    assert_true(apply_unified(old, hunks) == Some(new))
  }
}

///|
/// PBT：任意输入 patience/histogram 与 Myers 三算法 patch 语义等价
/// （250 迭代——脚本可不同，但应用结果必须一致且等于 new）。
test "patience histogram pbt patch equivalence" {
  let mut seed = 31U
  let next = fn() -> UInt {
    seed = seed * 1664525U + 1013904223U
    seed
  }
  let words = ["alpha", "beta", "gamma", "delta", "eps"]
  for _ in 0..<250 {
    let n = (next() % 30U).reinterpret_as_int()
    let m = (next() % 30U).reinterpret_as_int()
    let old : Array[String] = []
    for i in 0..<n {
      old.push(words[((next() >> 4) % 5U).reinterpret_as_int()])
      ignore(i)
    }
    let new : Array[String] = []
    for j in 0..<m {
      new.push(words[((next() >> 4) % 5U).reinterpret_as_int()])
      ignore(j)
    }
    assert_true(patch_apply(old, diff_patience(old, new)) == Some(new))
    assert_true(patch_apply(old, diff_histogram(old, new)) == Some(new))
  }
}

///|
/// LIS 正确性：耐心排序牌堆法（O(n log n)）。
test "patience lis via public diff behavior" {
  // 交叉锚点：a↔c 交换后 LIS 只保留一侧，diff 仍无损。
  let old = ["a", "b", "c"]
  let new = ["c", "b", "a"]
  let ops = diff_patience(old, new)
  assert_true(patch_apply(old, ops) == Some(new))
}
