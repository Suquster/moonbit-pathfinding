// btree_test.mbt —— BTreeMap 黑盒测试：定向 + 与朴素有序数组参照的差分 PBT。

///|
test "btree basic insert/get/update/size" {
  let m : @infra_ds.BTreeMap[Int, String] = @infra_ds.BTreeMap::new()
  assert_eq(m.size(), 0)
  assert_true(m.get(1) == None)
  assert_true(m.insert(1, "a") == None)
  assert_true(m.insert(2, "b") == None)
  assert_true(m.get(1) == Some("a"))
  assert_true(m.get(2) == Some("b"))
  assert_true(m.get(3) == None)
  assert_eq(m.size(), 2)
  // 更新返回旧值且 size 不变。
  assert_true(m.insert(1, "A") == Some("a"))
  assert_true(m.get(1) == Some("A"))
  assert_eq(m.size(), 2)
}

///|
test "btree remove: leaf / internal / borrow / merge / root shrink" {
  let m : @infra_ds.BTreeMap[Int, Int] = @infra_ds.BTreeMap::new()
  // 足够多的键强制多层分裂（t=8，>15 键必分裂根）。
  for i in 0..<200 {
    assert_true(m.insert(i, i * 10) == None)
  }
  assert_eq(m.size(), 200)
  // 删不存在的键。
  assert_true(m.remove(1000) == None)
  assert_eq(m.size(), 200)
  // 全删（正序+倒序混合触发借位/合并/根缩层）。
  for i in 0..<100 {
    assert_true(m.remove(i) == Some(i * 10))
  }
  let mut j = 199
  while j >= 100 {
    assert_true(m.remove(j) == Some(j * 10))
    j = j - 1
  }
  assert_eq(m.size(), 0)
  assert_eq(m.to_array().length(), 0)
}

///|
test "btree to_array sorted & range half-open" {
  let m : @infra_ds.BTreeMap[Int, Int] = @infra_ds.BTreeMap::new()
  // 乱序插入。
  let keys = [5, 1, 9, 3, 7, 2, 8, 4, 6, 0]
  for k in keys {
    let _ = m.insert(k, k * k)
  }
  let all = m.to_array()
  assert_eq(all.length(), 10)
  for i in 0..<10 {
    assert_eq(all[i].0, i)
    assert_eq(all[i].1, i * i)
  }
  // 半开区间 [3, 7)。
  let r = m.range(3, 7)
  assert_eq(r.length(), 4)
  assert_eq(r[0].0, 3)
  assert_eq(r[3].0, 6)
  // 空区间。
  assert_eq(m.range(7, 3).length(), 0)
  assert_eq(m.range(100, 200).length(), 0)
}

///|
/// 朴素参照：未排序 (K,V) 数组上的线性查改删。
priv struct RefMap {
  entries : Array[(Int, Int)]
}

///|
fn RefMap::insert(self : RefMap, k : Int, v : Int) -> Int? {
  for i in 0..<self.entries.length() {
    if self.entries[i].0 == k {
      let old = self.entries[i].1
      self.entries[i] = (k, v)
      return Some(old)
    }
  }
  self.entries.push((k, v))
  None
}

///|
fn RefMap::remove(self : RefMap, k : Int) -> Int? {
  for i in 0..<self.entries.length() {
    if self.entries[i].0 == k {
      let old = self.entries[i].1
      let last = self.entries.length() - 1
      self.entries[i] = self.entries[last]
      let _ = self.entries.pop()
      return Some(old)
    }
  }
  None
}

///|
fn RefMap::get(self : RefMap, k : Int) -> Int? {
  for e in self.entries {
    if e.0 == k {
      return Some(e.1)
    }
  }
  None
}

///|
fn RefMap::sorted(self : RefMap) -> Array[(Int, Int)] {
  let out = self.entries.copy()
  out.sort_by(fn(a, b) { a.0 - b.0 })
  out
}

///|
test "E1 property: btree ≡ reference map under random ops (200 iters)" {
  let rng = @infra_pbt.rng_new(20260705)
  for iter in 0..<200 {
    let m : @infra_ds.BTreeMap[Int, Int] = @infra_ds.BTreeMap::new()
    let ref_map : RefMap = { entries: [] }
    let ops = 60 + rng.next_below(120)
    let key_space = 1 + rng.next_below(80)
    for _ in 0..<ops {
      let k = rng.next_below(key_space)
      let dice = rng.next_below(10)
      if dice < 6 {
        let v = rng.next_below(1000)
        assert_true(m.insert(k, v) == ref_map.insert(k, v))
      } else if dice < 9 {
        assert_true(m.remove(k) == ref_map.remove(k))
      } else {
        assert_true(m.get(k) == ref_map.get(k))
      }
      assert_eq(m.size(), ref_map.entries.length())
    }
    // 终态：全量导出逐位一致（含有序性）。
    let a = m.to_array()
    let b = ref_map.sorted()
    assert_eq(a.length(), b.length())
    for i in 0..<a.length() {
      assert_eq(a[i].0, b[i].0)
      assert_eq(a[i].1, b[i].1)
    }
    // 随机 range 与参照过滤一致。
    let lo = rng.next_below(key_space)
    let hi = rng.next_below(key_space)
    let got = m.range(lo, hi)
    let want : Array[(Int, Int)] = []
    for e in b {
      if e.0 >= lo && e.0 < hi {
        want.push(e)
      }
    }
    assert_eq(got.length(), want.length())
    for i in 0..<got.length() {
      assert_eq(got[i].0, want[i].0)
      assert_eq(got[i].1, want[i].1)
    }
    ignore(iter)
  }
}
