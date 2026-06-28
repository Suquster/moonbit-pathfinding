// pikevm_test.mbt —— Pike VM 执行引擎单元测试（任务 6.6）。
//
// 覆盖入口存在性、病态输入线性见证、无匹配返回 `None` 不抛异常、前瞻成立 /
// 不成立、捕获不跨前瞻边界、贪婪 / 惰性与策略（R2.1/2.5、R5.4/5.5）。

///|
/// 测试辅助：编译模式（默认标志）为 Pike VM 程序。
fn prog_of(s : String) -> Program {
  match parse_pattern(s) {
    Ok(a) => compile_program(a)
    Err(_) => compile_program(Empty)
  }
}

///|
/// 测试辅助：以给定标志编译模式。
fn prog_of_flags(s : String, f : Flags) -> Program {
  match parse_pattern(s, flags=f) {
    Ok(a) => compile_program(a, flags=f)
    Err(_) => compile_program(Empty)
  }
}

///|
/// 测试辅助：提取第 i 组区间为 (start,end)。
fn grp(caps : Captures?, i : Int) -> (Int, Int)? {
  match caps {
    Some(c) =>
      match c.group(i) {
        Some(m) => Some((m.start, m.end))
        None => None
      }
    None => None
  }
}

///|
/// 测试辅助：判定无匹配（避免对 `Captures?` 直接 `==` 比较）。
fn no_match(caps : Captures?) -> Bool {
  match caps {
    None => true
    Some(_) => false
  }
}

///|
/// 编号捕获组：`(a)(b)` 在 "ab" 上提取整体与各子组区间。
test "pikevm captures numbered groups" {
  let p = prog_of("(a)(b)")
  let caps = p.exec("ab")
  assert_true(grp(caps, 0) == Some((0, 2)))
  assert_true(grp(caps, 1) == Some((0, 1)))
  assert_true(grp(caps, 2) == Some((1, 2)))
}

///|
/// 非捕获组不占编号：`(?:ab)(c)` 的捕获组仅 1 个。
test "pikevm non-capturing group does not allocate index" {
  let p = prog_of("(?:ab)(c)")
  let caps = p.exec("abc")
  assert_true(grp(caps, 0) == Some((0, 3)))
  assert_true(grp(caps, 1) == Some((2, 3)))
  match caps {
    Some(c) => assert_eq(c.group_count(), 2) // 含第 0 组
    None => fail("expected match")
  }
}

///|
/// 命名捕获组：按名检索与编号检索一致。
test "pikevm named group lookup" {
  let p = prog_of("(?<first>a)(?<second>b)")
  let caps = p.exec("ab")
  match caps {
    Some(c) => {
      assert_true(c.name("first") == c.group(1))
      assert_true(c.name("second") == c.group(2))
      assert_true(c.name("first") == Some({ start: 0, end: 1 }))
    }
    None => fail("expected match")
  }
}

///|
/// 未参与匹配的组返回未设置（None），不致整体失败。
test "pikevm unset group returns None" {
  let p = prog_of("(a)|(b)")
  let caps = p.exec("b")
  // 走通第二分支：组 1 未设置，组 2 = [0,1]。
  assert_true(grp(caps, 0) == Some((0, 1)))
  assert_true(grp(caps, 1) == None)
  assert_true(grp(caps, 2) == Some((0, 1)))
}

///|
/// 无匹配返回 `None`，不抛运行期异常。
test "pikevm no match returns None" {
  let p = prog_of("abc")
  assert_true(no_match(p.exec("xyz")))
  assert_false(p.is_match("xyz"))
  assert_true(p.is_match("xxabcyy"))
}

///|
/// 病态输入线性见证：`a*a*a*a*b` 在大量 'a' 无 'b' 上快速返回 `None`
/// （无回溯指数爆炸）。
test "pikevm pathological input terminates without backtracking blowup" {
  let p = prog_of("a*a*a*a*b")
  let mut input = ""
  for _i in 0..<64 {
    input = input + "a"
  }
  // 无结尾 'b' → 无匹配，线性时间返回。
  assert_true(no_match(p.exec(input)))
  // 末尾加 'b' → 匹配整串。
  assert_true(p.is_match(input + "b"))
}

