// ml_frontend_unit_test.mbt —— 任务 2.5：MiniML 词法 / 语法 / 打印单元测试。
//
// 目的（R2.1 / R2.2 / R2.3 / R8.1 / R8.2）：以一组**固定**的源串与手工构造的
// 语法树，逐字断言旁路新增前端三件套 `lex_ml` / `parse_ml` / `print_expr` 的
// 具体行为：
//   1. LEX——典型源串的 token 序列与精确 span（1 起始行列，逐字符计列）；多字符
//      算符（`<=` `>=` `==` `!=` `&&` `||` `->`）最长匹配、布尔归一为 `TkBool`、
//      关键字归一为 `TkKw`、括号与逗号。
//   2. PARSE——各优先级 / 结合性样例（乘除紧于加减、左结合、逻辑低于比较、应用
//      左结合）与 `if` / `fun` / `let` / `let rec` 结构，以 `erase_span` 去 span
//      后与期望树比较。
//   3. PRINT——手工构造 `Expr` 的 `print_expr` 完全括号化具体输出。
//   4. 错误——非法字符 `LexError`、非法文法与顶层残余 token 的 `SyntaxError`，
//      断言其 `kind` / `line` / `col`。
//
// 断言风格：`MlToken` / `Expr` / `Diagnostic` 仅派生 `Eq`（无 `Show`），故复合
// 比较用 `assert_true(x == y)`；标量（行 / 列 / 字符串）用 `assert_eq`。本文件为
// 旁路新增的黑盒 `_test.mbt`，不修改任何既有源文件；前端为已验证的真值来源
// （任务 2.1 / 2.2 / 2.3），期望值据其实际正确行为编码。

// ---------------------------------------------------------------------------
// 测试助手
// ---------------------------------------------------------------------------

///|
/// 去 span 的哨兵跨度（`erase_span` 与手工期望树统一使用）。
fn fe_z() -> Span {
  Span::{ line: 0, col: 0 }
}

///|
/// 词法分析并在失败时中止（夹具均为合法源串）。
fn fe_lex_ok(src : String) -> Array[MlToken] {
  match lex_ml(src) {
    Ok(t) => t
    Err(d) => abort("lex_ml 意外失败：\{d.msg}")
  }
}

///|
/// 源串 → 词法 → 语法 → 去 span 的 `Expr`；失败时中止。
fn fe_parse_ok(src : String) -> Expr {
  match parse_ml(fe_lex_ok(src)) {
    Ok(e) => erase_span(e)
    Err(d) => abort("parse_ml 意外失败：\{d.msg}")
  }
}

///|
/// 期望词法错误：取出诊断；若意外成功则中止。
fn fe_lex_err(src : String) -> Diagnostic {
  match lex_ml(src) {
    Ok(_) => abort("期望 LexError，但 lex_ml 成功")
    Err(d) => d
  }
}

///|
/// 期望语法错误：取出诊断；若意外成功则中止。
fn fe_parse_err(src : String) -> Diagnostic {
  // 词法先成功，再让 parse_ml 报语法错。
  match parse_ml(fe_lex_ok(src)) {
    Ok(_) => abort("期望 SyntaxError，但 parse_ml 成功")
    Err(d) => d
  }
}

// ---------------------------------------------------------------------------
// 1. LEX —— token 序列与精确 span
// ---------------------------------------------------------------------------

///|
/// 小输入精确 span：`"1 + 2"` 逐字符列定位（1 起始）。
test "lex_ml: precise spans for '1 + 2'" {
  assert_true(
    lex_ml("1 + 2") ==
    Ok([
      TkInt(1, Span::{ line: 1, col: 1 }),
      TkOp("+", Span::{ line: 1, col: 3 }),
      TkInt(2, Span::{ line: 1, col: 5 }),
    ]),
  )
}

