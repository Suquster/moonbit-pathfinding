// mini_compiler_test.mbt —— Mini_Compiler 任务 15.1 的单元测试。
//
// 在小型确定性夹具上校验：词法分析成功形态、词法错误的含行列诊断（R1.3）、
// 语法分析成功形态与优先级、语法错误的含位置诊断（R1.3），以及 `print_ast`
// 与 `parse∘lex` 的「打印再解析」互逆自洽（为任务 15.3「Property 1」奠基），
// 并贯通 `check` / `eval` 流水线桩。
//
// 说明：对 `Ast` / `Token` / `Result` 等复合类型采用 `assert_true(x == y)`
// （走派生的 `Eq`），以避免触发 `Show`-用于-debug 的弃用告警，保持本包零告警。

// ---------------------------------------------------------------------------
// 测试助手
// ---------------------------------------------------------------------------

///|
/// 词法分析并在失败时中止（夹具均为合法输入）。
fn lex_ok(s : String) -> Array[Token] {
  match lex(s) {
    Ok(t) => t
    Err(d) => abort("lex 意外失败：\{d.msg}")
  }
}

///|
/// 源串 → 词法 → 语法，返回 AST；失败时中止（夹具均为合法输入）。
fn parse_ok(s : String) -> Ast {
  match parse(lex_ok(s)) {
    Ok(a) => a
    Err(d) => abort("parse 意外失败：\{d.msg}")
  }
}

// ---------------------------------------------------------------------------
// 词法分析（lex）成功形态
// ---------------------------------------------------------------------------

///|
/// 算术表达式切分为整数与运算符词法单元。
test "lex arithmetic tokens" {
  assert_true(
    lex_ok("1 + 2 * 30") == [IntLit(1), Plus, IntLit(2), Star, IntLit(30)],
  )
}

///|
/// `let` 绑定切分，关键字 `let` / `in` 归一为 `KwLet` / `KwIn`。
test "lex let binding tokens with keywords" {
  assert_true(
    lex_ok("let x = 1 in x") ==
    [KwLet, Ident("x"), Assign, IntLit(1), KwIn, Ident("x")],
  )
}

///|
/// 标识符可含数字与下划线；`let`/`in` 作前缀的标识符不误判为关键字。
test "lex identifiers with digits and underscores" {
  assert_true(
    lex_ok("foo_1 lets income") ==
    [Ident("foo_1"), Ident("lets"), Ident("income")],
  )
}

///|
/// 括号与全部算术符号。
test "lex parens and all operators" {
  assert_true(
    lex_ok("(a - b) / c") ==
    [LParen, Ident("a"), Minus, Ident("b"), RParen, Slash, Ident("c")],
  )
}

// ---------------------------------------------------------------------------
// 词法错误：含行列位置的诊断，不产生后续产物（R1.3）
// ---------------------------------------------------------------------------

///|
/// 非法字符 `@` → LexError，位置定位到该字符（行 1 列 3）。
test "lex illegal char reports line and column" {
  match lex("a @ b") {
    Err(d) => {
      assert_true(d.kind == LexError)
      assert_eq(d.line, 1)
      assert_eq(d.col, 3)
    }
    Ok(_) => fail("期望词法错误")
  }
}

///|
/// 换行后非法字符 → 行列号随换行更新（行 2 列 1）。
test "lex illegal char tracks newlines" {
  match lex("12\n#") {
    Err(d) => {
      assert_true(d.kind == LexError)
      assert_eq(d.line, 2)
      assert_eq(d.col, 1)
    }
    Ok(_) => fail("期望词法错误")
  }
}

// ---------------------------------------------------------------------------
// 语法分析（parse）成功形态与优先级 / 结合性
// ---------------------------------------------------------------------------

///|
/// 单个整数 / 变量原子。
test "parse atoms" {
  assert_true(parse_ok("42") == Int(42))
  assert_true(parse_ok("foo") == Var("foo"))
}

///|
/// 乘除优先级高于加减：`1 + 2 * 3` → `1 + (2 * 3)`。
test "parse precedence mul over add" {
  assert_true(
    parse_ok("1 + 2 * 3") == Bin(Add, Int(1), Bin(Mul, Int(2), Int(3))),
  )
}

