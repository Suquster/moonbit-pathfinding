// compat_golden_test.mbt —— 任务 1.4：MiniLet 黄金样例向后兼容单元测试。
//
// 目的（R12.1 / R12.2 / R12.3）：以一组**固定**的 MiniLet 程序，逐字断言
// 既有冻结流水线 `lex` / `parse` / `check` / `eval` / `print_ast` 的产物与
// `0.1.0` 骨架完全一致，并确认 `compile` 桩签名与 `Diagnostic::new` 行为
// 不变。本文件为旁路新增的黑盒 `_test.mbt`，不修改任何既有源文件。
//
// 断言风格：对 `Token` / `Ast` / `TypedAst` / `Value` 等复合类型采用
// `assert_true(x == y)`（走派生的 `Eq`），与既有 `mini_compiler_test.mbt`
// 一致以避免触发 `Show`-用于-debug 的弃用告警；整数 / 字符串用 `assert_eq`。
//
// 若某条黄金断言与实现不符：实现为**冻结正确**资产，应订正本测试的期望值，
// 不得改动任何 `.mbt` 源文件。

// ---------------------------------------------------------------------------
// 测试助手：在失败时中止（夹具均为合法输入）。
// ---------------------------------------------------------------------------

///|
/// 词法分析并在失败时中止。
fn golden_lex(s : String) -> Array[Token] {
  match lex(s) {
    Ok(t) => t
    Err(d) => abort("lex 意外失败：\{d.msg}")
  }
}

///|
/// 源串 → 词法 → 语法，返回 AST；失败时中止。
fn golden_parse(s : String) -> Ast {
  match parse(golden_lex(s)) {
    Ok(a) => a
    Err(d) => abort("parse 意外失败：\{d.msg}")
  }
}

///|
/// 源串 → … → 类型检查，返回 TypedAst；失败时中止。
fn golden_check(s : String) -> TypedAst {
  match check(golden_parse(s)) {
    Ok(t) => t
    Err(d) => abort("check 意外失败：\{d.msg}")
  }
}

///|
/// 源串 → … → 求值，返回 Value；失败时中止。
fn golden_eval(s : String) -> Value {
  eval(golden_check(s))
}

// ---------------------------------------------------------------------------
// 黄金样例 1：整数字面量 "42"
// ---------------------------------------------------------------------------

///|
test "golden: integer literal 42 across all stages" {
  let src = "42"
  // lex
  assert_true(golden_lex(src) == [IntLit(42)])
  // parse
  assert_true(golden_parse(src) == Int(42))
  // check
  assert_true(golden_check(src) == TInt(42))
  // eval
  assert_true(golden_eval(src) == IntV(42))
  // print_ast 逐字
  @test.assert_eq(print_ast(golden_parse(src)), "42")
}

// ---------------------------------------------------------------------------
// 黄金样例 2：let 绑定变量 "let x = 1 in x"
// ---------------------------------------------------------------------------

///|
test "golden: let-bound variable across all stages" {
  let src = "let x = 1 in x"
  // lex
  assert_true(
    golden_lex(src) == [KwLet, Ident("x"), Assign, IntLit(1), KwIn, Ident("x")],
  )
  // parse
  assert_true(golden_parse(src) == Let("x", Int(1), Var("x")))
  // check
  assert_true(golden_check(src) == TLet("x", TInt(1), TVar("x", IntT), IntT))
  // eval
  assert_true(golden_eval(src) == IntV(1))
  // print_ast 逐字
  @test.assert_eq(print_ast(golden_parse(src)), "let x = 1 in x")
}

// ---------------------------------------------------------------------------
// 黄金样例 3：运算符优先级 "1 + 2 * 3"
// ---------------------------------------------------------------------------

///|
test "golden: arithmetic precedence across all stages" {
  let src = "1 + 2 * 3"
  // lex
  assert_true(golden_lex(src) == [IntLit(1), Plus, IntLit(2), Star, IntLit(3)])
  // parse：乘除优先级高于加减 → 1 + (2 * 3)
  assert_true(golden_parse(src) == Bin(Add, Int(1), Bin(Mul, Int(2), Int(3))))
  // check
  assert_true(
    golden_check(src) ==
    TBin(Add, TInt(1), TBin(Mul, TInt(2), TInt(3), IntT), IntT),
  )
  // eval：1 + 6 = 7
  assert_true(golden_eval(src) == IntV(7))
  // print_ast：完全括号化
  @test.assert_eq(print_ast(golden_parse(src)), "(1 + (2 * 3))")
}

// ---------------------------------------------------------------------------
// 黄金样例 4：let 内含算术 "let x = 10 in x - 4"
// ---------------------------------------------------------------------------

///|
test "golden: let with arithmetic body across all stages" {
  let src = "let x = 10 in x - 4"
  // lex
  assert_true(
    golden_lex(src) ==
    [KwLet, Ident("x"), Assign, IntLit(10), KwIn, Ident("x"), Minus, IntLit(4)],
  )
  // parse
  assert_true(
    golden_parse(src) == Let("x", Int(10), Bin(Sub, Var("x"), Int(4))),
  )
  // check
  assert_true(
    golden_check(src) ==
    TLet("x", TInt(10), TBin(Sub, TVar("x", IntT), TInt(4), IntT), IntT),
  )
  // eval：10 - 4 = 6
  assert_true(golden_eval(src) == IntV(6))
  // print_ast 逐字
  @test.assert_eq(print_ast(golden_parse(src)), "let x = 10 in (x - 4)")
}

