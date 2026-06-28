// proto_grammar_test.mbt —— 完整 proto3 文法解析单元测试（任务 3.2）。
//
// 覆盖 oneof / map / 嵌套 message-enum / reserved / 字段选项的具体样例，以及语法
// 错误的行列定位（R3.2–3.7）。

///|
/// 在富消息中按字段号查找字段。
fn tg_field(m : ProtoMessage, number : Int) -> ProtoField? {
  for f in m.fields {
    if f.number == number {
      return Some(f)
    }
  }
  None
}

///|
/// 解析含 oneof / map / 嵌套类型 / reserved / 字段选项的完整 proto3 源码。
test "parse_proto_full handles oneof, map, nested, reserved, options" {
  let src =
    #|syntax = "proto3";
    #|package demo;
    #|enum Color { COLOR_NONE = 0; RED = 1; }
    #|message Outer {
    #|  reserved 2, 9 to 11;
    #|  reserved "old";
    #|  int32 id = 1;
    #|  repeated int64 nums = 3 [packed = false];
    #|  Color color = 4;
    #|  oneof choice {
    #|    string s = 5;
    #|    int32 n = 6;
    #|  }
    #|  map<string, int32> meta = 7;
    #|  message Inner {
    #|    bool flag = 1;
    #|  }
    #|}
  let schema = match parse_proto_full(src) {
    Ok(s) => s
    Err(e) => {
      fail("合法 .proto 不应解析失败：\{e}")
      return
    }
  }
  // 顶层 + 嵌套消息均以限定名登记。
  let outer = match schema.message("Outer") {
    Some(m) => m
    None => {
      fail("应登记消息 Outer")
      return
    }
  }
  assert_true(schema.message("Outer.Inner") is Some(_))
  assert_true(outer.nested_messages == ["Outer.Inner"])
  // 标量与枚举引用解析。
  assert_true(tg_field(outer, 1).unwrap().ptype == PInt32)
  assert_true(tg_field(outer, 4).unwrap().ptype == PEnum("Color"))
  // repeated + packed=false 选项。
  match tg_field(outer, 3).unwrap().label {
    LRepeated(packed~) => assert_false(packed)
    _ => fail("字段 3 应为 repeated")
  }
  // oneof 成员归组。
  @test.assert_eq(outer.oneofs.length(), 1)
  @test.assert_eq(outer.oneofs[0].name, "choice")
  assert_true(outer.oneofs[0].members == [5, 6])
  match tg_field(outer, 5).unwrap().label {
    LOneof(group~) => @test.assert_eq(group, "choice")
    _ => fail("字段 5 应属 oneof")
  }
  // map 字段。
  @test.assert_eq(outer.maps.length(), 1)
  @test.assert_eq(outer.maps[0].name, "meta")
  @test.assert_eq(outer.maps[0].number, 7)
  assert_true(outer.maps[0].key == PString)
  assert_true(outer.maps[0].value == PInt32)
  // reserved 号区间与名。
  assert_true(outer.reserved_numbers == [{ lo: 2, hi: 2 }, { lo: 9, hi: 11 }])
  assert_true(outer.reserved_names == ["old"])
}

///|
/// 语法错误返回携带行列位置的 ParseError 且不构造 Schema。
test "parse_proto_full reports error with line and column on syntax error" {
  // 字段缺少字段号。
  let src =
    #|message M {
    #|  int32 x = ;
    #|}
  match parse_proto_full(src) {
    Ok(_) => fail("非法 .proto 不应解析成功")
    Err(e) => {
      // 错误定位在第 2 行（含字段号缺失处）。
      @test.assert_eq(e.line, 2)
      assert_true(e.col >= 1)
    }
  }
}

///|
/// 解析空白与注释，顶层语句被跳过。
test "parse_proto_full skips comments and top-level statements" {
  let src =
    #|// 行注释
    #|syntax = "proto3";
    #|/* 块注释 */
    #|message M {
    #|  string name = 1; // 尾随注释
    #|}
  match parse_proto_full(src) {
    Ok(s) => {
      @test.assert_eq(s.messages.length(), 1)
      @test.assert_eq(s.messages[0].name, "M")
    }
    Err(e) => fail("含注释的合法 .proto 不应失败：\{e}")
  }
}
