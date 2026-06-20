// infer_unit_test.mbt —— 任务 5.4：Algorithm W 类型推断（infer.mbt，任务 5.1）
// 单元测试。
//
// 目的（R4.1 ~ R4.7 与 R8.3）：以一组**固定**的具体源串样例，逐字断言旁路推断
// 核心 `infer.mbt` 的主类型与类型错误诊断行为：
//   1. 单态结果精确相等：算术 / 比较 / if / let / let rec / 应用（R4.1/4.4/4.5）。
//   2. 恒等函数 `fun x -> x` 的主类型为 `TyFun(TyVar a, TyVar a)`（同一变量），
//      以 id-鲁棒方式断言（不硬编码新鲜变量 id）。
//   3. let 多态：`let id = fun x -> x in ...` 在 Int / Bool 处分别实例化，并以
//      「同一 id 同时用于 Bool 与 Int」的见证确认泛化（R4.2 / R4.3）。
//   4. let rec 递归阶乘的主类型与函数类型（R4.6）。
//   5. 不可合一程序返回 `TypeError`：携带 span（行列 ≥ 1）与非空冲突类型消息
//      （R8.3）；未绑定变量诊断含变量名（R8.4）。
//
// 构造 `Expr` 的方式：直接 PARSE 源串（`lex_ml` + `parse_ml`），比手工构造 AST
// 更简洁可靠。期望值据 `infer.mbt`（已验证真值来源）的实际推断输出对齐编码。
// 本文件为旁路新增的黑盒 `_test.mbt`，不修改任何既有源文件。

// ---------------------------------------------------------------------------
// 测试助手
// ---------------------------------------------------------------------------

///|
/// 词法 + 语法分析源串为 `Expr`；任何前置失败均中止（这些样例均为合法源串）。
fn iu_parse(src : String) -> Expr {
  let tokens = match lex_ml(src) {
    Ok(ts) => ts
    Err(d) => abort("词法分析意外失败：\{d.msg}")
  }
  match parse_ml(tokens) {
    Ok(e) => e
    Err(d) => abort("语法分析意外失败：\{d.msg}")
  }
}

///|
/// 推断源串并期望成功，返回主类型；意外失败则中止。
fn iu_ty(src : String) -> Ty {
  match infer(iu_parse(src)) {
    Ok((_, t)) => t
    Err(d) => abort("infer 意外失败：\{d.msg}")
  }
}

///|
/// 推断源串并期望类型错误，返回诊断；意外成功则中止。
fn iu_err(src : String) -> Diagnostic {
  match infer(iu_parse(src)) {
    Ok((_, t)) => abort("期望 infer 失败，但成功推断出类型：\{t}")
    Err(d) => d
  }
}

// ---------------------------------------------------------------------------
// 1. 单态结果精确相等（R4.1 / R4.4 / R4.5）
// ---------------------------------------------------------------------------

///|
/// 算术：`1 + 2` => TyInt。
test "infer: arithmetic yields TyInt" {
  assert_eq(iu_ty("1 + 2"), TyInt)
}

///|
/// 比较：`1 < 2` => TyBool。
test "infer: comparison yields TyBool" {
  assert_eq(iu_ty("1 < 2"), TyBool)
}

///|
/// 条件：`if true then 1 else 2` => TyInt（两分支同型）。
test "infer: if expression yields branch type" {
  assert_eq(iu_ty("if true then 1 else 2"), TyInt)
}

///|
/// `let`：`let x = 5 in x + 1` => TyInt。
test "infer: let binding yields body type" {
  assert_eq(iu_ty("let x = 5 in x + 1"), TyInt)
}

///|
/// 函数应用：`(fun x -> x + 1) 41` => TyInt。
test "infer: application of lambda yields TyInt" {
  assert_eq(iu_ty("(fun x -> x + 1) 41"), TyInt)
}

// ---------------------------------------------------------------------------
// 2. 恒等函数主类型：id-鲁棒断言（R4.1）
// ---------------------------------------------------------------------------

