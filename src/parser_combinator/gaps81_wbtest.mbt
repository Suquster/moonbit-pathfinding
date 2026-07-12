// gaps81_wbtest.mbt —— label 成功透传、Grammar::pure、诊断渲染余臂（第八十一批）。

///|
/// label：成功路径原样透传（值与剩余输入不变）。
test "label：成功路径原样透传" {
  match label(pchar('a'), "NAME").parse_string("ab") {
    Ok(v, rest) => {
      assert_eq(v, 'a')
      assert_eq(rest.pos.offset, 1)
    }
    Fail(_, ..) => fail("应当成功")
  }
}

///|
/// `<?>` 别名与 label 语义一致。
test "op_as_label：与 label 等价" {
  match op_as_label(pchar('z'), "NAME").parse_string("a") {
    Fail(_, expected~) => assert_true(expected == ["NAME"])
    Ok(_, _) => fail("应当失败")
  }
}

///|
/// Grammar::pure：不消费输入、恒成功、携带给定值。
test "Grammar::pure：恒成功不消费" {
  match Grammar::pure(42).run_naive_string("xyz") {
    Ok(v, rest) => {
      assert_eq(v, 42)
      assert_eq(rest.pos.offset, 0)
    }
    Fail(_, ..) => fail("pure 不应失败")
  }
}

///|
/// ParseResult::value：失败态返回 None。
test "ParseResult::value：失败返回 None" {
  assert_true(pchar('z').parse_string("a").value() is None)
}

///|
/// unexpected_at：失败位置为换行字符时的专名渲染。
test "unexpected_at：换行专名" {
  assert_eq(unexpected_at("a\nb", { line: 1, col: 2, offset: 1 }), "换行")
}
