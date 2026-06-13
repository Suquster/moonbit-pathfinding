// cache_test.mbt —— 内容寻址缓存与持久化单元测试（任务 2.3）。
//
// 覆盖内容哈希确定 / 内容敏感、mtime 同而内容哈希不同仍判键变（R3.5）、命中 /
// 未命中判定（R3.2 / R3.3）、反序列化非法格式错误（R4.3）。

///|
/// 内容哈希确定且内容敏感。
test "content_hash is deterministic and content-sensitive" {
  assert_true(content_hash("abc") == content_hash("abc"))
  assert_true(content_hash("abc") != content_hash("abd"))
}

///|
/// 内容哈希变化（mtime 未变情形）→ 缓存键变化（R3.5）。
test "cache_key changes when content hash changes" {
  let k1 = cache_key("app", ["h1"], "fp")
  let k2 = cache_key("app", ["h2"], "fp")
  assert_true(k1 != k2)
}

///|
/// 命中 / 未命中驱动重建判定（R3.2 / R3.3）。
test "ActionCache hit and miss drive rebuild decision" {
  let cache = ActionCache::new()
  let key = cache_key("app", ["h1"], "fp")
  assert_true(needs_rebuild_by_key(cache, "app", ["h1"], "fp"))
  cache.record(key, "out1")
  assert_false(needs_rebuild_by_key(cache, "app", ["h1"], "fp"))
  assert_true(cache.hit(key))
  assert_true(cache.get(key) == Some("out1"))
}

///|
/// 缓存序列化-反序列化往返一致（R4.1 / R4.2）。
test "deserialize_cache round-trips a serialized cache" {
  let c = BuildCache::new()
  c.observe("app", 100L, "h1")
  c.mark_built("app")
  c.observe("app", 200L, "h2")
  match deserialize_cache(serialize_cache(c)) {
    Ok(c2) => assert_true(cache_eq(c, c2))
    Err(_) => fail("合法序列化文本不应反序列化失败")
  }
}

///|
/// 反序列化未知段标记报带行号错误（R4.3）。
test "deserialize_cache reports illegal marker with line number" {
  match deserialize_cache("# recorded_mtimes\nX app 100\n") {
    Ok(_) => fail("非法标记应报错")
    Err(e) => assert_eq(e.line, 2)
  }
}

///|
/// 反序列化非法 mtime 数值报带行号错误（R4.3）。
test "deserialize_cache reports non-numeric mtime" {
  match deserialize_cache("M app notanumber\n") {
    Ok(_) => fail("非法 mtime 应报错")
    Err(e) => assert_eq(e.line, 1)
  }
}