///|
/// 关键字 / 标识符 / `=` / `fun` / `->` / `<=` / 整数综合序列与 span。
test "lex_ml: keywords, ident, arrow, '<=' sequence with spans" {
  assert_true(
    lex_ml("let rec f = fun n -> n <= 1") ==
    Ok([
      TkKw("let", Span::{ line: 1, col: 1 }),
      TkKw("rec", Span::{ line: 1, col: 5 }),
      TkIdent("f", Span::{ line: 1, col: 9 }),
      TkOp("=", Span::{ line: 1, col: 11 }),
      TkKw("fun", Span::{ line: 1, col: 13 }),
      TkIdent("n", Span::{ line: 1, col: 17 }),
      TkOp("->", Span::{ line: 1, col: 19 }),
      TkIdent("n", Span::{ line: 1, col: 22 }),
      TkOp("<=", Span::{ line: 1, col: 24 }),
      TkInt(1, Span::{ line: 1, col: 27 }),
    ]),
  )
}

///|
/// 布尔归一为 `TkBool`，`&&` 最长匹配。
test "lex_ml: booleans and '&&'" {
  assert_true(
    lex_ml("true && false") ==
    Ok([
      TkBool(true, Span::{ line: 1, col: 1 }),
      TkOp("&&", Span::{ line: 1, col: 6 }),
      TkBool(false, Span::{ line: 1, col: 9 }),
    ]),
  )
}

///|
/// 多字符比较 / 逻辑算符最长匹配：`>=` `==` `!=` `||`。
test "lex_ml: multi-char operators '>=' '==' '!=' '||'" {
  assert_true(
    lex_ml("a >= b == c != d || e") ==
    Ok([
      TkIdent("a", Span::{ line: 1, col: 1 }),
      TkOp(">=", Span::{ line: 1, col: 3 }),
      TkIdent("b", Span::{ line: 1, col: 6 }),
      TkOp("==", Span::{ line: 1, col: 8 }),
      TkIdent("c", Span::{ line: 1, col: 11 }),
      TkOp("!=", Span::{ line: 1, col: 13 }),
      TkIdent("d", Span::{ line: 1, col: 16 }),
      TkOp("||", Span::{ line: 1, col: 18 }),
      TkIdent("e", Span::{ line: 1, col: 21 }),
    ]),
  )
}

///|
/// 括号与逗号（元组词素）。
test "lex_ml: parens and comma" {
  assert_true(
    lex_ml("(1, 2)") ==
    Ok([
      TkLParen(Span::{ line: 1, col: 1 }),
      TkInt(1, Span::{ line: 1, col: 2 }),
      TkOp(",", Span::{ line: 1, col: 3 }),
      TkInt(2, Span::{ line: 1, col: 5 }),
      TkRParen(Span::{ line: 1, col: 6 }),
    ]),
  )
}

///|
/// 单字符 `-` 与 `->` 的最长匹配区分；`*` `/` 单字符算符。
test "lex_ml: single '-' vs '->' and '*' '/'" {
  assert_true(
    lex_ml("n - 1 * 2 / 3") ==
    Ok([
      TkIdent("n", Span::{ line: 1, col: 1 }),
      TkOp("-", Span::{ line: 1, col: 3 }),
      TkInt(1, Span::{ line: 1, col: 5 }),
      TkOp("*", Span::{ line: 1, col: 7 }),
      TkInt(2, Span::{ line: 1, col: 9 }),
      TkOp("/", Span::{ line: 1, col: 11 }),
      TkInt(3, Span::{ line: 1, col: 13 }),
    ]),
  )
}

// ---------------------------------------------------------------------------
// 2. PARSE —— 优先级 / 结合性 / 结构
// ---------------------------------------------------------------------------

///|
/// 乘除紧于加减：`1 + 2 * 3` → `1 + (2 * 3)`。
test "parse_ml: '*' binds tighter than '+'" {
  let z = fe_z()
  assert_true(
    fe_parse_ok("1 + 2 * 3") ==
    EArith(Add, EInt(1, z), EArith(Mul, EInt(2, z), EInt(3, z), z), z),
  )
}

///|
/// 加减左结合：`1 - 2 - 3` → `(1 - 2) - 3`。
test "parse_ml: '-' is left associative" {
  let z = fe_z()
  assert_true(
    fe_parse_ok("1 - 2 - 3") ==
    EArith(Sub, EArith(Sub, EInt(1, z), EInt(2, z), z), EInt(3, z), z),
  )
}

///|
/// 逻辑低于比较：`1 < 2 && true` → `(1 < 2) && true`。
test "parse_ml: '&&' lower precedence than comparison" {
  let z = fe_z()
  assert_true(
    fe_parse_ok("1 < 2 && true") ==
    ELogic(And, ECmp(Lt, EInt(1, z), EInt(2, z), z), EBool(true, z), z),
  )
}

