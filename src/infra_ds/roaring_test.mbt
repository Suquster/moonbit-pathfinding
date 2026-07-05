// roaring_test.mbt —— RoaringBitmap 黑盒测试：定向（两态转换/跨桶/集合运算）
// + 与朴素布尔数组参照的差分 PBT。

///|
test "roaring basic add/remove/contains/cardinality" {
  let r = @infra_ds.RoaringBitmap::new()
  assert_eq(r.cardinality(), 0)
  assert_true(r.contains(5) == false)
  assert_true(r.add(5))
  assert_true(r.add(5) == false) // 幂等
  assert_true(r.contains(5))
  assert_eq(r.cardinality(), 1)
  assert_true(r.remove(5))
  assert_true(r.remove(5) == false)
  assert_eq(r.cardinality(), 0)
  // 跨桶（高 16 位不同）。
  assert_true(r.add(1))
  assert_true(r.add(65536 + 1))
  assert_true(r.add(3 * 65536 + 7))
  assert_eq(r.cardinality(), 3)
  let all = r.to_array()
  assert_eq(all.length(), 3)
  assert_eq(all[0], 1)
  assert_eq(all[1], 65537)
  assert_eq(all[2], 3 * 65536 + 7)
}

///|
test "roaring container promotion array->bitmap and demotion back" {
  let r = @infra_ds.RoaringBitmap::new()
  // 单桶内塞 5000 个元素越过 4096 阈值（array→bitmap）。
  for i in 0..<5000 {
    assert_true(r.add(i * 13 % 65536 + 0 * 65536) || true)
  }
  let card1 = r.cardinality()
  assert_true(card1 > 4096)
  // 全部命中。
  for i in 0..<5000 {
    assert_true(r.contains(i * 13 % 65536))
  }
  // 删回 4096 以下触发 bitmap→array，语义不变。
  let all = r.to_array()
  for i in 0..<(card1 - 100) {
    assert_true(r.remove(all[i]))
  }
  assert_eq(r.cardinality(), 100)
  for i in (card1 - 100)..<card1 {
    assert_true(r.contains(all[i]))
  }
}

///|
test "roaring union/intersect directed" {
  let a = @infra_ds.RoaringBitmap::new()
  let b = @infra_ds.RoaringBitmap::new()
  for i in 0..<100 {
    let _ = a.add(i * 2) // 偶数
    let _ = b.add(i * 3) // 3 的倍数
  }
  let u = a.union_with(b)
  let x = a.intersect_with(b)
  for i in 0..<200 {
    assert_true(u.contains(i) == (a.contains(i) || b.contains(i)))
    assert_true(x.contains(i) == (a.contains(i) && b.contains(i)))
  }
  // 交集 = 6 的倍数。
  assert_true(x.contains(6))
  assert_true(x.contains(0))
  assert_true(x.contains(4) == false)
}

///|
test "E1 property: roaring ≡ boolean-array reference (200 iters)" {
  let rng = @infra_pbt.rng_new(20260706)
  for _iter in 0..<200 {
    let space = 1 + rng.next_below(200000)
    let r = @infra_ds.RoaringBitmap::new()
    let ref_set : Array[Bool] = Array::make(space, false)
    let mut ref_card = 0
    let ops = 50 + rng.next_below(150)
    for _ in 0..<ops {
      let x = rng.next_below(space)
      if rng.next_below(10) < 6 {
        let added = r.add(x)
        assert_true(added == (ref_set[x] == false))
        if added {
          ref_card = ref_card + 1
        }
        ref_set[x] = true
      } else {
        let removed = r.remove(x)
        assert_true(removed == ref_set[x])
        if removed {
          ref_card = ref_card - 1
        }
        ref_set[x] = false
      }
      assert_eq(r.cardinality(), ref_card)
    }
    // 抽查成员一致 + 导出有序一致。
    for _ in 0..<30 {
      let q = rng.next_below(space)
      assert_true(r.contains(q) == ref_set[q])
    }
    let got = r.to_array()
    assert_eq(got.length(), ref_card)
    let mut prev = -1
    for v in got {
      assert_true(v > prev)
      assert_true(ref_set[v])
      prev = v
    }
  }
}

///|
test "E1 property: roaring union/intersect ≡ reference (100 iters)" {
  let rng = @infra_pbt.rng_new(777)
  for _iter in 0..<100 {
    let space = 1 + rng.next_below(150000)
    let a = @infra_ds.RoaringBitmap::new()
    let b = @infra_ds.RoaringBitmap::new()
    let sa : Array[Bool] = Array::make(space, false)
    let sb : Array[Bool] = Array::make(space, false)
    let na = rng.next_below(300)
    let nb = rng.next_below(300)
    for _ in 0..<na {
      let x = rng.next_below(space)
      let _ = a.add(x)
      sa[x] = true
    }
    for _ in 0..<nb {
      let x = rng.next_below(space)
      let _ = b.add(x)
      sb[x] = true
    }
    let u = a.union_with(b)
    let x = a.intersect_with(b)
    let mut uc = 0
    let mut xc = 0
    for i in 0..<space {
      if sa[i] || sb[i] {
        uc = uc + 1
      }
      if sa[i] && sb[i] {
        xc = xc + 1
      }
    }
    assert_eq(u.cardinality(), uc)
    assert_eq(x.cardinality(), xc)
    for _ in 0..<30 {
      let q = rng.next_below(space)
      assert_true(u.contains(q) == (sa[q] || sb[q]))
      assert_true(x.contains(q) == (sa[q] && sb[q]))
    }
  }
}
