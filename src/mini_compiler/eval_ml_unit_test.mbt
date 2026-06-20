// eval_ml_unit_test.mbt —— 任务 7.6：树遍历解释器与作用域检查（ml_eval.mbt，
// 任务 7.1）单元测试。
//
// 目的（R5.1 ~ R5.6 与 R8.4）：以一组**固定**的具体源串样例，逐字断言旁路解释器
// `eval_ml` 与作用域检查 `scope_check_ml`（已验证真值来源）的求值与诊断行为：
//   1. 闭包与词法捕获：闭包捕获**定义处**环境，不受调用处同名重绑定影响（R5.2/5.3）。
//   2. 遮蔽（shadowing）：内层 `let` 同名绑定遮蔽外层，作用域结束后恢复（R5.5）。
//   3. 递归（`let rec`）：阶乘 / 斐波那契自指递归（R5.6）。
//   4. 除零定义为 `0`：`a / 0 => VInt(0)`，保持全函数（R5.4）。
//   5. 比较 / 逻辑 / `if`：产出 `VBool` / 选择分支（R5.1）。
//   6. 高阶函数应用：`twice inc` 等（R5.2/5.3）。
//   7. `scope_check_ml`：闭合表达式 => `Ok(())`；含自由变量 => 携带变量 span
//      行列与变量名的 `TypeError` 诊断（R8.4）。
//
// 构造 `Val` 的方式：PARSE 源串（`lex_ml` + `parse_ml`）→ `infer` → `eval_ml`，
// 比手工构造带类型标注语法树更简洁可靠。期望值据 `ml_eval.mbt` 的实际输出对齐。
// 本文件为旁路新增的黑盒 `_test.mbt`，不修改任何既有源文件。

// ---------------------------------------------------------------------------
// 测试助手
// ---------------------------------------------------------------------------