///|
/// 逻辑 `||` 低于 `&&`：`a && b || c` → `(a && b) || c`。
test "parse_ml: '||' lower precedence than '&&'" {
  let z = fe_z()
  assert_true(
    fe_parse_ok("a && b || c") ==
    ELogic(Or, ELogic(And, EVar("a", z), EVar("b", z), z), EVar("c", z), z),
  )
}

///|
/// 函数应用左结合：`a b c` → `(a b) c`。
test "parse_ml: application is left associative" {
  let z = fe_z()
  assert_true(
    fe_parse_ok("a b c") ==
    EApp(EApp(EVar("a", z), EVar("b", z), z), EVar("c", z), z),
  )
}

///|
/// 应用紧于算术：`f x + 1` → `(f x) + 1`。
test "parse_ml: application binds tighter than arithmetic" {
  let z = fe_z()
  assert_true(
    fe_parse_ok("f x + 1") ==
    EArith(Add, EApp(EVar("f", z), EVar("x", z), z), EInt(1, z), z),
  )
}

///|
/// 条件 `if x then 1 else 2`。
test "parse_ml: if-then-else" {
  let z = fe_z()
  assert_true(
    fe_parse_ok("if x then 1 else 2") ==
    EIf(EVar("x", z), EInt(1, z), EInt(2, z), z),
  )
}

///|
/// 函数抽象 `fun x -> x + 1`。
test "parse_ml: lambda abstraction" {
  let z = fe_z()
  assert_true(
    fe_parse_ok("fun x -> x + 1") ==
    ELam("x", EArith(Add, EVar("x", z), EInt(1, z), z), z),
  )
}

///|
/// `let x = 1 in x`。
test "parse_ml: let binding" {
  let z = fe_z()
  assert_true(
    fe_parse_ok("let x = 1 in x") == ELet("x", EInt(1, z), EVar("x", z), z),
  )
}

///|
/// `let rec f = fun n -> n in f`。
test "parse_ml: let rec binding" {
  let z = fe_z()
  assert_true(
    fe_parse_ok("let rec f = fun n -> n in f") ==
    ELetRec("f", ELam("n", EVar("n", z), z), EVar("f", z), z),
  )
}

// ---------------------------------------------------------------------------
// 3. PRINT —— 完全括号化具体输出
// ---------------------------------------------------------------------------

///|
/// 原子打印：整数 / 布尔 / 变量。
test "print_expr: atoms" {
  let z = fe_z()
  assert_eq(print_expr(EInt(42, z)), "42")
  assert_eq(print_expr(EBool(true, z)), "true")
  assert_eq(print_expr(EBool(false, z)), "false")
  assert_eq(print_expr(EVar("x", z)), "x")
}

///|
/// 算术 / 比较 / 逻辑节点完全括号化。
test "print_expr: arithmetic, comparison, logic fully parenthesized" {
  let z = fe_z()
  assert_eq(
    print_expr(
      EArith(Add, EInt(1, z), EArith(Mul, EInt(2, z), EInt(3, z), z), z),
    ),
    "(1 + (2 * 3))",
  )
  assert_eq(print_expr(ECmp(Le, EInt(1, z), EInt(2, z), z)), "(1 <= 2)")
  assert_eq(
    print_expr(ELogic(Or, EBool(true, z), EBool(false, z), z)),
    "(true || false)",
  )
}

///|
/// 应用完全括号化：`((a b) c)`。
test "print_expr: application fully parenthesized" {
  let z = fe_z()
  assert_eq(
    print_expr(EApp(EApp(EVar("a", z), EVar("b", z), z), EVar("c", z), z)),
    "((a b) c)",
  )
}

///|
/// `if` / `fun` / `let` / `let rec` 整体外包括号。
test "print_expr: if, fun, let, let rec wrapped" {
  let z = fe_z()
  assert_eq(
    print_expr(EIf(EVar("x", z), EInt(1, z), EInt(2, z), z)),
    "(if x then 1 else 2)",
  )
  assert_eq(
    print_expr(ELam("x", EArith(Add, EVar("x", z), EInt(1, z), z), z)),
    "(fun x -> (x + 1))",
  )
  assert_eq(
    print_expr(ELet("x", EInt(1, z), EVar("x", z), z)),
    "(let x = 1 in x)",
  )
  assert_eq(
    print_expr(ELetRec("f", ELam("n", EVar("n", z), z), EVar("f", z), z)),
    "(let rec f = (fun n -> n) in f)",
  )
}

