// left_recursion_prop_test.mbt —— L1 直接左递归属性测试与边界单元测试
// （tasks 9.2, 9.3）。
//
// 实现 Property 25（左递归与 chainl1 差分一致）与左递归无基础情形的边界单元
// 测试（R9.4）。复用 derived_prop_test.mbt 中的 `dp_number` / `dp_sub_op` /
// `join_minus` / `gen_int_list`（同一黑盒测试包内共享）。

///|
/// 经 `left_recursive` 定义的直接左递归减法表达式：`expr := expr '-' num | num`
/// （左结合）。递归分支在前、基础分支在后，配合 seed-growing 收敛于最长左结合
/// 匹配。
fn lr_sub_expr() -> Grammar[Int] {
  let num_g = lift(dp_number())
  left_recursive("expr", fn(self) {
    choice([
      self.bind(fn(a) {
        lift(pchar('-')).bind(fn(_) { num_g.map(fn(b) { a - b }) })
      }),
      num_g,
    ])
  })
}

///|
/// Feature: parser-combinator, Property 25: 左递归与 chainl1 差分一致
///
/// 对任意左结合减法表达式输入，经 `left_recursive` 定义的直接左递归解析器与
/// `chainl1` 参照实现产生逐字段一致的求值结果（在有限步内收敛于最长匹配）。
///
/// **Validates: Requirements 9.1, 9.2, 9.3, 9.5**
test "Feature: parser-combinator, Property 25: left-recursion matches chainl1 reference" {
  let lr = lr_sub_expr()
  let cl = chainl1(dp_number(), dp_sub_op())
  let gen = @infra_pbt.Gen::new(fn(rng) { gen_int_list(rng, 1, 6, 20) })
  let ok = @infra_pbt.holds_for_all(gen, fn(xs) {
    let input = join_minus(xs)
    presult_eq(lr.run_packrat_string(input), cl.parse_string(input))
  })
  assert_true(ok)
}

///|
/// 左递归无基础情形：起始位置无可匹配操作数 → 返回携带起始位置与期望的失败，
/// 且不消费输入（R9.4）。
test "left_recursive fails at start without base case and consumes nothing" {
  let lr = lr_sub_expr()
  // "x"：无数字，基础情形在起点失败。
  match lr.run_packrat_string("x") {
    Fail(pos, expected~) => {
      @test.assert_eq(pos.offset, 0)
      assert_true(expected.length() > 0)
    }
    Ok(_, _) => fail("expected failure on non-operand input")
  }
  // 空输入：同样在起点失败。
  match lr.run_packrat_string("") {
    Fail(pos, ..) => @test.assert_eq(pos.offset, 0)
    Ok(_, _) => fail("expected failure on empty input")
  }
  // 单操作数：退化为基础情形，成功且消费该操作数。
  match lr.run_packrat_string("42") {
    Ok(v, rest) => {
      @test.assert_eq(v, 42)
      assert_true(rest.is_eof())
    }
    Fail(_, ..) => fail("expected single-operand success")
  }
}
