// 白盒测试：覆盖率审计收口（INFRA 第七十六批）——
// semantics 作用域错误传播与 LEB128 多字节编码、peephole 跳转链/自环
// 折叠与空程序、optimize 替换遮蔽/新名生成、match_ext EApp span 与
// 自由变量求值兜底、exhaustive 非 Int 头证据与完整签名有用性。

///|
test "check：Bin 左子/Let body 的自由变量错误传播" {
  assert_true(check(Bin(Add, Var("x"), Int(1))) is Err(_))
  assert_true(check(Let("a", Int(1), Bin(Add, Var("a"), Var("y")))) is Err(_))
}

///|
test "push_uleb/push_sleb_i32：多字节续标志" {
  let u : Array[Byte] = []
  push_uleb(u, 300)
  assert_eq(u.length(), 2)
  assert_true((u[0].to_int() & 0x80) != 0)
  let s : Array[Byte] = []
  push_sleb_i32(s, -300)
  assert_eq(s.length(), 2)
  assert_true((s[0].to_int() & 0x80) != 0)
}

///|
test "resolve_jump_target：跳转链折叠与自环保持" {
  let chain : Array[Instr] = [Jump(1), Jump(2), PushInt(7)]
  assert_eq(resolve_jump_target(chain, 0), 2)
  let selfloop : Array[Instr] = [Jump(0)]
  assert_eq(resolve_jump_target(selfloop, 0), 0)
}

///|
test "remove_unreachable：空指令序列原样返回" {
  let empty : Array[Instr] = []
  assert_eq(remove_unreachable(empty).length(), 0)
}

///|
test "occurs_free：ELetRec 非同名递归穿透" {
  let z = Span::{ line: 0, col: 0 }
  let e = ELetRec("f", EVar("x", z), EVar("f", z), z)
  assert_true(occurs_free("x", e))
  assert_false(occurs_free("x", ELetRec("x", EVar("x", z), EInt(1, z), z)))
}

///|
test "fresh_name：候选冲突时递增序号" {
  assert_eq(fresh_name("x", fn(n) { n == "x#0" }), "x#1")
}

///|
test "subst_expr：ELam 同名遮蔽与 ELet 无捕获直替" {
  let z = Span::{ line: 0, col: 0 }
  let lam = ELam("x", EVar("x", z), z)
  assert_true(subst_expr("x", EInt(1, z), lam) == lam)
  let letx = ELet("y", EInt(2, z), EVar("x", z), z)
  assert_true(
    subst_expr("x", EInt(1, z), letx) == ELet("y", EInt(2, z), EInt(1, z), z),
  )
}

///|
test "expr_span：EApp 余臂" {
  let z = Span::{ line: 0, col: 0 }
  let sp = Span::{ line: 4, col: 2 }
  assert_true(expr_span(EApp(EVar("f", z), EInt(1, z), sp)) == sp)
}

///|
test "eval_base：自由变量经闭式求值兜底" {
  let env : Map[String, ValX] = Map([])
  assert_true(
    eval_base(EVar("free", Span::{ line: 0, col: 0 }), env) is VXInt(_),
  )
  let z = Span::{ line: 0, col: 0 }
  let e = EIf(EBool(true, z), EVar("q", z), EInt(1, z), z)
  assert_true(eval_base(e, env) is VXInt(_))
}

///|
test "check_exhaustive：函数类型头证据与元组尾证据" {
  // TXFun 无构造器签名 → 头证据为通配。
  let none_pats : Array[Pattern] = []
  assert_true(check_exhaustive(none_pats, TXFun(TXInt, TXInt)) is Some(PWild))
  // 元组首列 Int 不完整 → 头为新鲜整数，尾证据随行拼接。
  let pats = [PTuple([PInt(1), PBool(true)])]
  assert_true(check_exhaustive(pats, TXTuple([TXInt, TXBool])) is Some(_))
}

///|
test "redundant_arms：完整签名下深列可用性判定" {
  let pats = [
    PTuple([PBool(true), PBool(true)]),
    PTuple([PBool(false), PBool(true)]),
    PTuple([PWild, PBool(false)]),
  ]
  assert_eq(redundant_arms(pats, TXTuple([TXBool, TXBool])).length(), 0)
}
