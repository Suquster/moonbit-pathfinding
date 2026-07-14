// prop_nested_json_test.mbt —— 嵌套 JSON 往返属性测试（任务 2.2）。
//
//   Feature: logging, Property 1: 嵌套 JSON 往返（nested JSON round-trip）
//   --------------------------------------------------------------------
//   *对任意* 含任意嵌套深度取值（VMap/VList 任意层级嵌套标量与复合取值）的
//   事件 e，`parse_json_log(format_json(e)) == Some(e)`。统摄 VMap→对象 /
//   VList→数组 的渲染与还原、对象成员升序稳定排序与任意层级嵌套保真。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代，满足 ≥100 基线）与
// `round_trip`（经 Bytes 桥接）。生成器为 `sh_nested_event`（深度上界 3）。

///|
/// Bytes 编码桥接：Event -> format_json -> Bytes（纯 ASCII 输出，逐字符低 8 位）。
fn nj_encode(e : Event) -> Bytes {
  let s = format_json(e)
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// Bytes 解码桥接：Bytes -> JSON 文本 -> parse_json_log。
fn nj_decode(b : Bytes) -> Event? {
  let mut s = ""
  let mut i = 0
  while i < b.length() {
    s = s + b[i].to_int().unsafe_to_char().to_string()
    i = i + 1
  }
  parse_json_log(s)
}

///|
/// 嵌套取值的具体见证：多层 VMap/VList 往返还原等价事件。
test "nested json round-trip on representative nested events (witness)" {
  let samples : Array[Event] = [
    // 对象内含数组、数组内含对象。
    Event::new(1L, Level::Info, {
      "user": VMap({ "id": VInt(7L), "name": VStr("ann"), "vip": VBool(true) }),
      "tags": VList([VStr("a"), VStr("b"), VInt(3L)]),
    }),
    // 三层嵌套：map -> list -> map。
    Event::new(-5L, Level::Error, {
      "tree": VMap({ "kids": VList([VMap({ "leaf": VFloat(0.125) })]) }),
    }),
    // 空嵌套容器。
    Event::new(0L, Level::Debug, {
      "empty_map": VMap(Map([])),
      "empty_list": VList([]),
    }),
  ]
  for e in samples {
    match parse_json_log(format_json(e)) {
      Some(out) => assert_true(out == e)
      None => fail("嵌套事件往返不应失败")
    }
  }
}

///|
/// Feature: logging, Property 1: 嵌套 JSON 往返（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 1.2, 1.3, 1.4, 1.6**
test "Feature: logging, Property 1: nested json round-trip (holds_for_all)" {
  let ok = @infra_pbt.holds_for_all(sh_nested_event(), fn(e) {
    parse_json_log(format_json(e)) == Some(e)
  })
  assert_true(ok)
}

///|
/// Feature: logging, Property 1: 嵌套 JSON 往返（round_trip 模板，≥100 迭代）
///
/// **Validates: Requirements 1.2, 1.3, 1.4, 1.6**
test "Feature: logging, Property 1: nested json round-trip (round_trip bridge)" {
  let ok = @infra_pbt.round_trip(sh_nested_event(), nj_encode, nj_decode)
  assert_true(ok)
}
