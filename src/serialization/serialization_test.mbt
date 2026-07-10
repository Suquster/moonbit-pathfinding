// serialization_test.mbt —— Serialization_Framework 骨架（任务 7.1）的单元测试。
//
// 覆盖：
//   1. wire 类型编码 code / from_code 的自洽；
//   2. encode / decode 在通用字段记录上的往返（编码再解码得到等价消息）；
//   3. **解码错误契约（Requirement 9.4）**：非法字节返回含出错字节偏移的
//      DecodeError，且失败时不产生部分构造的对象（结果为 Err，不存在 Message）；
//   4. parse_proto 解析消息/字段/枚举的模式描述（Requirement 9.5），含枚举引用
//      解析后处理；解析错误返回含行列位置的 ParseError（Requirement 9.6）；
//   5. gen_moonbit 由模式生成 MoonBit 类型骨架代码。
//
// 编解码往返性质（Property 20）与非法字节错误条件（Property 21）的属性测试由
// 后续任务 7.3 / 7.4 单独承载；本文件仅以确定性夹具校验桩行为与错误契约。

// ───────────────────────────── wire 类型 ─────────────────────────────────

///|
/// WireType 的数值编码与还原一一对应，非法取值（6/7）返回 None。
test "wire type code and from_code roundtrip" {
  @test.assert_eq(WireType::Varint.code(), 0)
  @test.assert_eq(WireType::I64.code(), 1)
  @test.assert_eq(WireType::Len.code(), 2)
  @test.assert_eq(WireType::SGroup.code(), 3)
  @test.assert_eq(WireType::EGroup.code(), 4)
  @test.assert_eq(WireType::I32.code(), 5)
  assert_true(WireType::from_code(0) == Some(WireType::Varint))
  assert_true(WireType::from_code(2) == Some(WireType::Len))
  assert_true(WireType::from_code(3) == Some(WireType::SGroup))
  assert_true(WireType::from_code(4) == Some(WireType::EGroup))
  assert_true(WireType::from_code(5) == Some(WireType::I32))
  // 6 / 7 为非法取值。
  assert_true(WireType::from_code(6) is None)
  assert_true(WireType::from_code(7) is None)
}

// ─────────────────────────── encode / decode 往返 ────────────────────────

///|
/// 空消息编码为空字节，解码回空消息。
test "encode and decode empty message" {
  let msg = Message::empty()
  let bytes = encode(msg)
  @test.assert_eq(bytes.length(), 0)
  match decode(bytes, Schema::empty()) {
    Ok(out) => assert_true(out == Message::empty())
    Err(e) => fail("空消息不应解码失败：\{e}")
  }
}

///|
/// 含四类 wire 取值的消息：编码再解码得到等价消息（generic round-trip）。
test "encode then decode roundtrips generic fields" {
  let msg = Message::from_fields([
    FieldEntry::new(1, FieldValue::varint(150UL)),
    FieldEntry::new(2, FieldValue::bytes(b"hello")),
    FieldEntry::new(3, FieldValue::i32(0x01020304U)),
    FieldEntry::new(4, FieldValue::i64(0x0102030405060708UL)),
    FieldEntry::new(5, FieldValue::varint(0UL)),
  ])
  let bytes = encode(msg)
  match decode(bytes, Schema::empty()) {
    Ok(out) => assert_true(out == msg)
    Err(e) => fail("往返不应失败：\{e}")
  }
}

// ─────────────────── 解码错误契约（Requirement 9.4）────────────────────

///|
/// 截断的 varint（仅有续位字节）→ 含偏移的 UnexpectedEof，且不产生消息。
test "decode truncated varint reports offset and yields no object" {
  let bytes = b"\x80" // 续位标志置位却无后续字节。
  match decode(bytes, Schema::empty()) {
    Ok(_) =>
      fail("截断 varint 不应解码成功（不得产生部分对象）")
    Err(e) => {
      // 错误携带出错字节偏移（此处为 tag varint 起始 0）。
      @test.assert_eq(e.offset(), 0)
      match e {
        UnexpectedEof(..) => assert_true(true)
        _ => fail("期望 UnexpectedEof，实际：\{e}")
      }
    }
  }
}

///|
/// 非法 wire 类型（tag 低三位为 6 = 保留取值）→ 含偏移的 InvalidWireType。
test "decode invalid wire type reports offset" {
  let bytes = b"\x0e" // 字段号 1、wire 类型 6（非法）。
  match decode(bytes, Schema::empty()) {
    Ok(_) => fail("非法 wire 类型不应解码成功")
    Err(InvalidWireType(offset~, ..)) => @test.assert_eq(offset, 0)
    Err(other) => fail("期望 InvalidWireType，实际：\{other}")
  }
}

