// arena_test.mbt —— Arena 黑盒测试：定向（bump/reset/容量保留）+
// 与朴素参照差分 PBT + 稳态零增长守卫。

///|
test "arena basic: bump alloc, get/set, reset keeps capacity" {
  let a : @infra_alloc.Arena[String] = @infra_alloc.Arena::new()
  assert_eq(a.len(), 0)
  let x = a.alloc("x")
  let y = a.alloc("y")
  assert_eq(x, 0)
  assert_eq(y, 1)
  assert_eq(a.len(), 2)
  assert_true(a.get(x) == Some("x"))
  assert_true(a.get(y) == Some("y"))
  assert_true(a.get(2) is None)
  assert_true(a.get(-1) is None)
  assert_true(a.set(y, "Y"))
  assert_true(a.get(y) == Some("Y"))
  assert_false(a.set(5, "?"))
  let cap = a.capacity()
  a.reset()
  assert_eq(a.len(), 0)
  assert_eq(a.capacity(), cap) // 容量保留
  assert_true(a.get(x) is None) // 旧代句柄失效
  // 新代复用槽位。
  let z = a.alloc("z")
  assert_eq(z, 0)
  assert_true(a.get(z) == Some("z"))
}

///|
test "arena steady-state: per-generation allocations reach zero growth" {
  let a : @infra_alloc.Arena[Int] = @infra_alloc.Arena::new()
  // 第一代把容量顶到 1000。
  for i in 0..<1000 {
    let _ = a.alloc(i)
  }
  let cap = a.capacity()
  // 之后 200 代：每代 ≤1000 个对象，容量恒定不再增长。
  for gen in 0..<200 {
    a.reset()
    for i in 0..<1000 {
      let id = a.alloc(gen * 1000 + i)
      assert_eq(id, i) // 稠密句柄确定性
    }
    assert_eq(a.capacity(), cap)
  }
  assert_eq(a.len(), 1000)
}

///|
test "arena differential PBT vs naive fresh-array reference (200 iterations)" {
  let rng = @infra_pbt.rng_new(0xE3_A2E4AUL)
  for _iter in 0..<200 {
    let a : @infra_alloc.Arena[Int] = @infra_alloc.Arena::new()
    let mut naive : Array[Int] = []
    for _step in 0..<(20 + rng.next_below(100)) {
      match rng.next_below(10) {
        0 => {
          a.reset()
          naive = []
        }
        1 =>
          if naive.length() > 0 {
            let id = rng.next_below(naive.length())
            let v = rng.next_below(1000000)
            assert_true(a.set(id, v))
            naive[id] = v
          }
        _ => {
          let v = rng.next_below(1000000)
          let id = a.alloc(v)
          assert_eq(id, naive.length())
          naive.push(v)
        }
      }
      assert_eq(a.len(), naive.length())
    }
    for i in 0..<naive.length() {
      assert_true(a.get(i) == Some(naive[i]))
    }
    let items = a.iter()
    assert_eq(items.length(), naive.length())
    for i in 0..<items.length() {
      assert_true(items[i] == (i, naive[i]))
    }
  }
}
