// json_gaps_wbtest.mbt —— LSP JSON 解析/渲染错误分支覆盖收口
// （INFRA 第十八批）：转义全谱、\uXXXX 词法、控制字符渲染、
// 数值 id 字面量边界的确定性反例。

///|
test "lsp json 字符串转义解析全谱" {
  // \b \f \/ \uXXXX（大小写 hex）可还原。
  match parse_json("\"a\\b\\f\\/\\u0041\\u004a\\u004A\"") {
    Some(JStr(s)) => assert_true(s == "a\u{08}\u{0C}/AJJ")
    _ => assert_true(false)
  }
  // 非法转义 / \u 截断 / 非 hex / 悬挂反斜杠 / 未闭合。
  assert_true(parse_json("\"\\q\"") is None)
  assert_true(parse_json("\"\\u00\"") is None)
  assert_true(parse_json("\"\\u00zz\"") is None)
  assert_true(parse_json("\"a\\") is None)
  assert_true(parse_json("\"abc") is None)
}

///|
test "lsp json 结构与关键字破坏拒绝" {
  // 对象：键非字符串 / 缺冒号 / 缺分隔。
  assert_true(parse_json("{1:2}") is None)
  assert_true(parse_json("{\"a\" 1}") is None)
  assert_true(parse_json("{\"a\":1 \"b\":2}") is None)
  // 数组：缺分隔 / 未闭合。
  assert_true(parse_json("[1 2]") is None)
  assert_true(parse_json("[1,") is None)
  // 关键字截断 / 顶层垃圾。
  assert_true(parse_json("tru") is None)
  assert_true(parse_json("nul") is None)
  assert_true(parse_json("!") is None)
}

///|
test "lsp json 控制字符渲染与 \\u 往返" {
  // 0x01（< 0x20 且非命名转义）→ \u0001；0x08/0x0C → \b/\f。
  let s = (0x01).unsafe_to_char().to_string() +
    (0x08).unsafe_to_char().to_string() +
    (0x0C).unsafe_to_char().to_string() +
    (0x1F).unsafe_to_char().to_string()
  let sb = StringBuilder::new()
  write_json(sb, JStr(s))
  let text = sb.to_string()
  assert_true(text == "\"\\u0001\\b\\f\\u001f\"")
  // 渲染→解析往返恒等。
  match parse_json(text) {
    Some(JStr(back)) => assert_true(back == s)
    _ => assert_true(false)
  }
}

///|
test "lsp json 整数 id 字面量边界" {
  assert_true(parse_int_literal("") is None)
  assert_true(parse_int_literal("-") is None)
  assert_true(parse_int_literal("+") is None)
  assert_true(parse_int_literal("+7") == Some(7))
  assert_true(parse_int_literal("-12") == Some(-12))
  assert_true(parse_int_literal("1.5") is None)
  assert_true(parse_int_literal("1e3") is None)
}
