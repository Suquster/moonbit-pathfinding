// liveness_gaps_wbtest.mbt —— 活跃性分析内部防御分支收口
// （INFRA 第二十三批）：空记号、未登记变量、悬空后继、集合比较。

///|
test "is_var_token：空记号非变量" {
  assert_false(is_var_token(""))
  assert_true(is_var_token("x"))
  assert_false(is_var_token("42"))
  assert_false(is_var_token("+"))
}

///|
test "block_use_def：未登记变量名安全忽略" {
  let block : BasicBlock = { label: "b0", instrs: ["x = y + 1"], succs: [] }
  // 空 name2id：use 与 def 均无法映射 → 两集皆空。
  let (use_set, def_set) = block_use_def(block, Map([]))
  assert_eq(use_set.length(), 0)
  assert_eq(def_set.length(), 0)
}

///|
test "liveness_step：悬空后继标签安全忽略" {
  let blocks : Array[BasicBlock] = [
    { label: "b0", instrs: ["x = 1"], succs: ["ghost"] },
  ]
  let live = liveness_step(blocks, { live_in: Map([]), live_out: Map([]) })
  match live.live_out.get("b0") {
    Some(vs) => assert_eq(vs.length(), 0)
    None => assert_true(false)
  }
}

///|
test "int_set_equal：同长异键判不等" {
  let a : Map[Int, Bool] = Map([])
  a[1] = true
  let b : Map[Int, Bool] = Map([])
  b[2] = true
  assert_false(int_set_equal(a, b))
  assert_true(int_set_equal(a, a))
}
