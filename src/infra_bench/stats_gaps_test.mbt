// 黑盒测试：覆盖率审计收口（INFRA 第七十七批）——
// 空样本统计拒绝。

///|
test "compute_stats：空样本返回 InvalidArgument" {
  let empty : Array[Double] = []
  assert_true(@infra_bench.compute_stats(empty) is Err(_))
}
