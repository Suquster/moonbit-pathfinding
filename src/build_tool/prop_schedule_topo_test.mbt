// prop_schedule_topo_test.mbt —— Property 8：调度尊重依赖。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_dag；展平批次并校验每目标排在其全部
// 依赖之后（含不限并行度与受限并行度两种 jobs）。

///|
/// Feature: build-tool, Property 8: 调度尊重依赖
///
/// 对任意无环构建图，`schedule` 产出的批次序列展平后，每个目标都排在其全部
/// 依赖之后（拓扑不变量），且全部节点被调度。
///
/// **Validates: Requirements 7.1, 7.5**
test "Feature: build-tool, Property 8: schedule respects dependencies" {
  let ok = @infra_pbt.holds_for_all(gen_dag(), fn(g) {
    schedule_topo_holds(g, 0) && schedule_topo_holds(g, 2)
  })
  assert_true(ok)
}

///|
/// 某并行度下：全覆盖 + 每依赖边 `pos[u] < pos[v]`。
fn schedule_topo_holds(g : BuildGraph, jobs : Int) -> Bool {
  let batches = schedule(g, jobs)
  let pos = position_map(batches)
  if flatten_order(batches).length() != g.nodes.length() {
    return false
  }
  for edge in g.edges {
    let (u, v) = edge
    match (pos.get(u), pos.get(v)) {
      (Some(pu), Some(pv)) => if pu >= pv { return false }
      _ => return false
    }
  }
  true
}
