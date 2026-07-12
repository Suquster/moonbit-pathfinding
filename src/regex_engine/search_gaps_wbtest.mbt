// 白盒测试：覆盖率审计收口（INFRA 第六十六批）——
// 切片辅助的越界钳制余臂。

///|
test "slice_chars：负下界与超上界钳制" {
  assert_eq(slice_chars(['a', 'b', 'c'], -2, 99), "abc")
  assert_eq(slice_chars(['a', 'b', 'c'], 1, 2), "b")
  assert_eq(slice_chars(['a', 'b', 'c'], 2, 1), "")
}
