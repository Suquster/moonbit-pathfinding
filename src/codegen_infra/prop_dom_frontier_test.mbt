// prop_dom_frontier_test.mbt —— Property 8：支配边界正确性（任务 2.4）。
//
// Feature: codegen-infra, Property 8: 支配边界正确性
// **Validates: Requirements 5.3**
//
// 性质：对任意带唯一入口的随机 CFG 与任意可达节点对 (d, n)，`n` 属于
// `dominance_frontier` 中 `d` 的支配边界，当且仅当 `d` 支配 `n` 的某个前驱
// 且 `d` 不严格支配 `n`。支配关系以独立参考实现 `reference_dominates` 判定。
// 复用 @infra_pbt.holds_for_all（100 次迭代）。

///|
/// Feature: codegen-infra, Property 8: 支配边界正确性
/// **Validates: Requirements 5.3**
test "Feature: codegen-infra, Property 8: dominance frontier correctness" {
  let ok = @infra_pbt.holds_for_all(
    gen_cfg(),
    fn(blocks) {
      let entry = "b0"
      let dom = build_dom_tree(blocks, entry~)
      let df = dominance_frontier(blocks, dom)
      let reach : Map[String, Bool] = Map([])
      for r in dom.reachable {
        reach[r] = true
      }
      for d in dom.reachable {
        let dfd = df.get(d).unwrap_or([])
        for n in dom.reachable {
          let is_member = t_contains_str(dfd, n)
          // 参考：∃ n 的可达前驱 p 使 d 支配 p；且 d 不严格支配 n。
          let mut dominates_some_pred = false
          for p in preds_of(blocks, n) {
            if reach.contains(p) && reference_dominates(blocks, entry, d, p) {
              dominates_some_pred = true
              break
            }
          }
          let strictly = reference_dominates(blocks, entry, d, n) && d != n
          let expected = dominates_some_pred && !(strictly)
          if is_member != expected {
            return false
          }
        }
      }
      true
    },
    iters=100,
  )
  assert_true(ok)
}