///|
/// 加减左结合：`1 - 2 - 3` → `(1 - 2) - 3`。
test "parse left associativity" {
  assert_true(
    parse_ok("1 - 2 - 3") == Bin(Sub, Bin(Sub, Int(1), Int(2)), Int(3)),
  )
}

///|
/// 括号改变结合范围：`(1 + 2) * 3`。
test "parse parentheses override precedence" {
  assert_true(
    parse_ok("(1 + 2) * 3") == Bin(Mul, Bin(Add, Int(1), Int(2)), Int(3)),
  )
}

///|
/// `let` 绑定解析为 `Let` 节点，body 可为复合表达式。
test "parse let binding" {
  assert_true(
    parse_ok("let x = 1 in x + 2") ==
    Let("x", Int(1), Bin(Add, Var("x"), Int(2))),
  )
}

// ---------------------------------------------------------------------------
// 语法错误：含位置的诊断，不产生 AST（R1.3）
// ---------------------------------------------------------------------------

///|
/// 运算符后缺操作数 → SyntaxError「期望表达式」。
test "parse missing operand is a syntax error" {
  match parse(lex_ok("1 +")) {
    Err(d) => assert_true(d.kind == SyntaxError)
    Ok(_) => fail("期望语法错误")
  }
}

///|
/// 未闭合括号 → SyntaxError「期望 ')'」。
test "parse unbalanced paren is a syntax error" {
  match parse(lex_ok("(1 + 2")) {
    Err(d) => assert_true(d.kind == SyntaxError)
    Ok(_) => fail("期望语法错误")
  }
}

///|
/// 顶层残余输入 → SyntaxError「多余的输入」。
test "parse trailing input is a syntax error" {
  match parse(lex_ok("1 2")) {
    Err(d) => assert_true(d.kind == SyntaxError)
    Ok(_) => fail("期望语法错误")
  }
}

// ---------------------------------------------------------------------------
// 打印器 print_ast 与「打印再解析」互逆自洽（Property 1 的基础校验）
// ---------------------------------------------------------------------------

///|
/// print_ast 基本形态：二元运算完全括号化，let 按文法形态打印。
test "print_ast basic shapes" {
  inspect(print_ast(Int(42)), content="42")
  inspect(print_ast(Var("foo")), content="foo")
  inspect(print_ast(Bin(Add, Int(1), Int(2))), content="(1 + 2)")
  inspect(
    print_ast(Let("x", Int(1), Bin(Mul, Var("x"), Int(2)))),
    content="let x = 1 in (x * 2)",
  )
}

///|
/// 对若干手工 AST，`parse(lex(print_ast(a)))` 应得到等价 AST（往返自洽）。
test "round-trip parse of print" {
  let samples : Array[Ast] = [
    Int(0),
    Int(123),
    Var("x"),
    Bin(Add, Int(1), Int(2)),
    Bin(Mul, Bin(Add, Int(1), Int(2)), Int(3)),
    Bin(Sub, Bin(Sub, Int(1), Int(2)), Int(3)),
    Bin(Div, Var("a"), Var("b")),
    Let("x", Int(1), Bin(Add, Var("x"), Int(2))),
    Let("y", Bin(Mul, Int(2), Int(3)), Let("z", Var("y"), Var("z"))),
  ]
  for a in samples {
    assert_true(parse(lex_ok(print_ast(a))) == Ok(a))
  }
}

// ---------------------------------------------------------------------------
// 类型检查 check（任务 15.2）：作用域内结构性标注与自由变量类型错误（R1.4/R1.5）
// ---------------------------------------------------------------------------

///|
/// 全部变量均被绑定时，check 在作用域内结构性标注为 TypedAst（统一 IntT）。
test "check annotates bound program structurally" {
  assert_true(
    check(Let("x", Int(1), Bin(Add, Int(1), Var("x")))) ==
    Ok(TLet("x", TInt(1), TBin(Add, TInt(1), TVar("x", IntT), IntT), IntT)),
  )
}

