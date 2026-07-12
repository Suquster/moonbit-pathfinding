// gaps82_wbtest.mbt —— 诊断摘录行号越界余臂（第八十二批）。

///|
/// source_line_at：行号超出源末行时返回空串。
test "source_line_at：行号越界返回空串" {
  assert_eq(source_line_at("a\nb", 5), "")
}

///|
/// choice：零分支耗尽 → 在输入起点报空期望软失败。
test "choice：空分支列表软失败" {
  let g : Grammar[Int] = choice([])
  match g.run_naive_string("abc") {
    Fail(pos, expected~) => {
      assert_eq(pos.offset, 0)
      assert_eq(expected.length(), 0)
    }
    Ok(_, _) => fail("空 choice 应失败")
  }
}
