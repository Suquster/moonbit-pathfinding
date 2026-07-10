// lookbehind_test.mbt —— 后顾 `(?<=...)` / `(?<!...)` 完备化（INFRA 第五十五批）。
//
// 后顾以翻转 AST 编译的子程序自锚点向左反向扫描（Pike VM，线性时间），
// 支持变长后顾体、嵌套环视、断言与标志。

///|
fn lb_prog(s : String) -> Program {
  match parse_pattern(s) {
    Ok(a) => compile_program(a)
    Err(_) => compile_program(Empty)
  }
}

///|
fn lb_grp0(caps : Captures?) -> (Int, Int)? {
  match caps {
    Some(c) =>
      match c.group(0) {
        Some(m) => Some((m.start, m.end))
        None => None
      }
    None => None
  }
}

///|
test "后顾：正向定长与负向" {
  // (?<=a)b：仅当 b 前是 a。
  let p = lb_prog("(?<=a)b")
  assert_eq(lb_grp0(p.exec("ab")), Some((1, 2)))
  assert_true(p.exec("cb") is None)
  assert_true(p.exec("b") is None)
  // (?<!a)b：b 前不是 a（含文首）。
  let q = lb_prog("(?<!a)b")
  assert_eq(lb_grp0(q.exec("b")), Some((0, 1)))
  assert_eq(lb_grp0(q.exec("cb")), Some((1, 2)))
  assert_true(q.exec("ab") is None)
}

///|
test "后顾：变长体与择一" {
  // (?<=ab+)c：b 的数量任意。
  let p = lb_prog("(?<=ab+)c")
  assert_eq(lb_grp0(p.exec("abc")), Some((2, 3)))
  assert_eq(lb_grp0(p.exec("abbbbc")), Some((5, 6)))
  assert_true(p.exec("ac") is None)
  // 择一体：(?<=foo|ba)r。
  let q = lb_prog("(?<=foo|ba)r")
  assert_eq(lb_grp0(q.exec("foor")), Some((3, 4)))
  assert_eq(lb_grp0(q.exec("bar")), Some((2, 3)))
  assert_true(q.exec("car") is None)
}

///|
test "后顾：串接顺序正确（非回文体）" {
  // 体 "abc" 非回文：验证反向执行仍按原文顺序匹配。
  let p = lb_prog("(?<=abc)d")
  assert_eq(lb_grp0(p.exec("abcd")), Some((3, 4)))
  assert_true(p.exec("cbad") is None)
}

///|
test "后顾：与前瞻嵌套及断言" {
  // (?<=\d)-(?=\d)：数字间的连字符。
  let p = lb_prog("(?<=\\d)-(?=\\d)")
  assert_eq(lb_grp0(p.exec("1-2")), Some((1, 2)))
  assert_true(p.exec("a-2") is None)
  assert_true(p.exec("1-b") is None)
  // 后顾体内嵌前瞻：(?<=a(?=.c))b —— a 后瞻 .c（即 bc）。
  let q = lb_prog("(?<=a(?=.c))b")
  assert_eq(lb_grp0(q.exec("abc")), Some((1, 2)))
  assert_true(q.exec("abd") is None)
  // 体内词边界：(?<=\ba)b。
  let r = lb_prog("(?<=\\ba)b")
  assert_eq(lb_grp0(r.exec("ab")), Some((1, 2)))
  assert_true(r.exec("xab") is None)
}

///|
test "后顾：忽略大小写标志与打印往返" {
  let f = Flags::default()
  let fi = { ..f, ignore_case: true }
  let p = match parse_pattern("(?<=A)b", flags=fi) {
    Ok(a) => compile_program(a, flags=fi)
    Err(_) => compile_program(Empty)
  }
  assert_true(p.is_match("ab"))
  assert_true(p.is_match("AB"))
  // 打印往返：print_ast 输出可重解析且等价。
  match parse_pattern("(?<=ab)c") {
    Ok(a) => {
      let printed = print_ast(a)
      assert_eq(printed, "(?<=ab)c")
      match parse_pattern(printed) {
        Ok(a2) => assert_true(a == a2)
        Err(_) => fail("打印往返应可重解析")
      }
    }
    Err(_) => fail("(?<=ab)c 应可解析")
  }
  match parse_pattern("(?<!x)y") {
    Ok(a) => assert_eq(print_ast(a), "(?<!x)y")
    Err(_) => fail("(?<!x)y 应可解析")
  }
}

///|
test "后顾：捕获不跨后顾边界，负后顾体不可匹配时恒真" {
  // 后顾体内的组不导出到外层捕获。
  let p = lb_prog("(?<=(a))b")
  match p.exec("ab") {
    Some(c) =>
      match c.group(1) {
        Some(_) => fail("后顾体内捕获不应导出")
        None => assert_true(true)
      }
    None => fail("(?<=(a))b 应匹配 ab")
  }
  // 负后顾体不可能匹配（空字符类近似：用不存在的字符）→ 恒真。
  let q = lb_prog("(?<!z)a")
  assert_eq(lb_grp0(q.exec("a")), Some((0, 1)))
}