///|
/// 纯算术（无变量）通过类型检查。
test "check pure arithmetic succeeds" {
  assert_true(
    check(Bin(Mul, Int(2), Int(3))) == Ok(TBin(Mul, TInt(2), TInt(3), IntT)),
  )
}

///|
/// 自由变量（未绑定）→ TypeError 诊断，msg 标注出错变量名（R1.5）。
test "check unbound variable is a type error" {
  match check(Bin(Add, Int(1), Var("x"))) {
    Err(d) => {
      assert_true(d.kind == TypeError)
      assert_true(d.msg.contains("x"))
    }
    Ok(_) => fail("期望类型错误（自由变量 x）")
  }
}

///|
/// let 绑定的可见性：被绑定表达式在外层作用域检查，引用 body 外名字仍报错。
/// `let x = y in x` —— y 自由 → TypeError。
test "check let does not bind name in its own bound expr" {
  match check(Let("x", Var("y"), Var("x"))) {
    Err(d) => assert_true(d.kind == TypeError)
    Ok(_) => fail("期望类型错误（自由变量 y）")
  }
}

// ---------------------------------------------------------------------------
// 求值 eval（任务 15.2）：树遍历解释器、let 作用域、除零、确定性（R1.6）
// ---------------------------------------------------------------------------

///|
/// 源串 → 词法 → 语法 → 类型检查 → 求值，返回整数；任一阶段失败则中止。
fn run_int(s : String) -> Int {
  let ast = parse_ok(s)
  match check(ast) {
    Err(d) => abort("check 意外失败：\{d.msg}")
    Ok(t) =>
      match eval(t) {
        IntV(n) => n
      }
  }
}

///|
/// 整数字面量求值。
test "eval literal yields int value" {
  assert_eq(run_int("7"), 7)
}

///|
/// 算术求值遵循优先级与结合性：1 + 2 * 3 = 7。
test "eval respects precedence" {
  assert_eq(run_int("1 + 2 * 3"), 7)
}

///|
/// 减法左结合：10 - 3 - 2 = 5。
test "eval left-associative subtraction" {
  assert_eq(run_int("10 - 3 - 2"), 5)
}

///|
/// 括号改变求值范围：(1 + 2) * 3 = 9。
test "eval parentheses change grouping" {
  assert_eq(run_int("(1 + 2) * 3"), 9)
}

///|
/// 整数截断除法：7 / 2 = 3。
test "eval integer truncating division" {
  assert_eq(run_int("7 / 2"), 3)
}

///|
/// let 绑定与变量查找：let x = 2 in x * x = 4。
test "eval let binding and variable lookup" {
  assert_eq(run_int("let x = 2 in x * x"), 4)
}

///|
/// 嵌套 let 与内层遮蔽：let x = 1 in let x = 10 in x + 1 = 11。
test "eval nested let shadows outer binding" {
  assert_eq(run_int("let x = 1 in let x = 10 in x + 1"), 11)
}

///|
/// 被绑定表达式可引用外层绑定：let x = 3 in let y = x + 1 in x * y = 12。
test "eval inner binding sees outer scope" {
  assert_eq(run_int("let x = 3 in let y = x + 1 in x * y"), 12)
}

///|
/// 除零定义为 0（MiniLet 语义规范，保证全函数与三后端一致）。
test "eval division by zero is defined as zero" {
  assert_eq(run_int("1 / 0"), 0)
  assert_eq(run_int("(5 + 5) / (3 - 3)"), 0)
}

///|
/// 求值确定性：同一程序重复求值得到相同结果（R1.9 基础校验）。
test "eval is deterministic" {
  match check(parse_ok("let x = 4 in x * x - 1")) {
    Ok(t) => assert_true(eval(t) == eval(t))
    Err(_) => fail("check 意外失败")
  }
}

// ---------------------------------------------------------------------------
// 编译桩 compile（骨架级）
// ---------------------------------------------------------------------------

///|
/// compile 桩锁定签名并返回空产物（骨架级）。
test "compile stub returns empty bytes" {
  match check(Int(1)) {
    Ok(t) => assert_eq(compile(t, Wasm).length(), 0)
    Err(_) => fail("check 意外失败")
  }
}
