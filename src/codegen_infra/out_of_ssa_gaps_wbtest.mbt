// out_of_ssa_gaps_wbtest.mbt —— SSA 解构辅助操作边角收口
// （INFRA 第二十六批）。

///|
test "is_terminator：空指令判非终结" {
  assert_false(is_terminator(""))
  assert_false(is_terminator("   "))
}

///|
test "insert_before_terminator：空插入与无终结指令块" {
  let instrs = ["x = 1", "y = 2"]
  // 空 extra：原样返回。
  assert_eq(insert_before_terminator(instrs, []).length(), 2)
  // 末指令非终结：追加到尾部。
  let out = insert_before_terminator(instrs, ["c = x"])
  assert_eq(out.length(), 3)
  assert_eq(out[2], "c = x")
  // 末指令为终结：插到终结前。
  let out2 = insert_before_terminator(["x = 1", "br L1"], ["c = x"])
  assert_eq(out2.length(), 3)
  assert_eq(out2[1], "c = x")
  assert_eq(out2[2], "br L1")
}

///|
test "build_ssa_minimal：不可达块跳过版本分配" {
  let blocks : Array[BasicBlock] = [
    { label: "entry", instrs: ["x = 1"], succs: [] },
    { label: "dead", instrs: ["y = 2"], succs: ["entry"] },
  ]
  let p = build_ssa_minimal(blocks, entry="entry")
  assert_true(p.blocks.length() >= 1)
  assert_eq(p.phis.length(), 0)
}
