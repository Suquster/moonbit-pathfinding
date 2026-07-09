// hamt_gaps_wbtest.mbt —— HAMT 哈希冲突桶（Collision）通路收口
// （INFRA 第二十五批）：以 mod 4 哈希键强制全哈希冲突。

///|
/// 冲突键：哈希恒为 v % 4，制造全哈希冲突与桶不命中。
priv struct CollKey {
  v : Int
} derive(Eq)

///|
impl Hash for CollKey with fn hash_combine(self, hasher) {
  hasher.combine_int(self.v % 4)
}

///|
test "HamtMap：全哈希冲突桶的建立/查找/替换/追加" {
  let m0 : HamtMap[CollKey, String] = HamtMap::new()
  let m1 = m0.insert({ v: 0 }, "a")
  // 相同哈希不同键 → 建冲突桶。
  let m2 = m1.insert({ v: 4 }, "b")
  assert_eq(m2.size, 2)
  assert_true(m2.get({ v: 0 }) == Some("a"))
  assert_true(m2.get({ v: 4 }) == Some("b"))
  // 桶内不命中（同哈希、桶中无此键）。
  assert_true(m2.get({ v: 8 }) == None)
  assert_true(m2.contains({ v: 4 }))
  assert_false(m2.contains({ v: 8 }))
  // 桶内替换既有键。
  let m3 = m2.insert({ v: 0 }, "a2")
  assert_eq(m3.size, 2)
  assert_true(m3.get({ v: 0 }) == Some("a2"))
  // 同哈希新键追加进桶。
  let m4 = m3.insert({ v: 8 }, "c")
  assert_eq(m4.size, 3)
  assert_true(m4.get({ v: 8 }) == Some("c"))
}

///|
test "HamtMap：冲突桶与异哈希新键升层分裂" {
  let m = HamtMap::new()
    .insert(CollKey::{ v: 0 }, "a")
    .insert(CollKey::{ v: 4 }, "b")
    // 哈希 2 ≠ 桶哈希 0 → 升一层 Branch 再插。
    .insert(CollKey::{ v: 2 }, "c")
  assert_eq(m.size, 3)
  assert_true(m.get({ v: 0 }) == Some("a"))
  assert_true(m.get({ v: 4 }) == Some("b"))
  assert_true(m.get({ v: 2 }) == Some("c"))
}
