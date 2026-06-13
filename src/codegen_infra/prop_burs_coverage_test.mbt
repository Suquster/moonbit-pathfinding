// prop_burs_coverage_test.mbt —— Property 16：指令选择覆盖完整（任务 16.3）。
//
// Feature: codegen-infra, Property 16: 指令选择覆盖完整
// **Validates: Requirements 11.1, 11.5**
//
// 性质：对任意随机 IR 树与覆盖完整的带代价规则集，`select_burs` 所选指令序列
// 覆盖每个 IR 节点、无未匹配。由于规则集恒含 `Const`/`VarRef`/`BinOp` 通用规则，
// 每个节点恰发射一条指令，故发射指令数等于 IR 节点数即证覆盖完整。
// 复用 @infra_pbt.holds_for_all（100 次迭代）。

///|
/// Feature: codegen-infra, Property 16: 指令选择覆盖完整
/// **Validates: Requirements 11.1, 11.5**
test "Feature: codegen-infra, Property 16: instruction selection covers every node" {
  let ok = @infra_pbt.holds_for_all(
    gen_ir_and_rules(3),
    fn(pair) {
      let (ir, rules) = pair
      let instrs = select_burs(rules, ir)
      instrs.length() == count_ir_nodes(ir)
    },
    iters=100,
  )
  assert_true(ok)
}
