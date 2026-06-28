// arith_prop_test.mbt —— L2 算术求值器属性测试与黄金样例单元测试
// （tasks 13.2, 13.3）。
//
// 实现 Property 31（算术求值一致性）与优先级 / 结合性黄金样例。

// ---------------------------------------------------------------------------
// 表达式 AST 生成器（gen_expr）
// ---------------------------------------------------------------------------

///|
/// 深度受限的 `Expr` 生成器：数值叶子限定为小非负整数；除法分母取非零字面量
/// 以规避除零（杜绝 0/0 产生 NaN）；幂指数取小非负整数以保证可精确求值。
fn gen_expr_at(rng : @infra_pbt.Rng, depth : Int) -> Expr {
  if depth <= 0 || rng.next_below(2) == 0 {
    Num(rng.next_range(0, 12).to_double())
  } else {
    match rng.next_below(5) {
      0 => Add(gen_expr_at(rng, depth - 1), gen_expr_at(rng, depth - 1))
      1 => Sub(gen_expr_at(rng, depth - 1), gen_expr_at(rng, depth - 1))
      2 => Mul(gen_expr_at(rng, depth - 1), gen_expr_at(rng, depth - 1))
      3 =>
        // 除法：分母取非零字面量，避免除零 / NaN。
        Div(gen_expr_at(rng, depth - 1), Num(rng.next_range(1, 12).to_double()))
      _ =>
        // 幂：小非负整数指数。
        Pow(gen_expr_at(rng, depth - 1), Num(rng.next_range(0, 3).to_double()))
    }
  }
}

///|
/// `gen_expr`：深度 4 的合法算术 AST 生成器。
fn gen_expr() -> @infra_pbt.Gen[Expr] {
  @infra_pbt.Gen::new(fn(rng) { gen_expr_at(rng, 4) })
}

// ---------------------------------------------------------------------------
// Property 31：算术求值一致性
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 31: 算术求值一致性
///
/// 对任意合法算术表达式 AST `x`，对其完全括号化打印形式求值
/// `parse_and_eval(print_expr(x))` 得到与按 AST 直接求值 `eval_expr(x)` 一致的
/// 数值结果。完全括号化使解析无歧义地恢复同一结构，故两侧执行相同的浮点运算
/// 序列，结果逐位一致。
///
/// **Validates: Requirements 11.5, 11.6, 11.8**
test "Feature: parser-combinator, Property 31: arithmetic evaluation consistency" {
  let ok = @infra_pbt.holds_for_all(gen_expr(), fn(x) {
    match parse_and_eval(print_expr(x)) {
      Ok(v) => v == eval_expr(x)
      Err(_) => false
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// 黄金样例（task 13.3）：优先级与左 / 右结合（R11.6）
// ---------------------------------------------------------------------------

///|
/// 优先级与结合性的代表性样例：左结合减法、右结合幂、乘高于加。
test "arithmetic precedence and associativity golden cases" {
  // 左结合：8-3-2 == (8-3)-2 == 3。
  assert_true(parse_and_eval("8-3-2") == Ok(3.0))
  // 右结合幂：2^3^2 == 2^(3^2) == 2^9 == 512。
  assert_true(parse_and_eval("2^3^2") == Ok(512.0))
  // 乘高于加：2+3*4 == 2+12 == 14。
  assert_true(parse_and_eval("2+3*4") == Ok(14.0))
  // 括号改变优先级：(2+3)*4 == 20。
  assert_true(parse_and_eval("(2+3)*4") == Ok(20.0))
  // 除法左结合：100/5/2 == (100/5)/2 == 10。
  assert_true(parse_and_eval("100/5/2") == Ok(10.0))
  // 综合：1+2*3^2 == 1+2*9 == 19。
  assert_true(parse_and_eval("1+2*3^2") == Ok(19.0))
}

///|
/// 语法错误返回 Err（尾随未消费 / 缺失操作数）。
test "arithmetic reports errors on malformed input" {
  assert_true(parse_and_eval("1+") is Err(_))
  assert_true(parse_and_eval("(1+2") is Err(_))
  assert_true(parse_and_eval("1 2") is Err(_)) // 尾随未消费
}
