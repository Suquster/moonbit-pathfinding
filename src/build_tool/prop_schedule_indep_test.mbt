// prop_schedule_indep_test.mbt —— Property 9：批内独立。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_dag；校验同批任意两目标间无依赖边
// （等价于每依赖边两端落在不同批次）。

///|
/// Feature: build-tool, Property 9: 批内独立
///
/// 对任意无环构建图，`schedule` 产出的同一并行批次内任意两个目标之间不存在
/// 依赖边。
///
/// **Validates: Requirements 7.6**
test "Feature: build-tool, Property 9: intra-batch independence" {
  let ok = @infra_pbt.holds_for_all(gen_dag(), fn(g) {
    indep_holds(g, 0) && indep_holds(g, 3)
  })
  assert_true(ok)
}

///|
/// 某并行度下：每条依赖边两端不在同一批次。
fn indep_holds(g : BuildGraph, jobs : Int) -> Bool {
  let batches = schedule(g, jobs)
  let bi = batch_index_map(batches)
  for edge in g.edges {
    let (u, v) = edge
    match (bi.get(u), bi.get(v)) {
      (Some(bu), Some(bv)) => if bu == bv { return false }
      _ => return false
    }
  }
  true
}
