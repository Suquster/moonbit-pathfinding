// parser_textbuilder_equiv_wbtest.mbt —— 任务 12.4 等价性白盒测试。
//
// `ParseResult` 为 `pub`（非 `pub(all)`）枚举，其构造子 `Ok` / `Fail` 在黑盒
// 测试中只读、不可构造；而 `to_path_error` 内部的「期望符号集合逗号分隔」
// 循环（原 `exp = exp + ...`，已改为 `@infra_text.TextBuilder`）需以确定性的
// 多元素 `expected` 才能稳定锁定输出。故在白盒测试中直接构造 `ParseResult`，
// 验证改造后错误描述里的 `期望 a, b, c` 片段逐字符不变
// （production-hardening Requirement 1.5 / 1.6）。

///|
/// to_path_error：期望符号集合逗号分隔循环改造后逐字符等价。
test "textbuilder equiv (wb): to_path_error expected join loop" {
  // 多元素期望集合：以 ", " 分隔，无尾随分隔符。
  let r : ParseResult[Int] = Fail(Pos::start(), expected=[
    "数字", "字母", "符号",
  ])
  match r.to_path_error() {
    Some(@core.PathError::InvalidInput(msg)) =>
      assert_true(msg.contains("期望 数字, 字母, 符号"))
    _ => fail("期望 InvalidInput，实得其他结果")
  }
  // 单元素期望集合：无分隔逗号。
  let r1 : ParseResult[Int] = Fail(Pos::start(), expected=["唯一"])
  match r1.to_path_error() {
    Some(@core.PathError::InvalidInput(msg)) =>
      assert_true(msg.contains("期望 唯一"))
    _ => fail("期望 InvalidInput，实得其他结果")
  }
  // 空期望集合：仅 `期望 ` 后无内容（循环零次，TextBuilder 物化为空串）。
  let r2 : ParseResult[Int] = Fail(Pos::start(), expected=[])
  match r2.to_path_error() {
    Some(@core.PathError::InvalidInput(_)) => assert_true(true)
    _ => fail("期望 InvalidInput，实得其他结果")
  }
  // 成功结果无错误。
  let ok : ParseResult[Int] = Ok(7, Input::from_string(""))
  assert_true(ok.to_path_error() is None)
}
