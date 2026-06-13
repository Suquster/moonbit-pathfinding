// demo_test.mbt —— 端到端示例单元测试（任务 17.2）。
//
// 断言：仅在支配边界放 φ 且 φ 数符合声明（R12.2/12.3）、`k` 充足时着色无溢出
// 且满足干涉不变量（R12.4）、同一无溢出场景图着色与线性扫描溢出结论一致
// （R12.5），以及指令选择各阶段产物与声明快照一致。

///|
/// demo 各阶段产物与声明一致。
test "demo_pipeline 各阶段产物符合声明" {
  let stages = demo_pipeline()
  // 支配树：入口 entry，四个块全可达。
  inspect(stages.dom.root, content="entry")
  inspect(stages.dom.reachable.length(), content="4")
  // 最小 SSA：x 在 then/else 定义 → join 处恰一个 φ，实参数 = 2（汇合块前驱数）。
  inspect(stages.ssa.phis.length(), content="1")
  inspect(stages.ssa.phis[0].args.length(), content="2")
  // k 充足：图着色无溢出且尊重干涉。
  assert_false(allocation_has_spill(stages.coloring))
  let g = build_interference_from_liveness(demo_program(), stages.liveness)
  assert_true(t_coloring_respects(g, stages.coloring))
  // 同一无溢出场景：图着色与线性扫描溢出结论一致（均无需溢出）。
  assert_false(allocation_has_spill(stages.linear_scan))
  // 指令选择：(n + 1) * 2 共 5 个 IR 节点 → 5 条指令；`*` 用特化 mul。
  inspect(stages.instrs.length(), content="5")
  inspect(stages.instrs[4].op, content="mul")
}
