// parser_ext_prop_wbtest.mbt —— L1 解析器增强属性测试（白盒，任务 6.3 /
// design.md §「Property 6: R6 增量解析等价 → AC5 内存上限」）。
//
// 本文件承载 Property 6d（AC5 BoundedCache 容量上限不变量）。该属性需对引擎
// 内部只读类型 `Outcome[T]` 直接构造（`OOk`），而其构造器对黑盒测试为只读、
// 不可创建，故以白盒测试（`*_wbtest.mbt`，可访问包内构造器）实现，与同包黑盒
// 文件 `parser_ext_prop_test.mbt` 承载的 6a/6b/6c 互补。
//
// 仅新增测试，不改既有签名与既有测试（freeze + bypass）。属性 `iters >= 100`，
// 由 @infra_pbt.holds_for_all 以固定种子驱动，三后端 wasm-gc / js / native
// 逐位一致、可复现。全程禁止循环内字符串 `+`。

///|
/// Feature: production-hardening, Property 6: BoundedCache size never exceeds cap
///
/// 对随机 cap（含负 / 零 cap）与随机 put 序列（偏移含重复，触发条目更新与
/// LRU 淘汰），断言每次写入后及最终缓存条目数恒 <= max(cap, 0)（AC5 内存上限
/// 不变量）。`cap <= 0` 视为「无缓存」，条目数恒为 0。
///
/// **Validates: Requirements 6.5**
test "Feature: production-hardening, Property 6: BoundedCache entry count is bounded by cap" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    let cap = rng.next_range(-2, 8) // 含负 / 零 cap（视为无缓存）
    let count = rng.next_range(0, 30)
    let offsets : Array[Int] = []
    let mut i = 0
    while i < count {
      offsets.push(rng.next_range(0, 12)) // 偏移有重复，触发更新与淘汰
      i = i + 1
    }
    (cap, offsets)
  })
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(pair) {
      let (cap, offsets) = pair
      let cache : BoundedCache[Int] = BoundedCache::new(cap)
      let limit = if cap > 0 { cap } else { 0 } // max(cap, 0)
      let mut held = true
      for off in offsets {
        cache.put(off, OOk(off, Input::from_string("")))
        if cache.len() > limit {
          held = false
        }
      }
      held && cache.len() <= limit
    },
    iters=100,
  )
  assert_true(ok)
}