///|
/// 元组打印为 `(e1, e2, ...)`。
test "print_expr: tuple" {
  let z = fe_z()
  assert_eq(
    print_expr(ETuple([EInt(1, z), EInt(2, z), EBool(true, z)], z)),
    "(1, 2, true)",
  )
}

// ---------------------------------------------------------------------------
// 4. 错误 —— LexError / SyntaxError 的 kind / line / col
// ---------------------------------------------------------------------------

///|
/// 非法字符 `@`：`LexError`，定位到该字符（col 3）。
test "lex_ml: illegal char '@' yields LexError at its column" {
  let d = fe_lex_err("1 @ 2")
  assert_true(d.kind == LexError)
  assert_eq(d.line, 1)
  assert_eq(d.col, 3)
}

///|
/// 孤立 `!`（非 `!=`）：`LexError` 定位到 `!`（col 3）。
test "lex_ml: lone '!' yields LexError" {
  let d = fe_lex_err("a ! b")
  assert_true(d.kind == LexError)
  assert_eq(d.line, 1)
  assert_eq(d.col, 3)
}

///|
/// 孤立 `&`（非 `&&`）：`LexError` 定位到 `&`（col 3）。
test "lex_ml: lone '&' yields LexError" {
  let d = fe_lex_err("a & b")
  assert_true(d.kind == LexError)
  assert_eq(d.line, 1)
  assert_eq(d.col, 3)
}

///|
/// 孤立 `|`（非 `||`）：`LexError` 定位到 `|`（col 3）。
test "lex_ml: lone '|' yields LexError" {
  let d = fe_lex_err("a | b")
  assert_true(d.kind == LexError)
  assert_eq(d.line, 1)
  assert_eq(d.col, 3)
}

///|
/// 缺失右操作数：`1 +` → `SyntaxError`（退化到最后 token `+` 的位置 col 3）。
test "parse_ml: missing rhs yields SyntaxError" {
  let d = fe_parse_err("1 +")
  assert_true(d.kind == SyntaxError)
  assert_eq(d.line, 1)
  assert_eq(d.col, 3)
}

///|
/// 顶层残余 token：`1 )` → `SyntaxError` 定位到残余 `)`（col 3）。
test "parse_ml: leftover token yields SyntaxError" {
  let d = fe_parse_err("1 )")
  assert_true(d.kind == SyntaxError)
  assert_eq(d.line, 1)
  assert_eq(d.col, 3)
}

///|
/// 多余右括号：`(1))` → `SyntaxError` 定位到第二个 `)`（col 4）。
test "parse_ml: extra close paren yields SyntaxError" {
  let d = fe_parse_err("(1))")
  assert_true(d.kind == SyntaxError)
  assert_eq(d.line, 1)
  assert_eq(d.col, 4)
}

///|
/// 不完整 `let`：仅 `let` → `SyntaxError`（期望绑定名，退化到 `let` 位置 col 1）。
test "parse_ml: incomplete let yields SyntaxError" {
  let d = fe_parse_err("let")
  assert_true(d.kind == SyntaxError)
  assert_eq(d.line, 1)
  assert_eq(d.col, 1)
}

///|
/// 缺失 `else`：`if x then 1` → `SyntaxError`（退化到最后 token `1` 位置 col 11）。
test "parse_ml: missing else yields SyntaxError" {
  let d = fe_parse_err("if x then 1")
  assert_true(d.kind == SyntaxError)
  assert_eq(d.line, 1)
  assert_eq(d.col, 11)
}

///|
/// 空输入：`parse_ml([])` → `SyntaxError` 位置 (0, 0)。
test "parse_ml: empty input yields SyntaxError at (0,0)" {
  match parse_ml([]) {
    Ok(_) => abort("期望空输入 SyntaxError")
    Err(d) => {
      assert_true(d.kind == SyntaxError)
      assert_eq(d.line, 0)
      assert_eq(d.col, 0)
    }
  }
}