///|
/// 词法 + 语法分析源串为 `Expr`；任何前置失败均中止（这些样例均为合法源串）。
fn ev_parse(src : String) -> Expr {
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
/// 解析 → 推断 → 求值源串为 `Val`；任何前置失败均中止（这些样例均为良类型）。
fn run(src : String) -> Val {
  match infer(ev_parse(src)) {
    Ok((te, _)) => eval_ml(te)
    Err(d) => abort("infer 意外失败：\{d.msg}")
  }
}

///|
/// 作用域检查源串（**在推断前**对 `Expr` 检查）并期望失败，返回诊断；意外通过
/// 则中止。
fn scope_err(src : String) -> Diagnostic {
  match scope_check_ml(ev_parse(src)) {
    Ok(_) =>
      abort(
        "期望 scope_check_ml 失败（含自由变量），但通过了检查",
      )
    Err(d) => d
  }
}

// ---------------------------------------------------------------------------
// 1. 闭包与词法捕获（R5.2 / R5.3）
// ---------------------------------------------------------------------------

///|
/// 闭包捕获**定义处**环境：`f` 捕获 `x = 1`，调用处的 `let x = 100` 不影响它。
/// `let x = 1 in let f = fun y -> x + y in let x = 100 in f 5` => VInt(6)。
test "eval: closure captures lexical environment, not call-site x" {
  assert_true(
    run("let x = 1 in let f = fun y -> x + y in let x = 100 in f 5") == VInt(6),
  )
}

// ---------------------------------------------------------------------------
// 2. 遮蔽（shadowing，R5.5）
// ---------------------------------------------------------------------------

///|
/// 内层 `let` 同名绑定遮蔽外层：`let x = 1 in let x = 2 in x` => VInt(2)。
test "eval: inner let shadows outer binding" {
  assert_true(run("let x = 1 in let x = 2 in x") == VInt(2))
}

///|
/// 遮蔽仅在内层作用域生效，作用域结束后恢复外层：
/// `let x = 10 in (let x = 20 in x) + x` => 20 + 10 = VInt(30)。
test "eval: shadowing is scoped, outer binding restored after inner scope" {
  assert_true(run("let x = 10 in (let x = 20 in x) + x") == VInt(30))
}

// ---------------------------------------------------------------------------
// 3. 递归（let rec，R5.6）
// ---------------------------------------------------------------------------

///|
/// 阶乘递归：`let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f 5`
/// => 5! = VInt(120)。
test "eval: recursive factorial" {
  assert_true(
    run("let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f 5") ==
    VInt(120),
  )
}

///|
/// 斐波那契递归（双递归调用）：
/// `let rec fib = fun n -> if n <= 1 then n else fib (n - 1) + fib (n - 2) in fib 10`
/// => fib(10) = VInt(55)。
test "eval: recursive fibonacci" {
  assert_true(
    run(
      "let rec fib = fun n -> if n <= 1 then n else fib (n - 1) + fib (n - 2) in fib 10",
    ) ==
    VInt(55),
  )
}

// ---------------------------------------------------------------------------
// 4. 除零定义为 0（R5.4）
// ---------------------------------------------------------------------------

///|
/// 除零定义为 `0`（保持全函数）：`10 / 0` => VInt(0)。
test "eval: division by zero yields zero" {
  assert_true(run("10 / 0") == VInt(0))
}

///|
/// 除零（被除数来自绑定）：`let x = 7 in x / 0` => VInt(0)。
test "eval: division by zero with bound dividend yields zero" {
  assert_true(run("let x = 7 in x / 0") == VInt(0))
}

// ---------------------------------------------------------------------------
// 5. 比较 / 逻辑 / if（R5.1）
// ---------------------------------------------------------------------------

///|
/// 条件选择 then 分支：`if 2 < 3 then 7 else 8` => VInt(7)。
test "eval: if selects then branch on true condition" {
  assert_true(run("if 2 < 3 then 7 else 8") == VInt(7))
}

///|
/// 逻辑与（两侧皆真）：`(1 < 2) && (3 > 2)` => VBool(true)。
test "eval: logical and of two true comparisons" {
  assert_true(run("(1 < 2) && (3 > 2)") == VBool(true))
}

///|
/// 逻辑或（两侧皆假）：`(1 > 2) || false` => VBool(false)。
test "eval: logical or of two false operands" {
  assert_true(run("(1 > 2) || false") == VBool(false))
}

// ---------------------------------------------------------------------------
// 6. 高阶函数应用（R5.2 / R5.3）
// ---------------------------------------------------------------------------

///|
/// 高阶函数 `twice`：把函数作用两次。
/// `let twice = fun f -> fun x -> f (f x) in let inc = fun n -> n + 1 in twice inc 10`
/// => inc(inc(10)) = VInt(12)。
test "eval: higher-order twice applies a function twice" {
  assert_true(
    run(
      "let twice = fun f -> fun x -> f (f x) in let inc = fun n -> n + 1 in twice inc 10",
    ) ==
    VInt(12),
  )
}

// ---------------------------------------------------------------------------
// 7. 作用域检查（R8.4 / R8.6）
// ---------------------------------------------------------------------------

///|
/// 闭合表达式通过作用域检查：`let x = 1 in x` => Ok(())。
test "scope_check_ml: closed expression is accepted" {
  match scope_check_ml(ev_parse("let x = 1 in x")) {
    Ok(_) => ()
    Err(d) =>
      abort(
        "期望闭合表达式通过作用域检查，但被拒绝：\{d.msg}",
      )
  }
}

///|
/// 单一自由变量 `x`（源串 `"x"`）：作用域检查返回携带变量 span 与变量名的
/// `TypeError` 诊断。`x` 位于源串第 1 行第 1 列，故 line == 1、col == 1（R8.4）。
test "scope_check_ml: lone free variable yields TypeError carrying its span and name" {
  let d = scope_err("x")
  assert_true(d.kind == TypeError)
  assert_true(d.msg.contains("x"))
  assert_eq(d.line, 1)
  assert_eq(d.col, 1)
}

///|
/// 嵌套自由变量 `z`：`let y = 1 in y + z` —— `z` 自由（`y` 已绑定）。诊断为
/// `TypeError`，消息含变量名 `z`，span 指向 `z` 的列。源串中 `z` 位于第 1 行，
/// 其前缀 `let y = 1 in y + ` 共 17 字符，故 `z` 在第 18 列（1 起始，R8.4）。
test "scope_check_ml: nested free variable yields TypeError at its column" {
  let d = scope_err("let y = 1 in y + z")
  assert_true(d.kind == TypeError)
  assert_true(d.msg.contains("z"))
  assert_eq(d.line, 1)
  assert_eq(d.col, 18)
}

///|
/// 自由变量的 span 行列均为 1 起始正值（与 R8.4 的「携带变量 span」一致）。
test "scope_check_ml: free variable diagnostic span uses 1-based positions" {
  let d = scope_err("a + 1")
  assert_true(d.kind == TypeError)
  assert_true(d.msg.contains("a"))
  assert_true(d.line >= 1)
  assert_true(d.col >= 1)
}
