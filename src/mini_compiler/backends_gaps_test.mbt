// 黑盒测试：覆盖率审计收口（INFRA 第六十九批）——
// JS/WAT 全链编译入口、负整数与 TyVar 形状渲染、TCO 元组构造、
// 元组作用域检查与跳转链穿透。

///|
test "compile_ml_to_js：全链编译成功与词法错误传播" {
  assert_true(@mini_compiler.compile_ml_to_js("let x = 1 in x + 2") is Ok(_))
  assert_true(@mini_compiler.compile_ml_to_js("let x =") is Err(_))
}

///|
test "compile_ml_to_wat：全链编译成功与语法错误传播" {
  assert_true(
    @mini_compiler.compile_ml_to_wat("if true then 1 else 2") is Ok(_),
  )
  assert_true(@mini_compiler.compile_ml_to_wat("f (") is Err(_))
}

///|
test "emit_js_expr：负整数字面量加括号" {
  let z = @mini_compiler.Span::{ line: 0, col: 0 }
  let e = @mini_compiler.TEInt(-3, @mini_compiler.TyInt, z)
  assert_eq(@mini_compiler.emit_js_expr(e), "(-3)")
}

///|
test "ty_shape：TyVar 渲染为函数形状" {
  assert_eq(@mini_compiler.ty_shape(@mini_compiler.TyVar(0)), "\"fun\"")
}

///|
test "emit_js/emit_wat：Lambda 与 let/乘法渲染" {
  let z = @mini_compiler.Span::{ line: 0, col: 0 }
  let lam = @mini_compiler.TELam(
    "x",
    @mini_compiler.TEVar("x", @mini_compiler.TyInt, z),
    @mini_compiler.TyFun(@mini_compiler.TyInt, @mini_compiler.TyInt),
    z,
  )
  assert_true(@mini_compiler.emit_js(lam).contains("=>"))
  let letx = @mini_compiler.TELet(
    "x",
    @mini_compiler.TEArith(
      @mini_compiler.Mul,
      @mini_compiler.TEInt(2, @mini_compiler.TyInt, z),
      @mini_compiler.TEInt(3, @mini_compiler.TyInt, z),
      @mini_compiler.TyInt,
      z,
    ),
    @mini_compiler.TEVar("x", @mini_compiler.TyInt, z),
    @mini_compiler.TyInt,
    z,
  )
  assert_true(@mini_compiler.emit_wat(letx).contains("i32.mul"))
}

///|
test "run_tco：MkTuple 构造元组值" {
  let bc = @mini_compiler.Bytecode::{
    instrs: [
      @mini_compiler.PushInt(1),
      @mini_compiler.PushInt(2),
      @mini_compiler.MkTuple(2),
      @mini_compiler.Ret,
    ],
  }
  assert_true(
    @mini_compiler.run_tco(bc, @mini_compiler.ml_env_empty()) ==
    @mini_compiler.VTuple([@mini_compiler.VInt(1), @mini_compiler.VInt(2)]),
  )
}

///|
test "scope_check_ml：元组元素逐一作用域检查" {
  guard @mini_compiler.lex_ml("(1, y)") is Ok(toks)
  guard @mini_compiler.parse_ml(toks) is Ok(e)
  assert_true(@mini_compiler.scope_check_ml(e) is Err(_))
  guard @mini_compiler.lex_ml("(1, 2)") is Ok(toks2)
  guard @mini_compiler.parse_ml(toks2) is Ok(e2)
  assert_true(@mini_compiler.scope_check_ml(e2) is Ok(_))
}
