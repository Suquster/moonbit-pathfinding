// 黑盒测试：覆盖率审计收口（INFRA 第七十七批）——
// 顶层非标识符拒绝与匿名嵌套类型的块体配平。

///|
test "parse_proto：顶层非标识符 token 报语法错误" {
  assert_true(@serialization.parse_proto("123") is Err(_))
}

///|
test "parse_proto：匿名嵌套类型块体照常配平跳过" {
  let src = "message M { message { int32 a = 1; } int32 b = 2; }"
  guard @serialization.parse_proto(src) is Ok(s)
  assert_eq(s.messages.length(), 1)
  assert_eq(s.messages[0].name, "M")
}

///|
test "parse_proto：嵌套块体未闭合报错" {
  let src = "message M { message N { int32 a = 1; "
  assert_true(@serialization.parse_proto(src) is Err(_))
}
