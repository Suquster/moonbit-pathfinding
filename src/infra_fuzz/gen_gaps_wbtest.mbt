// 白盒测试：覆盖率审计收口（INFRA 第七十二批）——
// 整数辅助余臂与自环图生成器的退化容量路径。

///|
test "imax/clamp_int：两侧余臂" {
  assert_eq(imax(5, 3), 5)
  assert_eq(imax(3, 5), 5)
  assert_eq(clamp_int(-1, 0, 10), 0)
  assert_eq(clamp_int(99, 0, 10), 10)
  assert_eq(clamp_int(5, 0, 10), 5)
}
