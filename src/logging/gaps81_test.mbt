// gaps81_test.mbt —— logfmt 解析拒绝与 env-filter 边界收口（第八十一批）。

///|
/// 值 token 非法 JSON（截断数组）→ 整行拒绝。
test "logfmt：值 JSON 截断被拒绝" {
  assert_true(parse_logfmt("ts=1 level=info k=[1,") is None)
}

///|
/// 值 JSON 合法但超出 Int64 表示范围 → 语义还原失败被拒绝。
test "logfmt：整数溢出值被拒绝" {
  assert_true(
    parse_logfmt("ts=1 level=info k=99999999999999999999999999") is None,
  )
}

///|
/// 值之后紧跟非空白字符 → 分隔约定破坏被拒绝。
test "logfmt：值后非空白分隔被拒绝" {
  assert_true(parse_logfmt("ts=1 level=info k=\"v\"x") is None)
}

///|
/// '=' 前空目标 → 解析错误。
test "env-filter：空目标被拒绝" {
  match parse_env_filter("=info") {
    Err(e) => assert_eq(e.message, "empty target before '='")
    Ok(_) => fail("应当拒绝空目标")
  }
}

///|
/// 仅含 target=level 指令、无裸级别 → 回退级别保持默认。
test "env-filter：无裸级别时回退默认" {
  let f = parse_env_filter("core=debug").unwrap()
  assert_true(f.threshold_for("core") is Debug)
}
