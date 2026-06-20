// combinators_test.mbt —— 生成器组合子（task 2.1）的极少量内联示例测试。
//
// 仅做「编译自洽 + 基本正确性」的烟雾测试（smoke test）；分布趋近权重、
// 大样本占比等属性测试由 task 2.4 单独承载，本文件不与其重复。

///|
/// one_of：从两个常量生成器中择一，结果必为其中之一。
test "one_of picks one of the provided generators" {
  let g = one_of([gen_int_range(1, 1), gen_int_range(2, 2)])
  let rng = rng_new(123)
  let mut i = 0
  while i < 20 {
    let v = g.generate(rng)
    assert_true(v == 1 || v == 2)
    i += 1
  }
}

///|
/// one_of：单元素数组退化为恒定生成该元素。
test "one_of with single generator is deterministic" {
  let g = one_of([gen_int_range(7, 7)])
  let rng = rng_new(1)
  assert_eq(g.generate(rng), 7)
}

///|
/// frequency：权重为 0 的分支被忽略，只可能选中正权重分支。
test "frequency skips non-positive weights" {
  let g = frequency([(0, gen_int_range(1, 1)), (5, gen_int_range(2, 2))])
  let rng = rng_new(99)
  let mut i = 0
  while i < 20 {
    // 权重 0 的「1」分支永不命中，结果恒为「2」。
    assert_eq(g.generate(rng), 2)
    i += 1
  }
}

///|
/// frequency：全部权重非正时等概率回退到现存生成器，不崩溃。
test "frequency degenerates safely when all weights non-positive" {
  let g = frequency([(0, gen_int_range(3, 3)), (-2, gen_int_range(4, 4))])
  let rng = rng_new(5)
  let mut i = 0
  while i < 20 {
    let v = g.generate(rng)
    assert_true(v == 3 || v == 4)
    i += 1
  }
}

///|
/// sized：派生规模落在 [0, default_max_size] 内，并被传入 make。
test "sized derives bounded reproducible size" {
  // make 直接生成等于 size 的常量，便于断言规模区间。
  let g = sized(fn(size) { gen_int_range(size, size) })
  let rng = rng_new(2024)
  // 规模上界与实现内部常量 default_max_size 一致（此处取其字面值 100）。
  let max_size = 100
  let mut i = 0
  while i < 50 {
    let v = g.generate(rng)
    assert_true(v >= 0 && v <= max_size)
    i += 1
  }
}

///|
/// sized：同种子可复现——两次以同种子驱动产生相同规模序列。
test "sized is reproducible from seed" {
  let g = sized(fn(size) { gen_int_range(size, size) })
  let a = rng_new(777)
  let b = rng_new(777)
  let mut i = 0
  while i < 16 {
    assert_eq(g.generate(a), g.generate(b))
    i += 1
  }
}
