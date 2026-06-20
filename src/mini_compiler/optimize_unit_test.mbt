// optimize_unit_test.mbt —— 优化管线单元测试（task 10.5，覆盖 R7.1 / R7.2 /
// R7.3）。
//
// 目的：以一组**固定**源串与确定的前后形态，逐字断言 optimize.mbt 的三类语义
// 保持变换 `const_fold` / `dead_let_elim` / `beta_reduce` 及组合 `optimize` 的
// 具体行为（design.md §11）。
//
//   1. const_fold（R7.1）：常量算术 / 比较 / 逻辑折叠、常量 `if` 分支选择、
//      除零=0；非常量子表达式原样保留。
//   2. dead_let_elim（R7.2）：绑定名在 body 中自由出现零次的 `let` 被消除；
//      仍被引用的 `let` 保留；嵌套 `let` 逐层判定。
//   3. beta_reduce（R7.3）：字面 lambda 应用的捕获避免替换；当实参自由变量与
//      内层绑定子同名时对绑定子做 alpha 重命名（fresh_name 以 `#` 计数），并
//      经 eval 等价校验语义保持。
//   4. optimize（R7.4 / R7.5）：`const_fold ∘ dead_let_elim` 组合。
//
// 构造 `Expr` 的方式：PARSE 源串（`lex_ml` + `parse_ml`），比手工构造 AST 更
// 简洁可靠。比较策略：对确定形态用 `print_expr` 字符串相等（完全括号化打印，
// 与运算符优先级无关地还原树形）；对 AST 相等用 `erase_span` + `==`；对捕获
// 避免的化简结果额外以 `infer → eval_ml` 校验语义保持。期望值据 optimize.mbt
// （已验证真值来源）的实际输出对齐。本文件为旁路新增黑盒 `_test.mbt`，不修改
// 任何既有源文件。

