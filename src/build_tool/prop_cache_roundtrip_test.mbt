// prop_cache_roundtrip_test.mbt —— Property 4：缓存往返一致性。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_build_cache（随机 BuildCache）。
// 以 cache_eq 逐字段比较序列化-反序列化往返结果（BuildCache 非 Eq，故用
// holds_for_all + cache_eq 而非 round_trip 的 Bytes 通道）。

///|
/// Feature: build-tool, Property 4: 缓存往返一致性
///
/// 对任意由生成器产出的 `BuildCache` `c`，序列化后再反序列化得到与原缓存逐
/// 字段一致的缓存：`deserialize_cache(serialize_cache(c))` 为 `Ok(c')` 且
/// `cache_eq(c, c')`（四张指纹映射逐字段相等）。
///
/// **Validates: Requirements 4.1, 4.2, 4.4**
test "Feature: build-tool, Property 4: cache serialization round-trip" {
  let ok = @infra_pbt.holds_for_all(gen_build_cache(), fn(c) {
    match deserialize_cache(serialize_cache(c)) {
      Ok(c2) => cache_eq(c, c2)
      Err(_) => false
    }
  })
  assert_true(ok)
}
