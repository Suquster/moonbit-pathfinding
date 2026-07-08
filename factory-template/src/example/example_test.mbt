// example_test.mbt —— 黑盒测试示例：定值见证 + 边界 + 简易属性遍历。

///|
test "isqrt：定值见证与边界" {
  assert_true(@example.isqrt(0) == Some(0))
  assert_true(@example.isqrt(1) == Some(1))
  assert_true(@example.isqrt(15) == Some(3))
  assert_true(@example.isqrt(16) == Some(4))
  assert_true(@example.isqrt(-1) is None)
}

///|
test "isqrt：属性——x*x ≤ n < (x+1)*(x+1)（0..500 全量遍历）" {
  for n in 0..<500 {
    match @example.isqrt(n) {
      Some(x) => assert_true(x * x <= n && (x + 1) * (x + 1) > n)
      None => assert_true(false)
    }
  }
}
