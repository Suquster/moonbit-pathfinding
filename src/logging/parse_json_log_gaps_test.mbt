// parse_json_log_gaps_test.mbt —— 结构化日志 JSON 解析器错误分支覆盖收口
// （INFRA 第十七批）：顶层键类型不符、字段还原、转义与数值词法的确定性反例。

///|
fn lg_err(s : String) -> Bool {
  parse_json_log(s) is None
}

///|
test "parse_json_log 顶层键类型不符与缺键拒绝" {
  // ts 非数值 / 非法整数；level 非字符串 / 非法标签；fields 非对象。
  assert_true(lg_err("{\"ts\":\"x\",\"level\":\"INFO\",\"fields\":{}}"))
  assert_true(lg_err("{\"ts\":1e999x,\"level\":\"INFO\",\"fields\":{}}"))
  assert_true(lg_err("{\"ts\":1,\"level\":5,\"fields\":{}}"))
  assert_true(lg_err("{\"ts\":1,\"level\":\"nope\",\"fields\":{}}"))
  assert_true(lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":[]}"))
  // 缺任一必要键。
  assert_true(lg_err("{\"level\":\"INFO\",\"fields\":{}}"))
  assert_true(lg_err("{\"ts\":1,\"fields\":{}}"))
  assert_true(lg_err("{\"ts\":1,\"level\":\"INFO\"}"))
  // 未知顶层键被忽略（向前兼容）。
  assert_true(
    parse_json_log("{\"ts\":1,\"level\":\"INFO\",\"fields\":{},\"x\":1}")
    is Some(_),
  )
}

///|
test "parse_json_log 字段取值还原与非法数值拒绝" {
  // 嵌套对象 / 数组 / 浮点 / 整数还原。
  match
    parse_json_log(
      "{\"ts\":1,\"level\":\"INFO\"," +
      "\"fields\":{\"m\":{\"a\":1},\"l\":[1.5,true],\"s\":\"x\"}}",
    ) {
    Some(e) => {
      assert_true(e.fields.get("m") is Some(VMap(_)))
      assert_true(e.fields.get("l") is Some(VList(_)))
      assert_true(e.fields.get("s") == Some(VStr("x")))
    }
    None => assert_true(false)
  }
  // 字段中非法浮点 / 非法整数 / 嵌套对象成员非法 / 数组元素非法。
  assert_true(lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"a\":1.5.5}}"))
  assert_true(
    lg_err(
      "{\"ts\":1,\"level\":\"INFO\"," +
      "\"fields\":{\"a\":99999999999999999999999999}}",
    ),
  )
  assert_true(
    lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"m\":{\"a\":1.5.5}}}"),
  )
  assert_true(
    lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"l\":[1.5.5]}}"),
  )
}

///|
test "parse_json_log 转义与词法边界" {
  // \/、\uABCD 大写 hex、\u 小写 hex 可还原。
  match
    parse_json_log(
      "{\"ts\":1,\"level\":\"INFO\"," +
      "\"fields\":{\"s\":\"a\\/b\\u00E9\\u00e9\"}}",
    ) {
    Some(e) => assert_true(e.fields.get("s") == Some(VStr("a/béé")))
    None => assert_true(false)
  }
  // 悬挂反斜杠 / 未知转义 / \u 截断 / 非 hex / 未闭合字符串。
  assert_true(lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"s\":\"a\\"))
  assert_true(
    lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"s\":\"\\q\"}}"),
  )
  assert_true(
    lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"s\":\"\\u12\"}}"),
  )
  assert_true(
    lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"s\":\"\\u12G4\"}}"),
  )
  assert_true(lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"s\":\"ab"))
  // 数组结构破坏 / 关键字截断 / 纯负号 / 顶层垃圾。
  assert_true(lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"l\":[1 2]}}"))
  assert_true(lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"b\":tru}}"))
  assert_true(lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"n\":-}}"))
  assert_true(lg_err("{\"ts\":1,\"level\":\"INFO\",\"fields\":{\"n\":x}}"))
  assert_true(lg_err("{1:2}"))
  assert_true(lg_err("{\"a\" 2}"))
  assert_true(lg_err("{\"a\":1 \"b\":2}"))
  assert_true(lg_err("!"))
}
