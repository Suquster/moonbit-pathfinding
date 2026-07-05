// slab_test.mbt —— Slab 黑盒测试：定向（alloc/free/分代失效/clear/复用）+
// 与朴素参照映射差分 PBT + 容量有界性（churn 不增长）守卫。

///|
test "slab basic: alloc/get/set/free/len" {
  let s : @infra_alloc.Slab[String] = @infra_alloc.Slab::new()
  assert_eq(s.len(), 0)
  let k1 = s.alloc("a")
  let k2 = s.alloc("b")
  assert_eq(s.len(), 2)
  assert_true(s.get(k1) == Some("a"))
  assert_true(s.get(k2) == Some("b"))
  assert_true(s.set(k1, "A"))
  assert_true(s.get(k1) == Some("A"))
  assert_true(s.free(k1) == Some("A"))
  assert_eq(s.len(), 1)
  assert_true(s.get(k1) == None)
  assert_false(s.contains(k1))
  assert_true(s.contains(k2))
}

///|
test "slab generational handles: stale key permanently invalid after reuse" {
  let s : @infra_alloc.Slab[Int] = @infra_alloc.Slab::new()
  let k1 = s.alloc(10)
  assert_true(s.free(k1) == Some(10))
  // 槽位被复用，旧句柄仍失效（代数不符）。
  let k2 = s.alloc(20)
  assert_true(s.get(k2) == Some(20))
  assert_true(s.get(k1) == None)
  assert_false(s.set(k1, 99))
  assert_true(s.free(k1) == None)
  // 双重释放无效。
  assert_true(s.free(k2) == Some(20))
  assert_true(s.free(k2) == None)
  assert_eq(s.len(), 0)
}

///|
test "slab clear: all invalidated, capacity retained, slots reusable" {
  let s : @infra_alloc.Slab[Int] = @infra_alloc.Slab::with_capacity(16)
  assert_eq(s.capacity(), 16)
  let keys : Array[@infra_alloc.SlabKey] = []
  for i in 0..<10 {
    keys.push(s.alloc(i))
  }
  assert_eq(s.len(), 10)
  s.clear()
  assert_eq(s.len(), 0)
  assert_eq(s.capacity(), 16)
  for k in keys {
    assert_true(s.get(k) == None)
  }
  // 复用后新句柄正常。
  let k = s.alloc(42)
  assert_true(s.get(k) == Some(42))
}

///|
test "slab churn keeps capacity bounded (zero growth allocation in steady state)" {
  let s : @infra_alloc.Slab[Int] = @infra_alloc.Slab::with_capacity(64)
  let cap0 = s.capacity()
  // 稳态 churn：64 存活上限下 alloc/free 交替 10000 次。
  let live : Array[@infra_alloc.SlabKey] = []
  let rng = @infra_pbt.rng_new(0xE3_51ABUL)
  for i in 0..<10000 {
    if live.length() < 64 && (live.length() == 0 || rng.next_bool()) {
      live.push(s.alloc(i))
    } else {
      let j = rng.next_below(live.length())
      let k = live[j]
      let _ = live.remove(j)
      assert_true(s.free(k) is Some(_))
    }
  }
  // 稳态容量不增长——逐操作分配归零。
  assert_eq(s.capacity(), cap0)
}

///|
test "slab differential PBT vs naive map reference (200 iterations)" {
  let rng = @infra_pbt.rng_new(0xE3_2026_0705UL)
  for _iter in 0..<200 {
    let s : @infra_alloc.Slab[Int] = @infra_alloc.Slab::new()
    // 参照：句柄数组 +（存活标志, 值）。
    let ref_keys : Array[@infra_alloc.SlabKey] = []
    let ref_vals : Array[Int] = []
    let ref_live : Array[Bool] = []
    let steps = 5 + rng.next_below(60)
    for step in 0..<steps {
      match rng.next_below(4) {
        0 => {
          let k = s.alloc(step)
          ref_keys.push(k)
          ref_vals.push(step)
          ref_live.push(true)
        }
        1 =>
          if ref_keys.length() > 0 {
            let j = rng.next_below(ref_keys.length())
            let expected = if ref_live[j] { Some(ref_vals[j]) } else { None }
            assert_true(s.free(ref_keys[j]) == expected)
            ref_live[j] = false
          }
        2 =>
          if ref_keys.length() > 0 {
            let j = rng.next_below(ref_keys.length())
            let ok = s.set(ref_keys[j], step * 7)
            assert_eq(ok, ref_live[j])
            if ref_live[j] {
              ref_vals[j] = step * 7
            }
          }
        _ =>
          if ref_keys.length() > 0 {
            let j = rng.next_below(ref_keys.length())
            let expected = if ref_live[j] { Some(ref_vals[j]) } else { None }
            assert_true(s.get(ref_keys[j]) == expected)
          }
      }
      // 存活计数一致。
      let mut live_n = 0
      for b in ref_live {
        if b {
          live_n = live_n + 1
        }
      }
      assert_eq(s.len(), live_n)
    }
    // 终态：iter_live 与参照存活集一致。
    let got = s.iter_live()
    let mut live_n = 0
    for j in 0..<ref_keys.length() {
      if ref_live[j] {
        live_n = live_n + 1
        assert_true(s.get(ref_keys[j]) == Some(ref_vals[j]))
      }
    }
    assert_eq(got.length(), live_n)
  }
}