///|
/// 正向前瞻 `(?=...)`：成立时匹配且不消费前瞻内容。
test "pikevm positive lookahead" {
  let p = prog_of("a(?=b)")
  // "ab"：'a' 后跟 'b'，前瞻成立，匹配 [0,1]（不消费 'b'）。
  assert_true(grp(p.exec("ab"), 0) == Some((0, 1)))
  // "ac"：'a' 后非 'b'，前瞻不成立，无匹配。
  assert_true(no_match(p.exec("ac")))
}

///|
/// 负向前瞻 `(?!...)`：当前位置之后不能匹配子模式时成立。
test "pikevm negative lookahead" {
  let p = prog_of("a(?!b)")
  // "ac"：'a' 后非 'b' → 成立，匹配 [0,1]。
  assert_true(grp(p.exec("ac"), 0) == Some((0, 1)))
  // "ab"：'a' 后是 'b' → 不成立，无匹配。
  assert_true(no_match(p.exec("ab")))
}

///|
/// 捕获不跨前瞻边界导出：前瞻内的捕获组不写回外层 Captures。
test "pikevm captures do not cross lookahead boundary" {
  let p = prog_of("a(?=(b))")
  let caps = p.exec("ab")
  // 整体匹配 [0,1]（零宽前瞻不消费）。
  assert_true(grp(caps, 0) == Some((0, 1)))
  // 前瞻内的组 1 不写回外层 → 未设置。
  assert_true(grp(caps, 1) == None)
}

///|
/// 词边界 `\b`：仅在词 / 非词过渡处成立。
test "pikevm word boundary" {
  let p = prog_of("\\ba")
  // "a"：串首前视为非词，'a' 为词 → 边界成立。
  assert_true(grp(p.exec("a"), 0) == Some((0, 1)))
  // "ba"：'a' 左侧 'b' 为词 → 'a' 前无边界；串中无其它 'a' 前边界 → 无匹配。
  assert_true(no_match(p.exec("ba")))
}

///|
/// 贪婪 vs 惰性（在 LeftmostFirst 策略下区分）：`a+` 取最长，`a+?` 取最短。
test "pikevm greedy vs lazy under leftmost-first" {
  let greedy = prog_of("a+")
  let lazy_prog = prog_of("a+?")
  assert_true(grp(greedy.exec("aaa", kind=LeftmostFirst), 0) == Some((0, 3)))
  assert_true(grp(lazy_prog.exec("aaa", kind=LeftmostFirst), 0) == Some((0, 1)))
}

///|
/// 匹配策略：`a|ab` 在 "ab" 上，LeftmostFirst 取首分支 "a"，LeftmostLongest 取最长 "ab"。
test "pikevm leftmost-first vs leftmost-longest" {
  let p = prog_of("a|ab")
  assert_true(grp(p.exec("ab", kind=LeftmostFirst), 0) == Some((0, 1)))
  assert_true(grp(p.exec("ab", kind=LeftmostLongest), 0) == Some((0, 2)))
}

///|
/// 大小写不敏感标志：`abc` 配 `i` 匹配 "ABC"。
test "pikevm case-insensitive flag" {
  let p = prog_of_flags("abc", Flags::parse("i"))
  assert_true(p.is_match("ABC"))
  assert_true(p.is_match("aBc"))
  assert_true(grp(p.exec("xABCy"), 0) == Some((1, 4)))
}

///|
/// 多行标志：`^a` 配 `m` 在每行行首匹配。
test "pikevm multiline anchor flag" {
  let p = prog_of_flags("^a", Flags::parse("m"))
  // "x\na"：第二行行首 'a' 命中 [2,3]。
  assert_true(grp(p.exec("x\na"), 0) == Some((2, 3)))
}
