// hamt_test.mbt —— HamtMap 黑盒测试：定向（路径复制不可变共享/塌缩）+
// 与朴素参照映射差分 PBT。

///|
test "hamt basic insert/get/update/length" {
  let m0 : @infra_ds.HamtMap[Int, String] = @infra_ds.HamtMap::new()
  assert_eq(m0.length(), 0)
  assert_true(m0.get(1) == None)
  let m1 = m0.insert(1, "a")
  let m2 = m1.insert(2, "b")
  assert_eq(m2.length(), 2)
  assert_true(m2.get(1) == Some("a"))
  assert_true(m2.get(2) == Some("b"))
  assert_true(m2.get(3) == None)
  // 更新不改基数。
  let m3 = m2.insert(1, "A")
  assert_true(m3.get(1) == Some("A"))
  assert_eq(m3.length(), 2)
}

///|
test "hamt persistence: old versions unchanged (path copying)" {
  let base : @infra_ds.HamtMap[Int, Int] = @infra_ds.HamtMap::new()
  let v1 = base.insert(10, 100)
  let v2 = v1.insert(20, 200)
  let v3 = v2.remove(10)
  // 各版本独立可见。
  assert_true(base.get(10) == None)
  assert_true(v1.get(10) == Some(100))
  assert_true(v1.get(20) == None)
  assert_true(v2.get(10) == Some(100))
  assert_true(v2.get(20) == Some(200))
  assert_true(v3.get(10) == None)
  assert_true(v3.get(20) == Some(200))
  assert_eq(v1.length(), 1)
  assert_eq(v2.length(), 2)
  assert_eq(v3.length(), 1)
}

///|
test "hamt remove: leaf / branch collapse / missing" {
  let mut m : @infra_ds.HamtMap[Int, Int] = @infra_ds.HamtMap::new()
  for i in 0..<500 {
    m = m.insert(i, i * 7)
  }
  assert_eq(m.length(), 500)
  // 删不存在。
  let same = m.remove(9999)
  assert_eq(same.length(), 500)
  // 逐个删空，语义随删随查一致。
  for i in 0..<500 {
    m = m.remove(i)
    assert_true(m.get(i) == None)
    assert_eq(m.length(), 500 - i - 1)
  }
  assert_eq(m.length(), 0)
  assert_eq(m.to_array().length(), 0)
}

///|
struct HRef {
  entries : Array[(Int, Int)]
}

///|
fn HRef::put(self : HRef, k : Int, v : Int) -> Unit {
  for i in 0..<self.entries.length() {
    if self.entries[i].0 == k {
      self.entries[i] = (k, v)
      return
    }
  }
  self.entries.push((k, v))
}

///|
fn HRef::del(self : HRef, k : Int) -> Unit {
  for i in 0..<self.entries.length() {
    if self.entries[i].0 == k {
      let last = self.entries.length() - 1
      self.entries[i] = self.entries[last]
      let _ = self.entries.pop()
      return
    }
  }
}

///|
fn HRef::find(self : HRef, k : Int) -> Int? {
  for e in self.entries {
    if e.0 == k {
      return Some(e.1)
    }
  }
  None
}

///|
test "E1 property: hamt ≡ reference map under random ops (200 iters)" {
  let rng = @infra_pbt.rng_new(20260707)
  for _iter in 0..<200 {
    let mut m : @infra_ds.HamtMap[Int, Int] = @infra_ds.HamtMap::new()
    let ref_map : HRef = { entries: [] }
    let ops = 60 + rng.next_below(140)
    let key_space = 1 + rng.next_below(60)
    for _ in 0..<ops {
      let k = rng.next_below(key_space)
      let dice = rng.next_below(10)
      if dice < 6 {
        let v = rng.next_below(1000)
        m = m.insert(k, v)
        ref_map.put(k, v)
      } else if dice < 9 {
        m = m.remove(k)
        ref_map.del(k)
      }
      assert_true(m.get(k) == ref_map.find(k))
      assert_eq(m.length(), ref_map.entries.length())
    }
    // 终态：导出集合（排序后）逐位一致。
    let a = m.to_array()
    a.sort_by(fn(x, y) { x.0 - y.0 })
    let b = ref_map.entries.copy()
    b.sort_by(fn(x, y) { x.0 - y.0 })
    assert_eq(a.length(), b.length())
    for i in 0..<a.length() {
      assert_eq(a[i].0, b[i].0)
      assert_eq(a[i].1, b[i].1)
    }
  }
}
