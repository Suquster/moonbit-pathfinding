// proto_grammar_errors_test.mbt —— proto 全文法解析器错误分支覆盖收口
// （INFRA 第十六批）。moon coverage analyze 显示 parse_proto_full 及其
// 子解析器的大量错误传播 / 结构破坏分支未被触达；解析器的健壮性要求每个
// Err 分支都有确定性反例。逐分支补齐畸形 .proto 文本锚点。

///|
/// 便捷断言：解析必须失败。
fn pg_must_err(src : String) -> Bool {
  parse_proto_full(src) is Err(_)
}

///|
/// 便捷断言：解析必须成功。
fn pg_must_ok(src : String) -> Bool {
  parse_proto_full(src) is Ok(_)
}

///|
test "top level statements and service blocks" {
  // service 块：合法（跳过整块）。
  assert_true(pg_must_ok("service S { rpc F (A) returns (B); }"))
  // service 名后缺 '{'。
  assert_true(pg_must_err("service S ;"))
  // service 块未闭合。
  assert_true(pg_must_err("service S {"))
  // 顶层语句缺结尾 ';'。
  assert_true(pg_must_err("package a.b"))
  // 顶层非标识符。
  assert_true(pg_must_err("123"))
}

///|
test "field option list structural breakage" {
  // 选项列表中既非 ',' 也非 ']' ⇒ 报错。
  assert_true(
    pg_must_err("message M { int32 a = 1 [deprecated=true deprecated=false]; }"),
  )
  // 合法多选项（',' 分支）。
  assert_true(
    pg_must_ok("message M { int32 a = 1 [deprecated=true, packed=false]; }"),
  )
  // 选项取值为带符号裸记号与字符串字面量。
  assert_true(pg_must_ok("message M { int32 a = 1 [default=-5]; }"))
  assert_true(pg_must_ok("message M { int32 a = 1 [default=\"x y\"]; }"))
  // 选项取值缺失 ⇒ 报错。
  assert_true(pg_must_err("message M { int32 a = 1 [default=]; }"))
  // 字符串字面量未闭合 ⇒ 报错。
  assert_true(pg_must_err("message M { int32 a = 1 [default=\"x]; }"))
}

///|
test "enum block error branches" {
  // enum 名缺失。
  assert_true(pg_must_err("enum { A = 0; }"))
  // enum 名后缺 '{'。
  assert_true(pg_must_err("enum E ;"))
  // enum 块未闭合。
  assert_true(pg_must_err("enum E { A = 0;"))
  // 多余 ';' 直接跳过（Some(';') 分支）。
  assert_true(pg_must_ok("enum E { ; A = 0; }"))
  // enum 内 option / reserved 声明跳过；缺结尾 ';' 报错。
  assert_true(pg_must_ok("enum E { option allow_alias = true; A = 0; }"))
  assert_true(pg_must_err("enum E { option allow_alias = true"))
  // 枚举值缺 '='、缺数字、缺 ';'。
  assert_true(pg_must_err("enum E { A 0; }"))
  assert_true(pg_must_err("enum E { A = x; }"))
  assert_true(pg_must_err("enum E { A = 0 }"))
}

///|
test "reserved numbers and names error branches" {
  // 数字列表：',' 连接、'to' 区间、结构破坏。
  assert_true(pg_must_ok("message M { reserved 1, 2, 5 to 8; }"))
  assert_true(pg_must_err("message M { reserved 1 2; }"))
  assert_true(pg_must_err("message M { reserved 1 to; }"))
  assert_true(pg_must_err("message M { reserved x; }"))
  // 名字列表：',' 连接与结构破坏。
  assert_true(pg_must_ok("message M { reserved \"a\", \"b\"; }"))
  assert_true(pg_must_err("message M { reserved \"a\" \"b\"; }"))
  assert_true(pg_must_err("message M { reserved \"a\", 1; }"))
}

///|
test "message block error branches" {
  // message 名缺失 / 缺 '{' / 未闭合。
  assert_true(pg_must_err("message { }"))
  assert_true(pg_must_err("message M ;"))
  assert_true(pg_must_err("message M {"))
  // 多余 ';' 跳过。
  assert_true(pg_must_ok("message M { ; }"))
  // 嵌套 message / enum 及其错误传播。
  assert_true(
    pg_must_ok("message M { message N { int32 a = 1; } enum E { A = 0; } }"),
  )
  assert_true(pg_must_err("message M { message N { int32 a = 1; }"))
  assert_true(pg_must_err("message M { enum E { A = 0 } }"))
  // message 内 option 声明跳过与缺 ';' 报错。
  assert_true(pg_must_ok("message M { option deprecated = true; }"))
  assert_true(pg_must_err("message M { option deprecated = true"))
  // oneof 错误传播。
  assert_true(pg_must_err("message M { oneof { int32 a = 1; } }"))
}

