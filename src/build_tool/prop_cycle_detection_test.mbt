// prop_cycle_detection_test.mbt —— Property 13：环检测可靠性。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_graph_with_cycle_flag（携带「是否含
// 环」真值），校验 detect_cycle 与 topo_order 的判定与事实及彼此等价。

///|
/// Feature: build-tool, Property 13: 环检测可靠性
///
/// 对任意构建图，`detect_cycle` 返回 `Some` 当且仅当该图含依赖环；等价地，
/// `topo_order` 返回 `Err(Cycle)` 当且仅当 `detect_cycle` 返回 `Some`。
///
/// **Validates: Requirements 8.3, 13.2, 13.3**
test "Feature: build-tool, Property 13: cycle-detection reliability" {
  let ok = @infra_pbt.holds_for_all(gen_graph_with_cycle_flag(), fn(pair) {
    let (g, has_cycle) = pair
    let detected = match detect_cycle(g) {
      Some(_) => true
      None => false
    }
    let topo_err = match topo_order(g) {
      Ok(_) => false
      Err(_) => true
    }
    detected == has_cycle && topo_err == has_cycle && detected == topo_err
  })
  assert_true(ok)
}
