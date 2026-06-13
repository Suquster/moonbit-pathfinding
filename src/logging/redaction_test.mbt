// redaction_test.mbt —— 嵌套整体掩码与键集合不变单元测试（任务 10.3）。
//
// 覆盖 Requirement 7.3（键集合不变、仅替换敏感字段）/ 7.4（嵌套整体掩码）。

///|
/// 敏感字段为嵌套 VMap / VList 时整体替换为掩码，内部无原值片段残留。
test "redact masks nested values wholesale" {
  let nested : Value = VMap({
    "card": VStr("4111111111111111"),
    "cvv": VInt(123L),
    "meta": VList([VStr("a"), VStr("b")]),
  })
  let e = Event::new(1L, Level::Info, { "secret": nested, "public": VStr("ok") })
  let policy = RedactionPolicy::by_names(["secret"])
  let red = redact(policy, e)
  // 敏感字段整体替换为掩码（不再是 VMap）。
  assert_true(red.fields.get("secret") == Some(redaction_mask))
  // 非敏感字段不变。
  assert_true(red.fields.get("public") == Some(VStr("ok")))
  // 整体渲染不含任何原值片段（卡号/cvv）。
  let json = format_json(red)
  assert_false(json.contains("4111111111111111"))
  assert_false(json.contains("123"))
  assert_true(json.contains("[REDACTED]"))
}

///|
/// 键集合脱敏前后一致；仅替换敏感字段取值。
test "redact preserves field key set" {
  let e = Event::new(2L, Level::Warn, {
    "password": VStr("hunter2"),
    "user": VStr("alice"),
    "id": VInt(7L),
  })
  let policy = RedactionPolicy::by_names(["password"])
  let red = redact(policy, e)
  assert_eq(red.fields.size(), e.fields.size())
  assert_true(red.fields.get("password") == Some(redaction_mask))
  assert_true(red.fields.get("user") == Some(VStr("alice")))
  assert_true(red.fields.get("id") == Some(VInt(7L)))
}

///|
/// 谓词命中的字段被掩码（Requirement 7.2）。
test "redact applies predicate-matched fields" {
  let e = Event::new(3L, Level::Info, {
    "email": VStr("a@b.com"),
    "name": VStr("bob"),
  })
  // 谓词：键以 "email" 命中。
  let policy = RedactionPolicy::by_names([]).with_predicate(fn(k, _v) {
    k == "email"
  })
  let red = redact(policy, e)
  assert_true(red.fields.get("email") == Some(redaction_mask))
  assert_true(red.fields.get("name") == Some(VStr("bob")))
}