///|
test "oneof block error branches" {
  // 合法 oneof（含多余 ';'）。
  assert_true(
    pg_must_ok("message M { oneof o { ; int32 a = 1; string b = 2; } }"),
  )
  // oneof 名后缺 '{' / 未闭合。
  assert_true(pg_must_err("message M { oneof o ; }"))
  assert_true(pg_must_err("message M { oneof o { int32 a = 1;"))
  // 成员字段缺 '=' / 缺编号 / 缺 ';'。
  assert_true(pg_must_err("message M { oneof o { int32 a 1; } }"))
  assert_true(pg_must_err("message M { oneof o { int32 a = x; } }"))
  assert_true(pg_must_err("message M { oneof o { int32 a = 1 } }"))
  // 成员带选项列表。
  assert_true(
    pg_must_ok("message M { oneof o { int32 a = 1 [deprecated=true]; } }"),
  )
}

///|
test "map fields and regular field error branches" {
  // map 字段：合法（消息值类型走 PMessage 分支）。
  assert_true(
    pg_must_ok("message M { map<string, N> m = 1; message N { int32 a = 1; } }"),
  )
  assert_true(pg_must_ok("message M { map<int32, string> m = 1; }"))
  // map 结构破坏：缺 '<' / 缺 ',' / 缺 '>' / 缺名字 / 缺 '=' / 缺 ';'。
  assert_true(pg_must_err("message M { map string, int32> m = 1; }"))
  assert_true(pg_must_err("message M { map<string int32> m = 1; }"))
  assert_true(pg_must_err("message M { map<string, int32 m = 1; }"))
  assert_true(pg_must_err("message M { map<string, int32> = 1; }"))
  assert_true(pg_must_err("message M { map<string, int32> m 1; }"))
  assert_true(pg_must_err("message M { map<string, int32> m = 1 }"))
  // 普通字段：缺编号 / 缺 ';' / 带 repeated 与选项。
  assert_true(pg_must_err("message M { int32 a = ; }"))
  assert_true(pg_must_err("message M { int32 a = 1"))
  assert_true(pg_must_ok("message M { repeated int32 a = 1 [packed=true]; }"))
}

///|
test "remaining error propagation branches" {
  // 枚举值处非标识符（pg_expect_ident 失败）。
  assert_true(pg_must_err("enum E { = 0; }"))
  // 枚举值选项列表结构破坏（pg_parse_field_options 错误传播）。
  assert_true(pg_must_err("enum E { A = 0 [deprecated=true; }"))
  // message 成员处非标识符。
  assert_true(pg_must_err("message M { = 1; }"))
  // 嵌套 enum 解析错误传播。
  assert_true(pg_must_err("message M { enum E { A = ; } }"))
  // oneof 成员：类型处非标识符 / 字段名处非标识符 / 选项列表破坏。
  assert_true(pg_must_err("message M { oneof o { = 1; } }"))
  assert_true(pg_must_err("message M { oneof o { int32 = 1; } }"))
  assert_true(pg_must_err("message M { oneof o { int32 a = 1 [x=; } }"))
  // map：键类型非标识符 / 值类型非标识符 / 字段名非标识符 / 字段号缺失 /
  // 选项列表破坏 / 消息键类型（PMessage 键分支）。
  assert_true(pg_must_err("message M { map<, int32> m = 1; }"))
  assert_true(pg_must_err("message M { map<string, > m = 1; }"))
  assert_true(pg_must_err("message M { map<string, int32> = 1; }"))
  assert_true(pg_must_err("message M { map<string, int32> m = ; }"))
  assert_true(pg_must_err("message M { map<string, int32> m = 1 [x=; }"))
  assert_true(pg_must_ok("message M { map<K, int32> m = 1; message K { } }"))
  // 普通字段：字段名非标识符 / '=' 缺失。
  assert_true(pg_must_err("message M { int32 = 1; }"))
  assert_true(pg_must_err("message M { int32 a 1; }"))
  // service 名缺失（匿名 service 也可跳过块）。
  assert_true(pg_must_ok("service { }"))
}

///|
test "print proto covers message-typed fields and options" {
  // print_proto：消息类型字段（PMessage 简名分支）与字段选项串接分支。
  let src = "message N { int32 x = 1; } " +
    "message M { N n = 1 [deprecated=true]; map<string, N> m = 2; }"
  match parse_proto_full(src) {
    Ok(schema) => {
      let printed = print_proto(schema)
      assert_true(printed.contains("N n = 1"))
      assert_true(printed.contains("deprecated=true"))
    }
    Err(_) => assert_true(false)
  }
}
