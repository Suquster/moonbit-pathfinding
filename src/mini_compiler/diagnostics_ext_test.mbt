// diagnostics_ext_test.mbt —— T1.4 诊断增强：渲染与修复建议的定向用例 + 属性。

///|
/// 便捷前端：lex → parse → infer，返回首个诊断。
fn infer_src(src : String) -> Result[(TExpr, Ty), Diagnostic] {
  match lex_ml(src) {
    Err(d) => Err(d)
    Ok(toks) =>
      match parse_ml(toks) {
        Err(d) => Err(d)
        Ok(e) => infer(e)
      }
  }
}

///|
test "T1.4: render_diagnostic shows source line, caret and hint" {
  // if 条件用了整数：既有管线报 Int/Bool 合一失败。
  let src = "if 1 then 2 else 3"
  match infer_src(src) {
    Err(d) => {
      let report = render_diagnostic(src, d)
      assert_true(report.contains("type error @ "))
      assert_true(report.contains(src))
      assert_true(report.contains("^"))
      assert_true(report.contains("hint: "))
    }
    Ok(_) => assert_true(false)
  }
}

///|
test "T1.4: unbound variable diagnostic carries position and scope hint" {
  let src = "let x = 1 in y"
  match infer_src(src) {
    Err(d) => {
      assert_true(d.msg.contains("未绑定变量"))
      let report = render_diagnostic(src, d)
      assert_true(report.contains("作用域"))
      // caret 对准第 14 列的 y。
      assert_eq(d.line, 1)
      assert_eq(d.col, 14)
    }
    Ok(_) => assert_true(false)
  }
}

///|
test "T1.4: suggestion families cover unify shapes" {
  // 元组形态。
  let td = Diagnostic::new(
    TypeError,
    1,
    1,
    "cannot unify TyTuple([TyInt]) with TyTuple([TyInt, TyInt])",
  )
  assert_true(render_diagnostic("(1)", td).contains("元数"))
  // 函数误用形态。
  let fd = Diagnostic::new(
    TypeError,
    1,
    1,
    "cannot unify TyInt with TyFun(TyInt, TyInt)",
  )
  assert_true(render_diagnostic("1 2", fd).contains("函数"))
  // occurs check 形态。
  let od = Diagnostic::new(
    TypeError,
    1,
    1,
    "occurs check: cannot construct infinite type t0 ~ TyFun(t0, t1)",
  )
  assert_true(render_diagnostic("fun x -> x x", od).contains("无限类型"))
}

///|
/// T1.4 属性：渲染确定性 + 结构完整——对任意行列与消息，两次渲染逐字节一致，
/// 且标题行必含 `line:col` 与原消息（100 迭代）。
test "T1.4 property: render_diagnostic is deterministic and complete (100 iters)" {
  let gen = @infra_pbt.gen_int_range(0, 1000000)
  let ok = @infra_pbt.holds_for_all(gen, fn(seed) {
    let line = seed % 3 + 1
    let col = seed / 3 % 10 + 1
    let msg = if seed % 2 == 0 {
      "cannot unify TyInt with TyBool"
    } else {
      "未绑定变量 'v\{seed % 7}'"
    }
    let d = Diagnostic::new(TypeError, line, col, msg)
    let src = "let a = 1 in\nlet b = 2 in\na + b"
    let r1 = render_diagnostic(src, d)
    let r2 = render_diagnostic(src, d)
    r1 == r2 &&
    r1.contains("\{line}:\{col}") &&
    r1.contains(msg) &&
    r1.contains("hint: ")
  })
  assert_true(ok)
}
