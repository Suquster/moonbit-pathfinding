// 黑盒测试：proofs 未覆盖分支（流/割验证器负例、MST/连通分量后置条件负例、
// ProofReport JSON 解析器数字/字符串边界）。

///|
test "max_flow_valid：形态与约束负例逐分支拒绝" {
  let es : Array[(Int, Int)] = [(0, 1)]
  // 数组长度不齐。
  assert_false(max_flow_valid(2, es, [1, 2], [1], 0, 1, 1))
  // 节点数非正。
  assert_false(max_flow_valid(0, [], [], [], 0, 1, 1))
  // 源/汇越界。
  assert_false(max_flow_valid(2, es, [1], [1], 5, 1, 1))
  // 源 == 汇。
  assert_false(max_flow_valid(2, es, [1], [1], 0, 0, 1))
  // 超容量。
  assert_false(max_flow_valid(2, es, [1], [2], 0, 1, 2))
  // 边端点越界。
  assert_false(max_flow_valid(2, [(0, 9)], [1], [1], 0, 1, 1))
  // 流不守恒（中间节点净流量非零）。
  assert_false(max_flow_valid(3, [(0, 1)], [1], [1], 0, 2, 0))
  // 合法正例。
  assert_true(max_flow_valid(2, es, [1], [1], 0, 1, 1))
}

///|
test "max_flow_equals_min_cut：割形态负例逐分支拒绝" {
  let es : Array[(Int, Int)] = [(0, 1)]
  assert_false(max_flow_equals_min_cut(2, es, [1, 2], [true, false], 0, 1, 1))
  assert_false(max_flow_equals_min_cut(2, es, [1], [true], 0, 1, 1))
  assert_false(max_flow_equals_min_cut(2, es, [1], [true, false], 5, 1, 1))
  assert_false(max_flow_equals_min_cut(2, es, [1], [false, true], 0, 1, 1))
  assert_false(
    max_flow_equals_min_cut(2, [(0, 9)], [1], [true, false], 0, 1, 1),
  )
  assert_true(max_flow_equals_min_cut(2, es, [1], [true, false], 0, 1, 1))
}

///|
test "mst_post / mst_weight_le_post / components_partition_post：负例分支" {
  // n < 0 / n == 0。
  assert_false(mst_post(-1, []))
  assert_true(mst_post(0, []))
  // 端点越界。
  assert_false(mst_post(2, [(0, 9, 1)]))
  // 有环（重复合并同一连通对）。
  assert_false(mst_post(3, [(0, 1, 1), (1, 0, 1)]))
  // 权重上界传播（内部先走 mst_post 失败分支）。
  assert_false(mst_weight_le_post(2, [], 10))
  assert_true(mst_weight_le_post(2, [(0, 1, 3)], 3))
  assert_false(mst_weight_le_post(2, [(0, 1, 5)], 3))
  // 分量划分：n<0 与标签长度不齐。
  assert_false(components_partition_post(-1, [], []))
  assert_false(components_partition_post(2, [0], []))
}

///|
test "proof_report JSON：小数/指数符号/转义边界解析" {
  // from_json 走 PJParser：带小数、指数符号、\/ 转义与残缺小数。
  let ok = "{\"entries\":[{\"direction\":\"a\\/b\",\"property\":\"p\",\"passed\":true,\"detail\":\"x\",\"iterations\":1.5e+2}],\"generated_at\":\"t\"}"
  // 数字字段类型按实现宽容或拒绝均可，只要不崩溃；解析器覆盖 . 与 e+ 分支。
  let _ = parse_proof_report(ok)
  // 残缺小数（点后无数字）→ 解析失败。
  let bad = "{\"entries\":[],\"generated_at\":1.}"
  assert_true(parse_proof_report(bad) is None)
  // 反斜杠悬挂在串尾 → 解析失败。
  let bad2 = "{\"entries\":[],\"generated_at\":\"x\\"
  assert_true(parse_proof_report(bad2) is None)
}
