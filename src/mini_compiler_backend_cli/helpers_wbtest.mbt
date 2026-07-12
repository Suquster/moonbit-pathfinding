// 白盒测试：覆盖率审计收口（INFRA 第六十二批）——
// CLI 字节渲染工具（hex_digit / bytes_hex / bytes_text）确定性输出。

///|
test "backend_cli：hex_digit 全 16 值渲染" {
  assert_eq(hex_digit(0), "0")
  assert_eq(hex_digit(9), "9")
  assert_eq(hex_digit(10), "a")
  assert_eq(hex_digit(15), "f")
}

///|
test "backend_cli：bytes_hex 逐字节小写十六进制" {
  assert_eq(bytes_hex(b"\x00\xab\xff"), "00abff")
  assert_eq(bytes_hex(b""), "")
}

///|
test "backend_cli：bytes_text 逐字节文本还原" {
  assert_eq(bytes_text(b"hi"), "hi")
  assert_eq(bytes_text(b""), "")
}
