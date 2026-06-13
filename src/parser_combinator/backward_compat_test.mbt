// backward_compat_test.mbt —— 向后兼容回归测试（task 17.2）。
//
// 校验既有 `0.1.0` 公开契约在旗舰深化（0.2.0）后签名与行为不变（R14.1 /
// R14.2 / R14.5）：核心类型 `Parser[T]` / `ParseResult[T]` / `Input` / `Pos`、
// 原语 `pchar` / `satisfy` / `any_char` / `ptoken`、组合子 `seq` / `alt` /
// `many` / `many1` / `optional`，以及 `to_path_error` 桥接语义。
//
// 注：`alt` 的**成功路径**行为不变；其失败诊断由 0.1.0 精化为最远失败（属
// 严格信息增益，已在 CHANGELOG/README 显式声明），本文件相应校验成功路径
// 与「同位置全失败」退化为既有顺序汇总两个方面。

///|
/// 核心类型与游标：Input 推进 / 行列计算 / EOF 语义不变。
test "compat: Input cursor and Pos semantics unchanged" {
  let input = Input::from_string("a\nb")
  assert_eq(input.pos.offset, 0)
  inspect(input.pos, content="1:1")
  let after = input.advance().advance()
  inspect(after.pos, content="2:1")
  assert_true(after.peek() == Some('b'))
  assert_false(input.is_eof())
}

///|
/// 原语签名与行为不变：pchar / satisfy / any_char / ptoken。
test "compat: primitives unchanged" {
  assert_true(pchar('a').parse_string("abc").value() == Some('a'))
  assert_true(
    satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
    .parse_string("7")
    .is_ok(),
  )
  assert_true(any_char().parse_string("z").value() == Some('z'))
  assert_true(ptoken("let").parse_string("let x").value() == Some("let"))
  // 失败定位不变
  match pchar('x').parse_string("abc") {
    Fail(pos, expected~) => {
      assert_eq(pos.offset, 0)
      assert_true(expected == ["'x'"])
    }
    Ok(_, _) => fail("expected failure")
  }
}

///|
/// 组合子签名与行为不变：seq / many / many1 / optional。
test "compat: combinators seq/many/many1/optional unchanged" {
  // seq 产出二元组
  assert_true(
    seq(pchar('a'), pchar('b')).parse_string("abc").value() == Some(('a', 'b')),
  )
  // many 零次成功
  let empty : Array[Char] = []
  assert_true(many(pchar('a')).parse_string("bbb").value() == Some(empty))
  // many1 至少一次
  assert_true(many1(pchar('a')).parse_string("aab").value() == Some(['a', 'a']))
  // optional 回溯
  assert_true(optional(pchar('a')).parse_string("xyz").value() == Some(None))
}

///|
/// alt 成功路径不变 + 同位置全失败退化为既有顺序汇总（R14.2）。
test "compat: alt success path and same-position aggregation unchanged" {
  // 成功路径：首个成功分支
  assert_true(
    alt([pchar('a'), pchar('b'), pchar('c')]).parse_string("bzz").value() ==
    Some('b'),
  )
  // 同位置全失败：期望按分支顺序去重汇总（与 0.1.0 一致）
  match alt([pchar('a'), pchar('b')]).parse_string("zzz") {
    Fail(pos, expected~) => {
      inspect(pos, content="1:1")
      assert_eq(pos.offset, 0)
      assert_true(expected == ["'a'", "'b'"])
    }
    Ok(_, _) => fail("expected failure")
  }
}

///|
/// to_path_error 桥接语义不变（R14.3）。
test "compat: to_path_error bridge semantics unchanged" {
  assert_true(pchar('a').parse_string("abc").to_path_error() is None)
  match pchar('x').parse_string("abc").to_path_error() {
    Some(InvalidInput(_)) => assert_true(true)
    _ => fail("expected InvalidInput bridge")
  }
}
