// proto_grammar_gaps_test.mbt —— proto 全文法解析 EOF/嵌套错误传播收口
// （INFRA 第三十二批）。

///|
test "parse_proto_full：EOF 处标识符与期望标识符缺失" {
  // 输入在标识符处截断（EOF 终止 ident 扫描）。
  assert_true(@serialization.parse_proto_full("syntax") is Err(_))
  // repeated 后 EOF：期望字段类型报错。
  assert_true(@serialization.parse_proto_full("message M { repeated") is Err(_))
}

///|
test "parse_proto_full：嵌套 message 解析错误向上传播" {
  let src = "message Outer { message Inner { int32 x = ; } }"
  assert_true(@serialization.parse_proto_full(src) is Err(_))
}
