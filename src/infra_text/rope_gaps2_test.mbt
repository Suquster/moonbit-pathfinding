// 黑盒测试：覆盖率审计收口（INFRA 第七十七批）——
// 空串构建与孤立高代理项的 UTF-8 长度按 3 字节计。

///|
test "Rope：空串构建与孤立高代理项 UTF-8 计长" {
  let empty = @infra_text.Rope::from_string("")
  assert_eq(empty.len(), 0)
  assert_eq(empty.utf8_len(), 0)
  // 高代理项后跟非低代理项：按 3 字节（替换语义）计。
  let sb = StringBuilder::new()
  sb.write_char((0xD800).unsafe_to_char())
  sb.write_char('a')
  let r = @infra_text.Rope::from_string(sb.to_string())
  assert_eq(r.utf8_len(), 4)
}
