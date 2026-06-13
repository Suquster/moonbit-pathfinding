// prop_ssa_phi_arity_test.mbt —— Property 10：φ 结构良构（任务 5.4）。
//
// Feature: codegen-infra, Property 10: φ 实参个数等于其汇合块前驱个数
// **Validates: Requirements 6.2**
//
// 性质：对任意带唯一入口的随机 CFG，`build_ssa_minimal` 产出的每个 φ 的实参
// 个数等于其所在汇合块的前驱个数。复用 holds_for_all（100 迭代）。

///|
/// Feature: codegen-infra, Property 10: φ 实参个数等于其汇合块前驱个数
/// **Validates: Requirements 6.2**
test "Feature: codegen-infra, Property 10: phi arity equals predecessor count" {
  let ok = @infra_pbt.holds_for_all(
    gen_cfg(),
    fn(blocks) {
      let ssa = build_ssa_minimal(blocks, entry="b0")
      let sites = t_phi_sites(ssa)
      for i in 0..<ssa.phis.length() {
        let (block, _) = sites[i]
        if block == "" {
          continue
        }
        if ssa.phis[i].args.length() != preds_of(blocks, block).length() {
          return false
        }
      }
      true
    },
    iters=100,
  )
  assert_true(ok)
}
