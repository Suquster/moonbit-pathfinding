// ds_proof_test.mbt —— 数据结构家族证明谓词的真实实现接地测试。
//
// 以 @infra_ds 的真实包实现驱动 ds_proof.mbt 中的谓词（跨包驱动只发生
// 在测试期）：
//   * BTreeMap / SkipList：随机键值插入删除后 `to_array` 键严格递增，
//     `range(lo, hi)` 结果封闭在区间内（随机脚本 PBT）；
//   * RoaringBitmap：并/交结果与逐元素成员判定外延一致（`same_members`）；
//   * LruCache：任意 put/get 序列后 size ≤ cap（`all_within`）；
//   * BloomFilter：已插入元素必命中——无假阴性（`forall_holds`）。

///|
/// 随机键序列生成器（值域 [0, 60]，高碰撞率覆盖重复插入/删除路径；
/// 长度 ∈ [1, 48]）。
fn ds_keys_gen() -> @infra_pbt.Gen[Array[Int]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 48)
    let out : Array[Int] = []
    for _i in 0..<n {
      out.push(rng.next_range(0, 60))
    }
    out
  })
}

///|
fn ds_prop_btree_sorted(keys : Array[Int]) -> Bool {
  let m : @infra_ds.BTreeMap[Int, Int] = @infra_ds.BTreeMap::new()
  let mut i = 0
  for k in keys {
    if i % 3 == 2 {
      ignore(m.remove(k))
    } else {
      ignore(m.insert(k, k * 10))
    }
    i += 1
  }
  let ks : Array[Int] = []
  for kv in m.to_array() {
    ks.push(kv.0)
  }
  let in_range : Array[Int] = []
  for kv in m.range(10, 40) {
    in_range.push(kv.0)
  }
  sorted_strict(ks) &&
  forall_holds(in_range, fn(k) { k >= 10 && k <= 40 }) &&
  sorted_strict(in_range)
}

///|
test "BTreeMap traversal is strictly sorted and range is interval-closed" {
  let ok = @infra_pbt.holds_for_all(
    ds_keys_gen(),
    ds_prop_btree_sorted,
    iters=128,
  )
  assert_true(ok)
}

///|
fn ds_prop_skiplist_sorted(keys : Array[Int]) -> Bool {
  let m : @infra_ds.SkipList[Int, Int] = @infra_ds.SkipList::new()
  let mut i = 0
  for k in keys {
    if i % 3 == 2 {
      ignore(m.remove(k))
    } else {
      ignore(m.insert(k, k * 10))
    }
    i += 1
  }
  let ks : Array[Int] = []
  for kv in m.to_array() {
    ks.push(kv.0)
  }
  let in_range : Array[Int] = []
  for kv in m.range(10, 40) {
    in_range.push(kv.0)
  }
  sorted_strict(ks) &&
  forall_holds(in_range, fn(k) { k >= 10 && k <= 40 }) &&
  sorted_strict(in_range)
}

///|
test "SkipList traversal is strictly sorted and range is interval-closed" {
  let ok = @infra_pbt.holds_for_all(
    ds_keys_gen(),
    ds_prop_skiplist_sorted,
    iters=128,
  )
  assert_true(ok)
}

///|
test "sorted_strict rejects duplicates and inversions" {
  assert_false(sorted_strict([1, 1]))
  assert_false(sorted_strict([2, 1]))
}

// --- RoaringBitmap：集合代数外延一致 ---

///|
fn ds_prop_roaring_algebra(pair : (Array[Int], Array[Int])) -> Bool {
  let (xs, ys) = pair
  let a = @infra_ds.RoaringBitmap::new()
  let b = @infra_ds.RoaringBitmap::new()
  for x in xs {
    ignore(a.add(x))
  }
  for y in ys {
    ignore(b.add(y))
  }
  let u = a.union_with(b)
  let n = a.intersect_with(b)
  // 参考模型：逐元素成员判定。
  let union_ref : Array[Int] = []
  let inter_ref : Array[Int] = []
  for v in 0..<70 {
    if a.contains(v) || b.contains(v) {
      union_ref.push(v)
    }
    if a.contains(v) && b.contains(v) {
      inter_ref.push(v)
    }
  }
  same_members(u.to_array(), union_ref) &&
  same_members(n.to_array(), inter_ref) &&
  u.cardinality() == union_ref.length() &&
  n.cardinality() == inter_ref.length()
}

///|
fn ds_keys_pair_gen() -> @infra_pbt.Gen[(Array[Int], Array[Int])] {
  @infra_pbt.Gen::new(fn(rng) {
    let one = fn() -> Array[Int] {
      let n = rng.next_range(0, 32)
      let out : Array[Int] = []
      for _i in 0..<n {
        out.push(rng.next_range(0, 60))
      }
      out
    }
    (one(), one())
  })
}

///|
test "RoaringBitmap union/intersection agree with membership reference" {
  let ok = @infra_pbt.holds_for_all(
    ds_keys_pair_gen(),
    ds_prop_roaring_algebra,
    iters=128,
  )
  assert_true(ok)
}

// --- LruCache：容量硬上界 ---

///|
fn ds_prop_lru_capacity(keys : Array[Int]) -> Bool {
  let cache : @infra_ds.LruCache[Int, Int] = @infra_ds.LruCache::create(8)
  let sizes : Array[Int] = []
  let mut i = 0
  for k in keys {
    if i % 4 == 3 {
      ignore(cache.get(k))
    } else {
      cache.put(k, k * 10)
    }
    sizes.push(cache.size())
    i += 1
  }
  all_within(sizes, 0, 8)
}

///|
test "LruCache size never exceeds capacity under random put/get" {
  let ok = @infra_pbt.holds_for_all(
    ds_keys_gen(),
    ds_prop_lru_capacity,
    iters=128,
  )
  assert_true(ok)
}

// --- BloomFilter：无假阴性 ---

///|
fn ds_prop_bloom_no_false_negative(keys : Array[Int]) -> Bool {
  let bloom = @infra_ds.BloomFilter::create(1024, 3)
  for k in keys {
    bloom.insert("key-\{k}")
  }
  forall_holds(keys, fn(k) { bloom.contains("key-\{k}") })
}

///|
test "BloomFilter has no false negatives for inserted keys" {
  let ok = @infra_pbt.holds_for_all(
    ds_keys_gen(),
    ds_prop_bloom_no_false_negative,
    iters=128,
  )
  assert_true(ok)
}

///|
test "forall_holds rejects a violating element" {
  assert_false(forall_holds([1, 2, 3], fn(x) { x < 3 }))
}

///|
test "same_members ignores order but not membership" {
  assert_true(same_members([3, 1, 2], [1, 2, 3]))
  assert_false(same_members([1, 2], [1, 2, 3]))
}
