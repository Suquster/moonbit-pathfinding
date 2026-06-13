// program_test.mbt —— 程序编译 `compile_program` 单元测试（任务 5.2）。
//
// 覆盖捕获组 `ISave` 槽位分配、贪婪 / 惰性 Split 臂序、`{m,n}` 展开、前瞻子
// 程序发射的结构见证（R2.1/3.1/5.4/5.5）。

///|
/// 测试辅助：解析并编译模式。
fn compile_of(s : String) -> Program {
  match parse_pattern(s) {
    Ok(a) => compile_program(a)
    Err(_) => compile_program(Empty)
  }
}

///|
/// 统计程序中 `ISave` 指令数。
fn count_saves(p : Program) -> Int {
  let mut c = 0
  for inst in p.insts {
    match inst {
      ISave(_) => c = c + 1
      _ => ()
    }
  }
  c
}

///|
/// 程序是否含前瞻子程序指令。
fn has_look(p : Program) -> Bool {
  for inst in p.insts {
    match inst {
      ILook(..) => return true
      _ => ()
    }
  }
  false
}

///|
/// 捕获组 `ISave` 槽位分配：n 个捕获组 → `2*(n+1)` 个 ISave（含第 0 组整体）。
test "compile_program allocates ISave slots per group" {
  let p = compile_of("(a)(b)")
  assert_eq(p.num_groups, 2)
  // 整体组(0) + 组1 + 组2 → 3 组 × 2 = 6 个 ISave。
  assert_eq(count_saves(p), 6)
}

///|
/// 非捕获组不发 `ISave`：仅整体组的 2 个 ISave。
test "compile_program non-capturing group emits no ISave" {
  let p = compile_of("(?:ab)")
  assert_eq(p.num_groups, 0)
  assert_eq(count_saves(p), 2)
}

///|
/// 命名组登记到 `names` 映射。
test "compile_program records named groups" {
  let p = compile_of("(?<year>a)(?<month>b)")
  assert_eq(p.num_groups, 2)
  assert_eq(p.names.get("year"), Some(1))
  assert_eq(p.names.get("month"), Some(2))
}

///|
/// 前瞻发射 `ILook` 子程序指令。
test "compile_program emits ILook for lookahead" {
  assert_true(has_look(compile_of("a(?=b)")))
  assert_true(has_look(compile_of("a(?!b)")))
  assert_false(has_look(compile_of("ab")))
}

///|
/// 贪婪 / 惰性 Split 臂序差异（经执行行为见证）：`{m,n}` 展开正确。
test "compile_program greedy/lazy and counted repeat via behavior" {
  // {2,3} 展开：匹配 2..3 个 'a'，最长取 3。
  let p = compile_of("a{2,3}")
  match p.exec("aaaa", kind=LeftmostFirst) {
    Some(c) =>
      match c.group(0) {
        Some(m) => assert_eq(m.end - m.start, 3)
        None => fail("expected group 0")
      }
    None => fail("expected match")
  }
  // 惰性 {2,3}? 在 LeftmostFirst 下取最短 2。
  let q = compile_of("a{2,3}?")
  match q.exec("aaaa", kind=LeftmostFirst) {
    Some(c) =>
      match c.group(0) {
        Some(m) => assert_eq(m.end - m.start, 2)
        None => fail("expected group 0")
      }
    None => fail("expected match")
  }
}