///|
/// 字段号 0 非法 → 含偏移的 InvalidFieldNumber。
test "decode invalid field number reports offset" {
  let bytes = b"\x00\x01" // tag=0 → 字段号 0、wire Varint。
  match decode(bytes, Schema::empty()) {
    Ok(_) => fail("字段号 0 不应解码成功")
    Err(InvalidFieldNumber(offset~, number~)) => {
      @test.assert_eq(offset, 0)
      @test.assert_eq(number, 0)
    }
    Err(other) => fail("期望 InvalidFieldNumber，实际：\{other}")
  }
}

///|
/// 定长字段字节不足 → 含偏移的 UnexpectedEof（偏移指向缺失数据起点）。
test "decode truncated fixed32 reports offset" {
  let bytes = b"\x0d\x01\x02" // 字段号 1、wire I32(5)，但仅 2 字节（需 4）。
  match decode(bytes, Schema::empty()) {
    Ok(_) => fail("定长字节不足不应解码成功")
    Err(UnexpectedEof(offset~)) => @test.assert_eq(offset, 1) // tag 占 1 字节，数据从偏移 1 起。
    Err(other) => fail("期望 UnexpectedEof，实际：\{other}")
  }
}

///|
/// 长度前缀超出剩余字节 → 含偏移的 UnexpectedEof。
test "decode length-delimited overflow reports offset" {
  let bytes = b"\x0a\x05ab" // 字段号 1、wire Len(2)，声明长度 5 但仅 2 字节。
  match decode(bytes, Schema::empty()) {
    Ok(_) => fail("长度前缀越界不应解码成功")
    Err(UnexpectedEof(..)) => assert_true(true)
    Err(other) => fail("期望 UnexpectedEof，实际：\{other}")
  }
}

// ─────────────────────── parse_proto（R9.5 / R9.6）───────────────────────

///|
/// 解析含消息、字段、repeated、枚举与枚举引用的 .proto，得到模式描述。
test "parse_proto extracts messages, fields and enums" {
  let src =
    #|syntax = "proto3";
    #|package demo;
    #|
    #|// 一个二维点
    #|message Point {
    #|  int32 x = 1;
    #|  int32 y = 2;
    #|  repeated string tags = 3;
    #|}
    #|
    #|enum Color {
    #|  RED = 0;
    #|  GREEN = 1;
    #|}
    #|
    #|message Pixel {
    #|  Point pos = 1;
    #|  Color color = 2;
    #|}
  match parse_proto(src) {
    Err(e) => fail("合法 .proto 不应解析失败：\{e}")
    Ok(schema) => {
      @test.assert_eq(schema.messages.length(), 2)
      let point = schema.messages[0]
      @test.assert_eq(point.name, "Point")
      @test.assert_eq(point.fields.length(), 3)
      @test.assert_eq(point.fields[0].name, "x")
      @test.assert_eq(point.fields[0].number, 1)
      assert_true(point.fields[0].ftype == FieldType::TInt32)
      assert_false(point.fields[0].repeated)
      // repeated string tags = 3
      assert_true(point.fields[2].ftype == FieldType::TString)
      assert_true(point.fields[2].repeated)
      // 枚举
      @test.assert_eq(schema.enums.length(), 1)
      @test.assert_eq(schema.enums[0].name, "Color")
      assert_true(schema.enums[0].values == [("RED", 0), ("GREEN", 1)])
      // 枚举引用解析后处理：Pixel.color 应为 TEnum，pos 应为 TMessage。
      let pixel = schema.messages[1]
      assert_true(pixel.fields[0].ftype == FieldType::TMessage("Point"))
      assert_true(pixel.fields[1].ftype == FieldType::TEnum("Color"))
    }
  }
}

///|
/// message 缺少消息名 → 返回含行列位置的解析错误。
test "parse_proto reports parse error with position" {
  let src = "message { }"
  match parse_proto(src) {
    Ok(_) => fail("缺少消息名的 .proto 不应解析成功")
    Err(e) => {
      @test.assert_eq(e.line, 1)
      assert_true(e.col > 0)
    }
  }
}

///|
/// 字段缺少结尾分号 → 解析错误（且不产生模式）。
test "parse_proto reports missing semicolon" {
  let src =
    #|message M {
    #|  int32 x = 1
    #|}
  match parse_proto(src) {
    Ok(_) => fail("字段缺少 ';' 不应解析成功")
    Err(_) => assert_true(true)
  }
}

// ──────────────────────────── gen_moonbit ────────────────────────────────

///|
/// gen_moonbit 由模式生成包含消息名与字段的 MoonBit 结构体骨架代码。
test "gen_moonbit emits struct skeleton from schema" {
  let src =
    #|message Pt {
    #|  int32 x = 1;
    #|  repeated string tags = 2;
    #|}
  let schema = match parse_proto(src) {
    Ok(s) => s
    Err(e) => {
      fail("解析夹具失败：\{e}")
      Schema::empty()
    }
  }
  let code = gen_moonbit(schema)
  let expected = "// 由 gen_moonbit 生成（骨架）—— 请勿手工编辑\n" +
    "\npub struct Pt {\n  x : Int\n  tags : Array[String]\n} derive(Eq, Debug)\n"
  assert_true(code == expected)
}
