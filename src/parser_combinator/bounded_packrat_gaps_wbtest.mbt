// bounded_packrat_gaps_wbtest.mbt —— 有界 packrat 缓存驱逐/压实/命中收口
// （INFRA 第三十三批）。

///|
test "BoundedCache：capacity 查询" {
  let cache : BoundedCache[Int] = BoundedCache::new(4)
  assert_eq(cache.capacity(), 4)
  assert_eq(cache.len(), 0)
}

///|
test "BoundedCache：大量驱逐触发 order 压实" {
  // cap=2：持续插入使 head 递增超过 64 且过半 → 触发就地压实。
  let cache : BoundedCache[Int] = BoundedCache::new(2)
  for i in 0..<200 {
    cache.put(i, OFail({ offset: i, line: 1, col: 1 }, ["x"], false))
  }
  assert_eq(cache.len(), 2)
  assert_true(cache.contains(199))
  assert_true(cache.contains(198))
  assert_false(cache.contains(0))
}
