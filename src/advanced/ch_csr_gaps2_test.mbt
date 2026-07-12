// 黑盒测试：覆盖率审计收口（INFRA 第七十五批）——
// CH-CSR 查询端点越界拒绝。

///|
test "ch_csr_query_cost：端点越界返回 None" {
  guard @graph.synthetic_grid_csr(2, 2, 1.0) is Ok(g)
  let ch = @advanced.ch_csr_preprocess(g)
  assert_true(@advanced.ch_csr_query_cost(ch, -1, 0) is None)
  assert_true(@advanced.ch_csr_query_cost(ch, 0, 99) is None)
  assert_true(@advanced.ch_csr_query_cost(ch, 0, 3) is Some(_))
}
