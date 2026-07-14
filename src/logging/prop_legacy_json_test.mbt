// prop_legacy_json_test.mbt —— 既有标量 JSON 往返属性测试（任务 2.3）。
//
//   Feature: logging, Property 2: 既有标量 JSON 往返（legacy scalar JSON round-trip）
//   --------------------------------------------------------------------
//   *对任意* 仅含标量字段（VStr/VInt/VBool/VFloat）的事件 e：
//     (a) `parse_json_log(format_json(e)) == Some(e)`；
//     (b) `format_json(e)` 与 `0.1.0` 逐字节一致（向后兼容契约）。
//
// (a) 由 `holds_for_all` 验证；(b) 由确定性见证（手写期望字节串）锁定——
// 既有标量渲染臂逐字保留，故输出与骨架首版逐字节不变（Requirement 1.5 / 12.4）。

///|
/// Feature: logging, Property 2: 既有标量 JSON 往返（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 1.5, 12.4, 12.7**
test "Feature: logging, Property 2: legacy scalar json round-trip (holds_for_all)" {
  let ok = @infra_pbt.holds_for_all(sh_scalar_event(), fn(e) {
    parse_json_log(format_json(e)) == Some(e)
  })
  assert_true(ok)
}

///|
/// Property 2 字节级见证：仅含标量字段事件的 `format_json` 输出与 0.1.0 逐字节
/// 一致——字段经既有 `sort_entries` 按 MoonBit `String` 全序（长度优先、同长再
/// 按码元）稳定排序、级别大写标签、整数/浮点/布尔/字符串既有渲染不变。该全序
/// 在 wasm-gc / js / native 三后端逐字节一致（已实测），且与 0.1.0 渲染逻辑
/// 逐字保留，故输出与骨架首版逐字节不变。
///
/// **Validates: Requirements 1.5, 12.4**
test "legacy scalar format_json is byte-identical to 0.1.0 (witness)" {
  // 字段刻意乱序构造，验证输出经既有排序稳定确定。
  let e = Event::new(7L, Level::Warn, {
    "msg": VStr("hi"),
    "count": VInt(42L),
    "ok": VBool(true),
    "ratio": VFloat(0.5),
  })
  let json = format_json(e)
  // 期望：fields 经 MoonBit String 全序（长度优先）稳定排序：
  //   ok(2) < msg(3) < count(5) < ratio(5，同长再按码元 c<r）。
  let expected = "{\"ts\":7,\"level\":\"WARN\",\"fields\":{" +
    "\"ok\":true,\"msg\":\"hi\",\"count\":42,\"ratio\":0.5}}"
  @test.assert_eq(json, expected)
  // 同时验证往返（往返与字段顺序无关：Map 相等按内容判定）。
  assert_true(parse_json_log(json) == Some(e))
}

///|
/// 空字段标量事件的字节级见证（边界）。
test "legacy empty-fields format_json byte-identical (witness)" {
  let e = Event::new(0L, Level::Info, Map([]))
  @test.assert_eq(format_json(e), "{\"ts\":0,\"level\":\"INFO\",\"fields\":{}}")
}
