// cache_gaps_test.mbt —— 缓存反序列化防御分支收口
// （INFRA 第三十九批）：缺字段分隔、无值行、空目标名、负数与畸形数值。

///|
test "deserialize_cache：缺字段分隔空格与空目标名拒绝" {
  assert_true(@build_tool.deserialize_cache("M") is Err(_))
  assert_true(@build_tool.deserialize_cache("M  123") is Err(_))
}

///|
test "deserialize_cache：无值行与负数 mtime 容受" {
  // 第二分隔缺失 → value 为空串 → mtime 数值非法。
  assert_true(@build_tool.deserialize_cache("M a.o") is Err(_))
  // 负数 mtime 合法解析。
  match @build_tool.deserialize_cache("M a.o -5") {
    Ok(c) => assert_true(c.recorded_mtimes.get("a.o") == Some(-5L))
    Err(_) => assert_true(false)
  }
  // 单独 '-' 数值非法。
  assert_true(@build_tool.deserialize_cache("M a.o -") is Err(_))
}
