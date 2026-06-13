// prop_ssa_single_assign_wbtest.mbt —— Property 11：SSA 单赋值不变量（任务 5.5）。
//
// Feature: codegen-infra, Property 11: SSA 单赋值不变量
// **Validates: Requirements 6.6**
//
// 性质：对任意带唯一入口的随机 CFG，`build_ssa_minimal` 的结果满足单赋值
// 不变量——每个版本化变量在全程序至多被定义一次。白盒测试经包内私有 `version_id`
// 抽取定义版本号（复用同包白盒辅助 `ssa_definition_ids` / `all_distinct`，见
// codegen_infra_wbtest.mbt）。复用 holds_for_all（100 迭代）。

///|
/// Feature: codegen-infra, Property 11: SSA 单赋值不变量
/// **Validates: Requirements 6.6**
test "Feature: codegen-infra, Property 11: SSA single-assignment invariant" {
  let ok = @infra_pbt.holds_for_all(
    gen_cfg_wb(),
    fn(blocks) {
      let ssa = build_ssa_minimal(blocks, entry="b0")
      all_distinct(ssa_definition_ids(ssa))
    },
    iters=100,
  )
  assert_true(ok)
}
