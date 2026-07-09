// proto_parser_gaps_test.mbt —— 骨架 proto 解析器（parse_proto）错误分支与
// 类型映射覆盖收口（INFRA 第十六批）：每个 Err 返回路径给出确定性反例见证。

///|
fn pp_err(src : String) -> Bool {
  parse_proto(src) is Err(_)
}

///|
fn pp_ok(src : String) -> Bool {
  parse_proto(src) is Ok(_)
}

///|
test "proto 顶层声明错误分支" {
  // 非标识符开头。
  assert_true(pp_err("123"))
  // message / enum 名缺失、'{' 缺失。
  assert_true(pp_err("message"))
  assert_true(pp_err("message M"))
  assert_true(pp_err("enum"))
  assert_true(pp_err("enum E"))
  // service：匿名块 / '{' 缺失 / 未闭合。
  assert_true(pp_ok("service { }"))
  assert_true(pp_err("service S ;"))
  assert_true(pp_err("service S {"))
  // 顶层语句缺 ';'。
  assert_true(pp_err("package a.b"))
  assert_true(pp_ok("syntax = \"proto3\";"))
}

///|
test "proto message 体错误分支与嵌套跳过" {
  // 块未闭合 / 空语句容忍。
  assert_true(pp_err("message M {"))
  assert_true(pp_ok("message M { ; }"))
  // 字段声明非标识符。
  assert_true(pp_err("message M { = 1; }"))
  // 嵌套类型：oneof/enum/message 骨架跳过；'{' 缺失 / 未闭合。
  assert_true(pp_ok("message M { message N { int32 a = 1; } }"))
  assert_true(pp_ok("message M { oneof o { int32 a = 1; } }"))
  assert_true(pp_err("message M { enum E ; }"))
  assert_true(pp_err("message M { message N { }"))
  // reserved / option / extensions 跳到 ';'；缺失 → 错误。
  assert_true(pp_ok("message M { reserved 1; option x = 1; extensions 2; }"))
  assert_true(pp_err("message M { reserved 1 }"))
  // repeated 后缺字段类型。
  assert_true(pp_err("message M { repeated ; }"))
  assert_true(pp_err("message M { repeated = 1; }"))
  // map 字段整条跳过；缺 ';' → 错误。
  assert_true(pp_ok("message M { map<string, int32> kv = 1; }"))
  assert_true(pp_err("message M { map<string, int32> kv = 1 }"))
  // 字段名 / '=' / 字段号 / 选项 ']' / ';' 缺失。
  assert_true(pp_err("message M { int32 = 1; }"))
  assert_true(pp_err("message M { int32 a 1; }"))
  assert_true(pp_err("message M { int32 a = ; }"))
  assert_true(pp_err("message M { int32 a = 1 [deprecated = true }"))
  assert_true(pp_err("message M { int32 a = 1 }"))
  assert_true(pp_ok("message M { int32 a = 1 [deprecated = true]; }"))
}

///|
test "proto enum 体错误分支" {
  assert_true(pp_err("enum E {"))
  assert_true(pp_ok("enum E { ; A = 0; }"))
  assert_true(pp_err("enum E { = 0; }"))
  assert_true(pp_ok("enum E { option allow_alias = true; A = 0; }"))
  assert_true(pp_err("enum E { option allow_alias = true }"))
  assert_true(pp_err("enum E { A 0; }"))
  assert_true(pp_err("enum E { A = x; }"))
  assert_true(pp_err("enum E { A = 0 }"))
}

///|
test "proto 标量类型映射与枚举引用重写" {
  let src =
    #|message M {
    #|  sint32 a = 1;
    #|  sfixed32 b = 2;
    #|  fixed32 c = 3;
    #|  sint64 d = 4;
    #|  sfixed64 e = 5;
    #|  fixed64 f = 6;
    #|  uint32 g = 7;
    #|  uint64 h = 8;
    #|  bool i = 9;
    #|  string j = 10;
    #|  bytes k = 11;
    #|  E ev = 12;
    #|  Other m = 13;
    #|  repeated int32 xs = 14;
    #|}
    #|enum E { A = 0; B = -1; }
  match parse_proto(src) {
    Ok(schema) => {
      assert_true(schema.messages.length() == 1)
      let fs = schema.messages[0].fields
      assert_true(fs[0].ftype == TInt32 && fs[1].ftype == TInt32)
      assert_true(fs[2].ftype == TInt32)
      assert_true(fs[3].ftype == TInt64 && fs[4].ftype == TInt64)
      assert_true(fs[5].ftype == TInt64)
      assert_true(fs[6].ftype == TUInt32 && fs[7].ftype == TUInt64)
      assert_true(fs[8].ftype == TBool && fs[9].ftype == TString)
      assert_true(fs[10].ftype == TBytes)
      assert_true(fs[11].ftype == TEnum("E"))
      assert_true(fs[12].ftype == TMessage("Other"))
      assert_true(fs[13].repeated)
      assert_true(schema.enums[0].values == [("A", 0), ("B", -1)])
    }
    Err(_) => assert_true(false)
  }
}
