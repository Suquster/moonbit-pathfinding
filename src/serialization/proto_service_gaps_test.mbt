// proto_service_gaps_test.mbt —— proto service/rpc/import 解析错误分支覆盖收口
// （INFRA 第十九批）：rpc 各段截断、service 成员拒绝、import 修饰与路径、
// 块体跳过路径的确定性见证。

///|
fn psg_err(src : String) -> Bool {
  parse_proto_file("syntax = \"proto3\";\n" + src) is Err(_)
}

///|
fn psg_ok(src : String) -> Bool {
  parse_proto_file("syntax = \"proto3\";\n" + src) is Ok(_)
}

///|
test "proto rpc 各段截断与关键字拒绝" {
  assert_true(psg_err("service S { rpc }"))
  assert_true(psg_err("service S { rpc M }"))
  assert_true(psg_err("service S { rpc M ( }"))
  assert_true(psg_err("service S { rpc M (A }"))
  assert_true(psg_err("service S { rpc M (A) }"))
  assert_true(psg_err("service S { rpc M (A) return (B); }"))
  assert_true(psg_err("service S { rpc M (A) returns }"))
  assert_true(psg_err("service S { rpc M (A) returns (B }"))
  assert_true(psg_err("service S { rpc M (A) returns (B) }"))
  assert_true(psg_err("service S { rpc M (A) returns (B) x }"))
  // 方法体块 `{ ... }` 与流式前缀。
  assert_true(psg_ok("service S { rpc M (stream A) returns (stream B); }"))
  assert_true(psg_ok("service S { rpc M (A) returns (B) { option x = 1; } }"))
}

///|
test "proto service 成员与结构拒绝" {
  assert_true(psg_err("service"))
  assert_true(psg_err("service S"))
  assert_true(psg_err("service S {"))
  assert_true(psg_err("service S { message M {} }"))
  assert_true(psg_err("service S { % }"))
  // 空语句 ';' 与 option 成员被接受。
  assert_true(psg_ok("service S { ; option deprecated = true; }"))
  assert_true(psg_err("service S { option deprecated = true }"))
}

///|
test "proto import 修饰与路径拒绝" {
  assert_true(psg_ok("import \"a.proto\";"))
  assert_true(psg_ok("import public \"a.proto\";"))
  assert_true(psg_ok("import weak \"a.proto\";"))
  assert_true(psg_err("import a.proto;"))
  assert_true(psg_err("import \"a.proto\""))
  assert_true(psg_err("import public;"))
  // import 修饰符标志正确传递。
  match
    parse_proto_file(
      "syntax = \"proto3\";\nimport public \"x.proto\";\nimport \"y.proto\";",
    ) {
    Ok(f) => {
      assert_true(f.imports.length() == 2)
      assert_true(f.imports[0].public)
      assert_true(f.imports[1].public == false)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "parse_proto_file：方法选项块未闭合拒绝" {
  let src = "syntax = \"proto3\";\n" +
    "service S {\n" +
    "  rpc M(A) returns (B) {\n"
  assert_true(parse_proto_file(src) is Err(_))
}

///|
test "parse_proto_file：方法选项块整体跳过" {
  let src = "syntax = \"proto3\";\n" +
    "service S {\n" +
    "  rpc M(A) returns (B) { option idempotency_level = IDEMPOTENT; }\n" +
    "}\n"
  match parse_proto_file(src) {
    Ok(f) => assert_eq(f.services.length(), 1)
    Err(_) => assert_true(false)
  }
}
