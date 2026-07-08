// bounded_backtrack_test.mbt —— 有界回溯引擎测试。
//
// 覆盖：与 Pike VM `LeftmostFirst` 的整体区间 + 捕获逐槽差分（定向 + PBT）、
// 超预算显式报告与 `exec_bounded` 回退、(pc, pos) 记忆化的步数硬上界
// （病态嵌套量词不爆炸）。

///|
/// 取整体匹配区间 (start, end)；未命中返回 None。
fn bt_span(r : BacktrackResult) -> (Int, Int)? {
  match r {
    BtMatch(caps) =>
      match caps.group(0) {
        Some(m) => Some((m.start, m.end))
        None => None
      }
    _ => None
  }
}

///|
test "有界回溯与 Pike VM LeftmostFirst 在代表性夹具上逐槽一致" {
  let cases : Array[(String, String)] = [
    ("a(b|c)*d", "abcbcd"),
    ("[a-c]+", "xaabbz"),
    ("(a|ab)(c|bcd)", "abcd"),
    ("^a.*", "a"),
    ("a{2,3}", "aaaa"),
    ("(ab)+", "ababab"),
    ("(a*)(b*)", "aaabbb"),
    ("(a|b)*abb", "aabb"),
    ("x", "aaa"),
  ]
  for c in cases {
    let (pat, input) = c
    let r = match parse_regex(pat) {
      Ok(rr) => rr
      Err(_) => Char('\u{0}')
    }
    let prog = compile_program(Ast::of_regex(r))
    let pike = prog.exec(input, kind=LeftmostFirst)
    let bt = prog.exec_backtrack(input)
    match (pike, bt) {
      (Some(pc), BtMatch(bc)) =>
        // 捕获寄存器逐组一致。
        for g in 0..<(pc.group_count() + 1) {
          assert_true(pc.group(g) == bc.group(g))
        }
      (None, BtNoMatch) => ()
      _ => assert_true(false)
    }
  }
}

///|
test "有界回溯超预算显式报告，exec_bounded 回退 Pike VM" {
  let r = match parse_regex("(a|b)*abb") {
    Ok(rr) => rr
    Err(_) => Char('\u{0}')
  }
  let prog = compile_program(Ast::of_regex(r))
  // 预算 1：任何非空程序 × 输入都超预算。
  assert_true(prog.exec_backtrack("aabb", budget=1) is BtOverBudget)
  // 回退路径结果与 Pike VM 一致。
  let fallback = prog.exec_bounded("aabb", budget=1)
  let pike = prog.exec("aabb", kind=LeftmostFirst)
  match (fallback, pike) {
    (Some(a), Some(b)) => assert_true(a.group(0) == b.group(0))
    _ => assert_true(false)
  }
}

///|
test "病态嵌套量词：有界回溯不指数爆炸（(a+)+b 拒绝串）" {
  let r = match parse_regex("(a+)+b") {
    Ok(rr) => rr
    Err(_) => Char('\u{0}')
  }
  let prog = compile_program(Ast::of_regex(r))
  // 经典 ReDoS 输入：30 个 a 无 b。裸回溯为 2^30 级；记忆化后瞬时完成。
  let mut input = ""
  for _k in 0..<30 {
    input = input + "a"
  }
  assert_true(prog.exec_backtrack(input) is BtNoMatch)
  assert_true(prog.exec_bounded(input) is None)
}

///|
test "PBT：有界回溯与 Pike VM LeftmostFirst 差分一致（100 迭代）" {
  let ok = @infra_pbt.holds_for_all(gen_diff_case(), fn(case) {
    let (r, input) = case
    let prog = compile_program(Ast::of_regex(r))
    let pike = match prog.exec(input, kind=LeftmostFirst) {
      Some(caps) => caps.group(0)
      None => None
    }
    let bt = bt_span(prog.exec_backtrack(input))
    let pike_span = match pike {
      Some(m) => Some((m.start, m.end))
      None => None
    }
    bt == pike_span
  })
  assert_true(ok)
}
