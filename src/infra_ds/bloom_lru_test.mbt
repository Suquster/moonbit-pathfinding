// bloom_lru_test.mbt —— BloomFilter（无假阴性 + 假阳率上界）与
// LRU（O(1) 语义 + 淘汰序）测试。

///|
test "bloom filter has no false negatives" {
  let bf = @infra_ds.BloomFilter::create(1000, 10) // 1% 目标假阳率
  for i in 0..<1000 {
    bf.insert("key-\{i}")
  }
  assert_eq(bf.count(), 1000)
  for i in 0..<1000 {
    assert_true(bf.contains("key-\{i}"))
  }
}

///|
test "bloom filter false positive rate stays bounded" {
  let bf = @infra_ds.BloomFilter::create(1000, 10) // 1% 目标
  for i in 0..<1000 {
    bf.insert("member-\{i}")
  }
  // 10000 个不在集合内的键，假阳数应远低于 5%（1% 目标 + 裕量）。
  let mut fp = 0
  for i in 0..<10000 {
    if bf.contains("absent-\{i}") {
      fp = fp + 1
    }
  }
  assert_true(fp < 500)
}

///|
test "bloom filter empty contains nothing" {
  let bf = @infra_ds.BloomFilter::create(100, 10)
  assert_true(!bf.contains("anything"))
  assert_eq(bf.count(), 0)
}

///|
test "lru cache basic get put and eviction order" {
  let lru : @infra_ds.LruCache[String, Int] = @infra_ds.LruCache::create(3)
  lru.put("a", 1)
  lru.put("b", 2)
  lru.put("c", 3)
  assert_eq(lru.size(), 3)
  assert_true(lru.get("a") == Some(1))
  // 触摸 a 后插入 d，应淘汰最久未用的 b。
  lru.put("d", 4)
  assert_true(lru.get("b") == None)
  assert_true(lru.get("a") == Some(1))
  assert_true(lru.get("c") == Some(3))
  assert_true(lru.get("d") == Some(4))
  assert_eq(lru.size(), 3)
}

///|
test "lru cache updates existing key without eviction" {
  let lru : @infra_ds.LruCache[Int, String] = @infra_ds.LruCache::create(2)
  lru.put(1, "one")
  lru.put(2, "two")
  lru.put(1, "uno") // 更新不应触发淘汰
  assert_eq(lru.size(), 2)
  assert_true(lru.get(1) == Some("uno"))
  assert_true(lru.get(2) == Some("two"))
  // 再插入新键淘汰 1（因为 2 刚被触摸后 1 又被触摸……实际 2 是最久未用？
  // 触摸序：put1 put2 put1(更新) get1 get2 → 最久未用是 1。
  lru.put(3, "three")
  assert_true(lru.get(1) == None)
  assert_true(lru.get(2) == Some("two"))
}

///|
test "lru cache capacity one" {
  let lru : @infra_ds.LruCache[Int, Int] = @infra_ds.LruCache::create(1)
  lru.put(1, 10)
  assert_true(lru.get(1) == Some(10))
  lru.put(2, 20)
  assert_true(lru.get(1) == None)
  assert_true(lru.get(2) == Some(20))
  assert_eq(lru.cap(), 1)
}

///|
test "lru cache matches reference model (pbt)" {
  let rng = @infra_pbt.rng_new(20260707UL)
  for _ in 0..<50 {
    let cap = 1 + rng.next_below(8)
    let lru : @infra_ds.LruCache[Int, Int] = @infra_ds.LruCache::create(cap)
    // 参考模型：数组按最近使用序保存 (key, value)，头部最近。
    let model : Array[(Int, Int)] = []
    for _ in 0..<200 {
      let key = rng.next_below(16)
      if rng.next_below(2) == 0 {
        let value = rng.next_below(1000)
        lru.put(key, value)
        // 模型 put。
        let mut found = -1
        for i, kv in model {
          if kv.0 == key {
            found = i
            break
          }
        }
        if found >= 0 {
          let _ = model.remove(found)
        } else if model.length() == cap {
          let _ = model.remove(model.length() - 1)
        }
        model.insert(0, (key, value))
      } else {
        let got = lru.get(key)
        let mut found = -1
        for i, kv in model {
          if kv.0 == key {
            found = i
            break
          }
        }
        if found >= 0 {
          let kv = model[found]
          assert_true(got == Some(kv.1))
          let _ = model.remove(found)
          model.insert(0, kv)
        } else {
          assert_true(got == None)
        }
      }
      assert_eq(lru.size(), model.length())
    }
  }
}