///|
/// 词法 + 语法分析源串为 `Expr`；任何前置失败均中止（这些样例均为合法源串）。
fn op_parse(src : String) -> Expr {
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
/// 推断并求值源串对应的 `Expr`（用于 beta 捕获用例的语义保持校验）；失败中止。
fn op_eval(e : Expr) -> Val {
  match infer(e) {
    Ok((te, _)) => eval_ml(te)
    Err(d) => abort("infer 意外失败：\{d.msg}")
  }
}

// ---------------------------------------------------------------------------
// 1. const_fold（R7.1）
// ---------------------------------------------------------------------------

///|
/// 常量算术折叠：`1 + 2 * 3` → `1 + (2 * 3)` → `1 + 6` → `7`（自底向上）。
test "const_fold: arithmetic folds to single literal '7'" {
  assert_eq(print_expr(erase_span(const_fold(op_parse("1 + 2 * 3")))), "7")
}

///|
/// 常量比较 + 逻辑折叠：`(1 < 2) && (3 > 4)` → `true && false` → `false`。
test "const_fold: comparison and logic fold to 'false'" {
  assert_eq(
    print_expr(erase_span(const_fold(op_parse("(1 < 2) && (3 > 4)")))),
    "false",
  )
}

///|
/// 常量 `if` 条件做分支选择：`if 1 < 2 then 10 else 20` → cond 折叠为 true →
/// 选取 then 分支 `10`。
test "const_fold: constant if-condition selects then-branch" {
  assert_eq(
    print_expr(erase_span(const_fold(op_parse("if 1 < 2 then 10 else 20")))),
    "10",
  )
}

///|
/// 除零定义为 0（与 ml_eval.mbt 一致）：`10 / 0` → `0`。
test "const_fold: division by zero folds to '0'" {
  assert_eq(print_expr(erase_span(const_fold(op_parse("10 / 0")))), "0")
}

///|
/// 非常量子表达式原样保留：`x + 1`（x 自由）不可折叠，仍为 `(x + 1)`。
test "const_fold: non-constant expression is preserved" {
  assert_eq(print_expr(erase_span(const_fold(op_parse("x + 1")))), "(x + 1)")
}

// ---------------------------------------------------------------------------
// 2. dead_let_elim（R7.2）
// ---------------------------------------------------------------------------

///|
/// 死 `let` 消除：`let x = 5 in 42`，x 在 body 中自由出现零次 → 整个 `let` 由
/// body `42` 取代。
test "dead_let_elim: removes unused let binding" {
  assert_eq(
    print_expr(erase_span(dead_let_elim(op_parse("let x = 5 in 42")))),
    "42",
  )
}

///|
/// 活 `let` 保留：`let x = 5 in x + 1`，x 被引用 → `let` 原样保留。
test "dead_let_elim: keeps used let binding" {
  assert_eq(
    print_expr(erase_span(dead_let_elim(op_parse("let x = 5 in x + 1")))),
    "(let x = 5 in (x + 1))",
  )
}

///|
/// 嵌套逐层判定：`let x = 1 in let y = 2 in x`，内层 `y` 未被使用被消除，外层
/// `x` 被使用保留 → `(let x = 1 in x)`。
test "dead_let_elim: nested elimination removes inner unused binding" {
  assert_eq(
    print_expr(
      erase_span(dead_let_elim(op_parse("let x = 1 in let y = 2 in x"))),
    ),
    "(let x = 1 in x)",
  )
}

// ---------------------------------------------------------------------------
// 3. beta_reduce（R7.3 / R7.6）
// ---------------------------------------------------------------------------

///|
/// 基本 beta 化简：`(fun x -> x + 1) 41` → `41 + 1`（替换 x ↦ 41）。
test "beta_reduce: substitutes argument into lambda body" {
  assert_eq(
    print_expr(erase_span(beta_reduce(op_parse("(fun x -> x + 1) 41")))),
    "(41 + 1)",
  )
}

///|
/// 捕获避免（结构）：`let y = 7 in (fun x -> (fun y -> x + y)) y`。实参 `y`（指
/// 外层 let 绑定）替换入内层 `fun y -> x + y` 时，内层绑定子 `y` 与实参自由变量
/// `y` 同名，必须 alpha 重命名为新鲜名（fresh_name 方案以 `#0` 计数），避免捕获
/// 外层 `y`。结果内层形参重命名为 `y#0`，外层 `y` 仍自由引用 let 绑定。
test "beta_reduce: capture-avoiding rename of inner binder" {
  assert_eq(
    print_expr(
      erase_span(
        beta_reduce(op_parse("let y = 7 in (fun x -> (fun y -> x + y)) y")),
      ),
    ),
    "(let y = 7 in (fun y#0 -> (y + y#0)))",
  )
}

///|
/// 捕获避免（语义保持）：在可完全归约为整数的同构用例上，校验 beta_reduce 前后
/// eval 结果一致。`let y = 7 in ((fun x -> fun y -> x + y) y) 5`：x ↦ 7（外层 y），
/// 内层 y ↦ 5，得 `7 + 5 = 12`；beta_reduce 后化简为 `let y = 7 in y + 5`，
/// 同样求值为 12（外层 `y` 未被内层绑定子捕获）。
test "beta_reduce: capture-avoidance preserves evaluation result" {
  let src = "let y = 7 in ((fun x -> fun y -> x + y) y) 5"
  let original = op_eval(op_parse(src))
  let reduced = op_eval(beta_reduce(op_parse(src)))
  assert_true(original == reduced)
  assert_true(original == VInt(12))
}

// ---------------------------------------------------------------------------
// 4. optimize 组合（R7.4 / R7.5）
// ---------------------------------------------------------------------------

///|
/// 组合管线 `const_fold ∘ dead_let_elim`：`let x = 5 in 1 + 2 * 3`，先死 `let`
/// 消除（x 未使用）得 `1 + 2 * 3`，再常量折叠为 `7`。
test "optimize: dead-let elimination then constant folding yields '7'" {
  assert_eq(
    print_expr(erase_span(optimize(op_parse("let x = 5 in 1 + 2 * 3")))),
    "7",
  )
}