///|
/// `fun x -> x` 的主类型为 `TyFun(TyVar a, TyVar a)`：参数与结果是**同一**
/// 类型变量。不硬编码新鲜变量 id，仅断言两侧 id 相等。
test "infer: identity function has type a -> a (same var)" {
  match iu_ty("fun x -> x") {
    TyFun(TyVar(p), TyVar(q)) => assert_eq(p, q)
    other => abort("期望 TyFun(TyVar, TyVar)，实际：\{other}")
  }
}

// ---------------------------------------------------------------------------
// 3. let 多态：实例化与泛化见证（R4.2 / R4.3）
// ---------------------------------------------------------------------------

///|
/// `let id = fun x -> x in id 3` => TyInt（id 在 Int 处实例化）。
test "infer: let-polymorphism instantiates id at Int" {
  assert_eq(iu_ty("let id = fun x -> x in id 3"), TyInt)
}

///|
/// `let id = fun x -> x in id true` => TyBool（id 在 Bool 处实例化）。
test "infer: let-polymorphism instantiates id at Bool" {
  assert_eq(iu_ty("let id = fun x -> x in id true"), TyBool)
}

///|
/// 泛化见证：`let id = fun x -> x in if id true then id 1 else id 2` => TyInt。
/// 同一 `id` 在条件处用于 Bool、在分支处用于 Int，单态绑定将无法通过——成功推断
/// 出 TyInt 证明 `id` 被泛化为 `∀a. a -> a`（R4.2 / R4.3）。
test "infer: let-polymorphism allows id used at both Bool and Int" {
  assert_eq(
    iu_ty("let id = fun x -> x in if id true then id 1 else id 2"),
    TyInt,
  )
}

// ---------------------------------------------------------------------------
// 4. let rec 递归（R4.6）
// ---------------------------------------------------------------------------

///|
/// 递归阶乘整体应用：`let rec f = fun n -> ... in f 5` => TyInt。
test "infer: recursive factorial application yields TyInt" {
  assert_eq(
    iu_ty("let rec f = fun n -> if n <= 0 then 1 else n * f (n - 1) in f 5"),
    TyInt,
  )
}

///|
/// 裸递归函数：`let rec f = fun n -> ... in f` => TyFun(TyInt, TyInt)。
test "infer: recursive factorial function has type Int -> Int" {
  assert_eq(
    iu_ty("let rec f = fun n -> if n <= 0 then 1 else n * f (n - 1) in f"),
    TyFun(TyInt, TyInt),
  )
}

// ---------------------------------------------------------------------------
// 5. 类型错误：携带 span 与冲突类型消息（R8.3 / R8.4）
// ---------------------------------------------------------------------------

///|
/// `if 1 then 2 else 3`：条件为 Int 而非 Bool => TypeError。诊断携带 span
/// （行列 1 起始 ≥ 1）与非空消息。
test "infer: non-bool condition is a TypeError" {
  let d = iu_err("if 1 then 2 else 3")
  assert_true(d.kind == TypeError)
  assert_true(d.line >= 1)
  assert_true(d.col >= 1)
  assert_true(d.msg.length() > 0)
}

///|
/// `1 + true`：算术右操作数为 Bool 而非 Int => TypeError。
test "infer: arithmetic with bool right operand is a TypeError" {
  let d = iu_err("1 + true")
  assert_true(d.kind == TypeError)
  assert_true(d.line >= 1)
  assert_true(d.col >= 1)
  assert_true(d.msg.length() > 0)
}

///|
/// `true + 1`：算术左操作数为 Bool 而非 Int => TypeError。
test "infer: arithmetic with bool left operand is a TypeError" {
  let d = iu_err("true + 1")
  assert_true(d.kind == TypeError)
  assert_true(d.line >= 1)
  assert_true(d.col >= 1)
  assert_true(d.msg.length() > 0)
}

///|
/// 未绑定变量 `x` => TypeError，消息含变量名 `x`，span 指向变量（行列 ≥ 1）。
test "infer: unbound variable is a TypeError mentioning the name" {
  let d = iu_err("x")
  assert_true(d.kind == TypeError)
  assert_true(d.line >= 1)
  assert_true(d.col >= 1)
  assert_true(d.msg.contains("x"))
}
