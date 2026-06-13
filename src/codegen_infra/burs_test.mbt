// burs_test.mbt —— 指令选择升级单元测试（任务 16.2）。
//
// 覆盖 BinOp:<op> 特化规则优先于通用 BinOp（同代价时，R11.3）、代价更低的通用
// 规则胜过更贵的特化规则（代价最优，R11.2），以及既有 `select` 后序序列冻结
// 回归（R11.4）。

///|
/// 同代价下运算符特化规则 `BinOp:*` 优先于通用 `BinOp`。
test "select_burs 同代价时特化规则优先" {
  let rules : Array[CostRule] = [
    { pattern: "Const", template: "li", cost: 1 },
    { pattern: "BinOp", template: "op", cost: 5 },
    { pattern: "BinOp:*", template: "mul", cost: 5 },
  ]
  let instrs = select_burs(rules, IrNode::BinOp("*", Const(3), Const(4)))
  inspect(instrs.length(), content="3")
  inspect(instrs[2].op, content="mul")
}

///|
/// 代价更低的通用规则胜过更贵的特化规则（代价最优优先于特化偏好）。
test "select_burs 代价更低的通用规则胜出" {
  let rules : Array[CostRule] = [
    { pattern: "Const", template: "li", cost: 1 },
    { pattern: "BinOp:+", template: "addslow", cost: 9 },
    { pattern: "BinOp", template: "add", cost: 2 },
  ]
  let instrs = select_burs(rules, IrNode::BinOp("+", Const(1), Const(2)))
  inspect(instrs[2].op, content="add")
  // 最优 tiling 总代价 = 1 + 1 + 2 = 4。
  inspect(tiling_cost(rules, IrNode::BinOp("+", Const(1), Const(2))), content="4")
}

///|
/// 既有 `select` 后序遍历序列冻结：li t0 1 / li t1 2 / add t2 t0 t1。
test "select 既有后序序列冻结回归" {
  let rules : Array[IselRule] = [
    { pattern: "Const", template: "li" },
    { pattern: "BinOp", template: "add" },
  ]
  let instrs = select(rules, IrNode::BinOp("+", Const(1), Const(2)))
  inspect(instrs.length(), content="3")
  inspect(instrs[0].op, content="li")
  inspect(instrs[1].op, content="li")
  inspect(instrs[2].op, content="add")
  inspect(instrs[2].operands[0], content="t2")
  inspect(instrs[2].operands[1], content="t0")
  inspect(instrs[2].operands[2], content="t1")
}
