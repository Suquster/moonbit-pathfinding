// prop_dynamic_topo_test.mbt —— Property 14：动态依赖拓扑保持。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_dag_dynamic（DAG + 目标 + 不引入环的
// 动态依赖）。校验并入后仍无环，且 reschedule_with_dynamic 满足拓扑不变量。

///|
/// Feature: build-tool, Property 14: 动态依赖拓扑保持
///
/// 对任意无环构建图与不引入环的动态依赖追加，并入后的图仍无环，且
/// `reschedule_with_dynamic` 重新产出的调度仍满足拓扑不变量（每目标在其全部
/// 依赖之后），并覆盖全部节点。
///
/// **Validates: Requirements 8.1, 8.2, 8.4**
test "Feature: build-tool, Property 14: dynamic-dependency topology preservation" {
  let ok = @infra_pbt.holds_for_all(gen_dag_dynamic(), fn(triple) {
    let (g, target, dyn_deps) = triple
    let g2 = add_dynamic_deps(g, target, dyn_deps)
    // 并入后仍无环。
    let acyclic = match detect_cycle(g2) {
      Some(_) => false
      None => true
    }
    if !acyclic {
      return false
    }
    match reschedule_with_dynamic(g, target, dyn_deps, 0) {
      Err(_) => false
      Ok(batches) => {
        let pos = position_map(batches)
        if flatten_order(batches).length() != g2.nodes.length() {
          return false
        }
        for edge in g2.edges {
          let (u, v) = edge
          match (pos.get(u), pos.get(v)) {
            (Some(pu), Some(pv)) => if pu >= pv { return false }
            _ => return false
          }
        }
        true
      }
    }
  })
  assert_true(ok)
}