// ---------------------------------------------------------------------------
// 黄金样例 5：嵌套 let "let x = 1 in let y = 2 in x + y"
// ---------------------------------------------------------------------------

///|
test "golden: nested let across all stages" {
  let src = "let x = 1 in let y = 2 in x + y"
  // lex
  assert_true(
    golden_lex(src) ==
    [
      KwLet,
      Ident("x"),
      Assign,
      IntLit(1),
      KwIn,
      KwLet,
      Ident("y"),
      Assign,
      IntLit(2),
      KwIn,
      Ident("x"),
      Plus,
      Ident("y"),
    ],
  )
  // parse
  assert_true(
    golden_parse(src) ==
    Let("x", Int(1), Let("y", Int(2), Bin(Add, Var("x"), Var("y")))),
  )
  // check
  assert_true(
    golden_check(src) ==
    TLet(
      "x",
      TInt(1),
      TLet(
        "y",
        TInt(2),
        TBin(Add, TVar("x", IntT), TVar("y", IntT), IntT),
        IntT,
      ),
      IntT,
    ),
  )
  // eval：x=1, y=2 → 1 + 2 = 3
  assert_true(golden_eval(src) == IntV(3))
  // print_ast 逐字
  @test.assert_eq(
    print_ast(golden_parse(src)),
    "let x = 1 in let y = 2 in (x + y)",
  )
}

// ---------------------------------------------------------------------------
// 黄金样例 6：除零 = 0 "let z = 5 in z / 0"
// ---------------------------------------------------------------------------

///|
test "golden: division by zero is defined as zero across all stages" {
  let src = "let z = 5 in z / 0"
  // lex
  assert_true(
    golden_lex(src) ==
    [KwLet, Ident("z"), Assign, IntLit(5), KwIn, Ident("z"), Slash, IntLit(0)],
  )
  // parse
  assert_true(golden_parse(src) == Let("z", Int(5), Bin(Div, Var("z"), Int(0))))
  // check
  assert_true(
    golden_check(src) ==
    TLet("z", TInt(5), TBin(Div, TVar("z", IntT), TInt(0), IntT), IntT),
  )
  // eval：除零定义为 0（MiniLet 全函数约定）
  assert_true(golden_eval(src) == IntV(0))
  // print_ast 逐字
  @test.assert_eq(print_ast(golden_parse(src)), "let z = 5 in (z / 0)")
}

// ---------------------------------------------------------------------------
// 「打印再解析」往返自洽：print_ast(parse(lex(src))) 再解析还原同一 AST。
// ---------------------------------------------------------------------------

///|
test "golden: print_ast round-trips structurally for all fixtures" {
  let fixtures : Array[String] = [
    "42", "let x = 1 in x", "1 + 2 * 3", "let x = 10 in x - 4", "let x = 1 in let y = 2 in x + y",
    "let z = 5 in z / 0",
  ]
  for src in fixtures {
    let ast = golden_parse(src)
    // 对打印结果重新词法 + 语法分析，应还原等价 AST。
    assert_true(parse(golden_lex(print_ast(ast))) == Ok(ast))
  }
}

// ---------------------------------------------------------------------------
// compile 签名与 Diagnostic::new 行为保持兼容。
// ---------------------------------------------------------------------------

///|
/// compile 对任一后端均返回非空、带目标格式标识的真实产物。
test "golden: compile returns wasm and js artifacts" {
  let typed = golden_check("let x = 10 in x - 4")
  let wasm = compile(typed, Wasm)
  let js = compile(typed, Js)
  assert_true(wasm.length() > 8)
  @test.assert_eq(wasm[0], 0x00)
  @test.assert_eq(wasm[1], 0x61)
  @test.assert_eq(wasm[2], 0x73)
  @test.assert_eq(wasm[3], 0x6d)
  assert_true(js.length() > 0)
  assert_true(compile(TInt(42), Wasm).length() > 8)
}

///|
/// Diagnostic::new 逐字构造期望结构（kind / line / col / msg 原样保留，R12.2）。
test "golden: Diagnostic::new builds expected struct verbatim" {
  let d = Diagnostic::new(LexError, 1, 3, "非法字符 '@'")
  assert_true(d.kind == LexError)
  @test.assert_eq(d.line, 1)
  @test.assert_eq(d.col, 3)
  @test.assert_eq(d.msg, "非法字符 '@'")
  // 整体结构相等（走派生 Eq）。
  assert_true(d == Diagnostic::new(LexError, 1, 3, "非法字符 '@'"))
  // 不同类别 / 位置构造亦原样保留。
  let d2 = Diagnostic::new(SyntaxError, 2, 7, "期望 ')'")
  assert_true(d2.kind == SyntaxError)
  @test.assert_eq(d2.line, 2)
  @test.assert_eq(d2.col, 7)
  @test.assert_eq(d2.msg, "期望 ')'")
  let d3 = Diagnostic::new(TypeError, 0, 0, "未绑定变量 'q'")
  assert_true(d3.kind == TypeError)
  @test.assert_eq(d3.line, 0)
  @test.assert_eq(d3.col, 0)
  @test.assert_eq(d3.msg, "未绑定变量 'q'")
}
