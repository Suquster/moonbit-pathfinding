// skiplist_test.mbt —— SkipList 黑盒测试：定向 + 与朴素参照映射差分 PBT +
// 确定性（同种子同结果）验证。

///|
test "skiplist basic insert/get/update/size" {
  let s : @infra_ds.SkipList[Int, String] = @infra_ds.SkipList::new()
  assert_eq(s.size(), 0)
  assert_true(s.get(1) == None)
  assert_true(s.insert(1, "a") == None)
  assert_true(s.insert(2, "b") == None)
  assert_true(s.get(1) == Some("a"))
  assert_true(s.get(2) == Some("b"))
  assert_true(s.get(3) == None)
  assert_eq(s.size(), 2)
  assert_true(s.insert(1, "A") == Some("a"))
  assert_true(s.get(1) == Some("A"))
  assert_eq(s.size(), 2)
}

///|
test "skiplist to_array sorted & range half-open" {
  let s : @infra_ds.SkipList[Int, Int] = @infra_ds.SkipList::new()
  for k in [5, 1, 9, 3, 7, 2, 8, 4, 6, 0] {
    let _ = s.insert(k, k * k)
  }
  let all = s.to_array()
  assert_eq(all.length(), 10)
  for i in 0..<10 {
    assert_eq(all[i].0, i)
    assert_eq(all[i].1, i * i)
  }
  let r = s.range(3, 7)
  assert_eq(r.length(), 4)
  assert_eq(r[0].0, 3)
  assert_eq(r[3].0, 6)
  assert_eq(s.range(7, 3).length(), 0)
  assert_eq(s.range(100, 200).length(), 0)
}

///|
test "skiplist remove: many levels + borrow-free rewire" {
  let s : @infra_ds.SkipList[Int, Int] = @infra_ds.SkipList::new()
  for i in 0..<300 {
    let _ = s.insert(i, i * 10)
  }
  assert_eq(s.size(), 300)
  assert_true(s.remove(1000) == None)
  // 间隔删除后仍有序、命中一致。
  let mut i = 0
  while i < 300 {
    assert_true(s.remove(i) == Some(i * 10))
    i = i + 2
  }
  assert_eq(s.size(), 150)
  let rest = s.to_array()
  assert_eq(rest.length(), 150)
  for j in 0..<rest.length() {
    assert_eq(rest[j].0, j * 2 + 1)
  }
}

///|
test "skiplist determinism: same seed ⇒ same structure/order" {
  let mk = fn() {
    let s : @infra_ds.SkipList[Int, Int] = @infra_ds.SkipList::with_seed(12345)
    for k in [7, 3, 9, 1, 5, 2, 8, 4, 6, 0, 11, 10] {
      let _ = s.insert(k, k)
    }
    s.to_array()
  }
  let a = mk()
  let b = mk()
  assert_eq(a.length(), b.length())
  for i in 0..<a.length() {
    assert_eq(a[i].0, b[i].0)
  }
}

///|
struct SLRef {
  entries : Array[(Int, Int)]
}

///|
fn SLRef::put(self : SLRef, k : Int, v : Int) -> Int? {
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
fn SLRef::del(self : SLRef, k : Int) -> Int? {
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
fn SLRef::find(self : SLRef, k : Int) -> Int? {
  for e in self.entries {
    if e.0 == k {
      return Some(e.1)
    }
  }
  None
}

///|
fn SLRef::sorted(self : SLRef) -> Array[(Int, Int)] {
  let out = self.entries.copy()
  out.sort_by(fn(a, b) { a.0 - b.0 })
  out
}

///|
test "E1 property: skiplist ≡ reference map under random ops (200 iters)" {
  let rng = @infra_pbt.rng_new(20260708)
  for _iter in 0..<200 {
    let s : @infra_ds.SkipList[Int, Int] = @infra_ds.SkipList::with_seed(
      rng.next(),
    )
    let ref_map : SLRef = { entries: [] }
    let ops = 60 + rng.next_below(140)
    let key_space = 1 + rng.next_below(80)
    for _ in 0..<ops {
      let k = rng.next_below(key_space)
      let dice = rng.next_below(10)
      if dice < 6 {
        let v = rng.next_below(1000)
        assert_true(s.insert(k, v) == ref_map.put(k, v))
      } else if dice < 9 {
        assert_true(s.remove(k) == ref_map.del(k))
      } else {
        assert_true(s.get(k) == ref_map.find(k))
      }
      assert_eq(s.size(), ref_map.entries.length())
    }
    let a = s.to_array()
    let b = ref_map.sorted()
    assert_eq(a.length(), b.length())
    for i in 0..<a.length() {
      assert_eq(a[i].0, b[i].0)
      assert_eq(a[i].1, b[i].1)
    }
    let lo = rng.next_below(key_space)
    let hi = rng.next_below(key_space)
    let got = s.range(lo, hi)
    let want : Array[(Int, Int)] = []
    for e in b {
      if e.0 >= lo && e.0 < hi {
        want.push(e)
      }
    }
    assert_eq(got.length(), want.length())
    for i in 0..<got.length() {
      assert_eq(got[i].0, want[i].0)
    }
  }
}
