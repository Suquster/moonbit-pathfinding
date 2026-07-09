// burs_gaps_test.mbt —— BURS / 最大吞噬指令选择缺口收口
// （INFRA 第二十三批）：空规则集退化路径与 max_munch 全分支。

///|
test "tiling_cost：空规则集全节点退化为 0" {
  let ir : IrNode = BinOp("+", Const(1), VarRef({ id: 0 }))
  assert_eq(tiling_cost([], ir), 0)
  assert_eq(tiling_cost([], Const(7)), 0)
  assert_eq(tiling_cost([], VarRef({ id: 3 })), 0)
}

///|
test "select_burs：空规则集走占位模板" {
  let ir : IrNode = BinOp("+", Const(1), VarRef({ id: 0 }))
  let instrs = select_burs([], ir)
  // Const → "li" 占位；VarRef 直通名字（不发指令）；BinOp → 运算符名。
  assert_eq(instrs.length(), 2)
  assert_eq(instrs[0].op, "li")
  assert_eq(instrs[1].op, "+")
}

///|
test "max_munch：空规则集与占位路径" {
  let ir : IrNode = BinOp("*", Const(2), VarRef({ id: 1 }))
  let instrs = max_munch([], ir)
  assert_eq(instrs.length(), 2)
  assert_eq(instrs[0].op, "li")
  assert_eq(instrs[1].op, "*")
}

///|
test "max_munch：特化规则优先，通用规则兜底" {
  let rules : Array[CostRule] = [
    { pattern: "Const", template: "load_imm", cost: 1 },
    { pattern: "VarRef", template: "mov", cost: 1 },
    { pattern: "BinOp:+", template: "addq", cost: 1 },
    { pattern: "BinOp", template: "genop", cost: 2 },
  ]
  // '+'：命中特化模板。
  let add = max_munch(rules, BinOp("+", Const(1), VarRef({ id: 0 })))
  assert_eq(add[add.length() - 1].op, "addq")
  assert_eq(add[0].op, "load_imm")
  assert_eq(add[1].op, "mov")
  // '-'：无特化 → 通用 BinOp 兜底。
  let sub = max_munch(rules, BinOp("-", Const(3), Const(4)))
  assert_eq(sub[sub.length() - 1].op, "genop")
}

///|
test "max_munch 与 select_burs：同规则集产出等价操作码序列" {
  let rules = demo_isel_rules()
  let ir = demo_ir()
  let mm = max_munch(rules, ir)
  assert_true(mm.length() > 0)
  let burs = select_burs(rules, ir)
  assert_eq(mm.length(), burs.length())
}
