// prop_ssa_phi_frontier_test.mbt —— Property 9：φ 仅放在支配边界（任务 5.3）。
//
// Feature: codegen-infra, Property 9: φ 仅放在支配边界
// **Validates: Requirements 6.1, 6.5**
//
// 性质：对任意带唯一入口的随机 CFG，`build_ssa_minimal` 产出的每个 φ 所在块都
// 属于其对应变量定义块集合的（迭代）支配边界。参考实现以 `dominance_frontier`
// 输出独立计算迭代支配边界（`t_iterated_df`）。复用 holds_for_all（100 迭代）。

///|
/// Feature: codegen-infra, Property 9: φ 仅放在支配边界
/// **Validates: Requirements 6.1, 6.5**
test "Feature: codegen-infra, Property 9: phi placed only on dominance frontier" {
  let ok = @infra_pbt.holds_for_all(
    gen_cfg(),
    fn(blocks) {
      let entry = "b0"
      let ssa = build_ssa_minimal(blocks, entry~)
      let dom = build_dom_tree(blocks, entry~)
      let df = dominance_frontier(blocks, dom)
      let reach : Map[String, Bool] = Map([])
      for r in dom.reachable {
        reach[r] = true
      }
      let defb = t_def_blocks(blocks, reach)
      let sites = t_phi_sites(ssa)
      for site in sites {
        let (block, def_var) = site
        if block == "" {
          continue // 无法定位的死 φ：跳过
        }
        let idf = t_iterated_df(df, defb.get(def_var).unwrap_or([]))
        if !(idf.contains(block)) {
          return false
        }
      }
      true
    },
    iters=100,
  )
  assert_true(ok)
}
