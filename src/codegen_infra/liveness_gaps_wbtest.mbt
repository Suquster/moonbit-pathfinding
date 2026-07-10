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
test "analyze_liveness：悬空后继标签在不动点中安全忽略" {
  let blocks : Array[BasicBlock] = [
    { label: "b0", instrs: ["x = 1", "y = x + 1"], succs: ["b1", "ghost"] },
    { label: "b1", instrs: ["z = y + x"], succs: ["ghost"] },
  ]
  let live = analyze_liveness(blocks)
  match live.live_out.get("b1") {
    Some(vs) => assert_eq(vs.length(), 0)
    None => assert_true(false)
  }
  match live.live_in.get("b1") {
    Some(vs) => assert_true(vs.length() > 0)
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

///|
test "build_interference_from_liveness：live 结果标签/变量不匹配时安全忽略" {
  let blocks : Array[BasicBlock] = [
    { label: "b0", instrs: ["x = 1", "y = x + 1", "z = y + w"], succs: [] },
  ]
  // 以另一组块的活跃性结果调用：live_out 缺 b0（415），且其中
  // 指令引用的变量在 name2id 中可解析，而空 live 不影响防御路径。
  let alien : Array[BasicBlock] = [
    { label: "other", instrs: ["q = 1"], succs: [] },
  ]
  let live = analyze_liveness(alien)
  let g = build_interference_from_liveness(blocks, live)
  assert_true(g.nodes.length() > 0)
}

///|
test "build_interference_from_liveness：指令含未登记变量名安全忽略" {
  // blocks2 的 name2id 仅含本组变量；live 携带的标签匹配但指令中
  // 的 use/def 在跨组调用下无法映射时走 None 分支。
  let src : Array[BasicBlock] = [{ label: "b0", instrs: ["x = 1"], succs: [] }]
  let live = analyze_liveness(src)
  let other : Array[BasicBlock] = [
    { label: "b0", instrs: ["x = 1", "x = x + 1"], succs: [] },
  ]
  let g = build_interference_from_liveness(other, live)
  assert_eq(g.nodes.length(), 1)
}

///|
test "build_intervals_from_liveness：空指令块占位一个序号槽" {
  let blocks : Array[BasicBlock] = [
    { label: "b0", instrs: [], succs: ["b1"] },
    { label: "b1", instrs: ["x = 1", "y = x"], succs: [] },
  ]
  let live = analyze_liveness(blocks)
  let ivs = build_intervals_from_liveness(blocks, live)
  assert_true(ivs.length() > 0)
  // 空块占号：b1 指令自序号 1 起。
  for iv in ivs {
    assert_true(iv.start >= 1)
  }
}
