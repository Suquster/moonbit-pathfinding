// prop_backend_test.mbt —— T1.1/T1.2 真产物后端的仓内验证。
//
// 端到端的**真实执行**差分（node 跑 JS 产物、wat2wasm+V8 跑 wasm 产物、与
// `eval_ml` 逐字符对拍）由 `scripts/verify_backends.sh` 承载（外部工具链，
// 无法在 moon test 内调用）；本文件承载仓内可回归的三层保证：
//   1. 黄金见证：语义编码关键构造（32 位环绕 `|0` / `Math.imul` / `__div`、
//      闭包 lambda 提升 + `$apply`、递归 `isrec` 标记）在产物中的确切形态；
//   2. 属性（≥100 迭代）：对随机良类型程序，两个发射器均为全函数且产物
//      非空、wat 模块结构良构（括号配平）；
//   3. 发射确定性：同一程序两次发射逐字符一致。

///|
/// 端到端便捷解析：源码 → 良类型 `TExpr`（测试用，失败即 abort）。
fn be_typed(src : String) -> TExpr {
  match lex_ml(src) {
    Err(_) => abort("lex error: " + src)
    Ok(toks) =>
      match parse_ml(toks) {
        Err(_) => abort("parse error: " + src)
        Ok(e) =>
          match infer(e) {
            Err(_) => abort("infer error: " + src)
            Ok((te, _)) => te
          }
      }
  }
}

///|
/// 括号是否配平且深度恒非负（wat S-表达式良构的必要条件）。
fn be_parens_balanced(s : String) -> Bool {
  let mut depth = 0
  for c in s.iter() {
    if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      depth = depth - 1
      if depth < 0 {
        return false
      }
    }
  }
  depth == 0
}

///|
test "Feature: mini-compiler, Golden: JS backend encodes wrap-around and div semantics" {
  // 加/减经 `|0` 收窄、乘用 Math.imul、除走 __div（除零=0、INT_MIN/-1 环绕）。
  let te = be_typed("1 + 2 * 3 - 4 / 5")
  let js = emit_js_expr(te)
  assert_eq(js, "((((1 + Math.imul(2, 3)) | 0) - __div(4, 5)) | 0)")
}

///|
test "Feature: mini-compiler, Golden: JS backend lowers let/lam/letrec faithfully" {
  assert_eq(
    emit_js_expr(be_typed("let x = 5 in x + 1")),
    "((v_x) => ((v_x + 1) | 0))(5)",
  )
  assert_eq(
    emit_js_expr(be_typed("(fun x -> x * 2) 21")),
    "(((v_x) => Math.imul(v_x, 2)))(21)",
  )
  assert_eq(
    emit_js_expr(
      be_typed(
        "let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f 5",
      ),
    ),
    "(() => { const v_f = ((v_n) => ((v_n <= 1) ? 1 : Math.imul(v_n, (v_f)(((v_n - 1) | 0))))); return (v_f)(5); })()",
  )
}

///|
test "Feature: mini-compiler, Golden: wasm backend lifts lambdas and marks recursion" {
  // 递归闭包以 isrec=1 构造（$apply 调用时把自身 cons 进环境）。
  let wat = emit_wat_module(
    be_typed("let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f 5"),
  )
  assert_true(
    wat.contains("(call $mkclosure (i32.const 0) (i32.const 0) (i32.const 1))"),
  )
  assert_true(
    wat.contains("(func $l0 (type $fn) (param $env i32) (result i32)"),
  )
  assert_true(wat.contains("(elem (i32.const 0) $l0)"))
  // 非递归 lambda 以 isrec=0 构造。
  let wat2 = emit_wat_module(be_typed("(fun x -> x + 1) 41"))
  assert_true(wat2.contains("(i32.const 0))"))
  assert_true(wat2.contains("(call $apply "))
}

///|
test "Feature: mini-compiler, Golden: ty_shape renders result shapes for the wasm host" {
  assert_eq(ty_shape(TyInt), "\"int\"")
  assert_eq(ty_shape(TyBool), "\"bool\"")
  assert_eq(ty_shape(TyFun(TyInt, TyInt)), "\"fun\"")
  assert_eq(
    ty_shape(TyTuple([TyInt, TyBool, TyTuple([TyInt, TyInt])])),
    "[\"tuple\", \"int\", \"bool\", [\"tuple\", \"int\", \"int\"]]",
  )
}

///|
test "Feature: mini-compiler, Property: both backends total and well-formed on random well-typed programs" {
  let ok = @infra_pbt.holds_for_all(ml_well_typed_expr_gen(), fn(e) {
    match infer(e) {
      Err(_) => false
      Ok((te, ty)) => {
        let js = emit_js_program(te)
        let wat = emit_wat_module(te)
        js.length() > 0 &&
        wat.length() > 0 &&
        be_parens_balanced(wat) &&
        wat.contains("(export \"main\")") &&
        ty_shape(ty).length() > 0
      }
    }
  })
  assert_true(ok)
}

///|
test "Feature: mini-compiler, Property: emission is deterministic" {
  let ok = @infra_pbt.holds_for_all(ml_well_typed_expr_gen(), fn(e) {
    match infer(e) {
      Err(_) => false
      Ok((te, _)) =>
        emit_js_program(te) == emit_js_program(te) &&
        emit_wat_module(te) == emit_wat_module(te)
    }
  })
  assert_true(ok)
}

///|
test "Feature: mini-compiler, Regression: INT_MIN / -1 wraps instead of trapping across eval/optimize/vm" {
  // 修复见证：此前 `ml_apply_arith` 直接 `a / b`，INT_MIN / -1 在
  // native/wasm 后端触发「divide result unrepresentable」陷阱，违反
  // 求值全函数契约（R5.8）。现定义为环绕（0 - a）。
  let te = be_typed("(0 - 2147483647 - 1) / (0 - 1)")
  assert_true(eval_ml(te) == VInt(-2147483648))
  // 解释器 / 编译-VM 双路径一致。
  let r1 = run_interp("(0 - 2147483647 - 1) / (0 - 1)")
  let r2 = run_compiled("(0 - 2147483647 - 1) / (0 - 1)")
  assert_true(r1 == r2)
  assert_true(r1 is Produced(VInt(-2147483648)))
}
