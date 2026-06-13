// prop_dom_tree_test.mbt —— Property 7：支配树正确性（任务 2.3）。
//
// Feature: codegen-infra, Property 7: 支配树正确性
// **Validates: Requirements 5.1, 5.2, 5.5**
//
// 性质：对任意带唯一入口的随机 CFG，`build_dom_tree` 使每个可达非入口节点恰有
// 一个直接支配者；且由 idom 父链推出的支配关系（DomTree::dominates）与参考定义
// 「入口到该节点的所有路径均经过支配者」一致。参考实现 `reference_dominates`
// 以「移除候选支配者后入口是否仍能到达目标」独立判定，避免重用被测逻辑。
// 复用 @infra_pbt.holds_for_all（100 次迭代）。

///|
/// Feature: codegen-infra, Property 7: 支配树正确性
/// **Validates: Requirements 5.1, 5.2, 5.5**
test "Feature: codegen-infra, Property 7: dominator tree correctness" {
  let ok = @infra_pbt.holds_for_all(
    gen_cfg(),
    fn(blocks) {
      let entry = "b0"
      let dom = build_dom_tree(blocks, entry~)
      // 1) 每个可达非入口节点恰有一个 idom（在 idom 键集中，且入口不在）。
      for lbl in dom.reachable {
        if lbl == entry {
          if dom.idom.get(lbl) is Some(_) {
            return false
          }
        } else if dom.idom.get(lbl) is None {
          return false
        }
      }
      // 2) 支配关系与参考定义对所有可达节点对一致。
      for d in dom.reachable {
        for n in dom.reachable {
          let by_tree = dom.dominates(d, n)
          let by_ref = reference_dominates(blocks, entry, d, n)
          if by_tree != by_ref {
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
