// logging_nested_test.mbt —— 嵌套渲染/解析与标量回归单元测试（任务 2.4）。
//
// 覆盖 Requirement 1.3 / 1.4 / 1.5：嵌套 VMap/VList 的具体渲染与解析见证，
// 以及仅含标量字段事件输出与 0.1.0 逐字节一致的回归。

///|
/// VMap 渲染为 JSON 对象，成员按键名升序稳定排序（Requirement 1.3）。
test "format_json renders VMap as sorted JSON object" {
  let e = Event::new(1L, Level::Info, {
    "obj": VMap({ "z": VInt(1L), "a": VInt(2L), "m": VInt(3L) }),
  })
  let json = format_json(e)
  // obj 成员升序 a < m < z。
  assert_true(json.contains("\"obj\":{\"a\":2,\"m\":3,\"z\":1}"))
}

///|
/// VList 渲染为 JSON 数组，元素保持原序（Requirement 1.3）。
test "format_json renders VList as ordered JSON array" {
  let e = Event::new(1L, Level::Info, {
    "xs": VList([VInt(3L), VInt(1L), VInt(2L)]),
  })
  assert_true(format_json(e).contains("\"xs\":[3,1,2]"))
}

///|
/// 解析嵌套对象与数组还原为 VMap / VList（Requirement 1.4）。
test "parse_json_log restores nested object and array" {
  let json = "{\"ts\":2,\"level\":\"INFO\",\"fields\":{" +
    "\"o\":{\"a\":1,\"b\":\"x\"},\"l\":[1,true,\"y\"]}}"
  match parse_json_log(json) {
    Some(e) => {
      @test.assert_eq(e.ts, 2L)
      assert_true(
        e.fields.get("o") == Some(VMap({ "a": VInt(1L), "b": VStr("x") })),
      )
      assert_true(
        e.fields.get("l") == Some(VList([VInt(1L), VBool(true), VStr("y")])),
      )
    }
    None => fail("嵌套解析不应失败")
  }
}

///|
/// 深层嵌套整体往返（map -> list -> map -> scalar）。
test "deeply nested value round-trips" {
  let e = Event::new(9L, Level::Debug, {
    "deep": VMap({
      "a": VList([VMap({ "b": VList([VInt(1L), VFloat(0.25)]) })]),
    }),
  })
  assert_true(parse_json_log(format_json(e)) == Some(e))
}

///|
/// 仅含标量字段事件的渲染与既有行为一致（回归，Requirement 1.5）。
test "scalar-only events keep legacy rendering (regression)" {
  let e = Event::new(3L, Level::Error, {
    "a": VStr("x"),
    "b": VInt(-1L),
    "c": VBool(false),
  })
  let json = format_json(e)
  @test.assert_eq(
    json, "{\"ts\":3,\"level\":\"ERROR\",\"fields\":{\"a\":\"x\",\"b\":-1,\"c\":false}}",
  )
}
