// wire_group_test.mbt —— proto2 group（wire 类型 3/4）收口
// （INFRA 第五十批）：SGroup..EGroup 编解码 roundtrip、嵌套、畸形拒绝。

///|
fn wg_schema() -> @serialization.Schema {
  @serialization.Schema::empty()
}

///|
test "group：单层 roundtrip 与 wire_type/code 映射" {
  assert_eq(@serialization.WireType::SGroup.code(), 3)
  assert_eq(@serialization.WireType::EGroup.code(), 4)
  assert_true(
    @serialization.WireType::from_code(3) == Some(@serialization.SGroup),
  )
  assert_true(
    @serialization.WireType::from_code(4) == Some(@serialization.EGroup),
  )
  let inner = [
    @serialization.FieldEntry::new(1, @serialization.FieldValue::varint(150UL)),
    @serialization.FieldEntry::new(2, @serialization.FieldValue::bytes(b"hi")),
  ]
  let g = @serialization.FieldValue::group(inner)
  assert_true(g.wire_type() == @serialization.SGroup)
  let msg = @serialization.Message::from_fields([
    @serialization.FieldEntry::new(3, g),
    @serialization.FieldEntry::new(4, @serialization.FieldValue::varint(7UL)),
  ])
  let bytes = @serialization.encode(msg)
  // tag(3,SGROUP)=0x1B … tag(3,EGROUP)=0x1C。
  assert_eq(bytes[0].to_int(), 0x1B)
  match @serialization.decode(bytes, wg_schema()) {
    Ok(decoded) => assert_true(decoded == msg)
    Err(_) => assert_true(false)
  }
}

///|
test "group：嵌套分组与空分组 roundtrip" {
  let inner_group = @serialization.FieldValue::group([
    @serialization.FieldEntry::new(1, @serialization.FieldValue::i32(5U)),
  ])
  let outer = @serialization.Message::from_fields([
    @serialization.FieldEntry::new(
      2,
      @serialization.FieldValue::group([
        @serialization.FieldEntry::new(9, inner_group),
        @serialization.FieldEntry::new(
          1,
          @serialization.FieldValue::i64(0xDEADUL),
        ),
      ]),
    ),
    @serialization.FieldEntry::new(5, @serialization.FieldValue::group([])),
  ])
  let bytes = @serialization.encode(outer)
  match @serialization.decode(bytes, wg_schema()) {
    Ok(decoded) => assert_true(decoded == outer)
    Err(_) => assert_true(false)
  }
}

///|
test "group：畸形定界拒绝" {
  // 孤立 EGroup（字段号 1，tag=0x0C）。
  match @serialization.decode(b"\x0c", wg_schema()) {
    Err(e) =>
      assert_true(e is @serialization.InvalidWireType(offset=0, tag=0x0CUL))
    Ok(_) => assert_true(false)
  }
  // SGroup(1) 后跟号不匹配的 EGroup(2)（0x0B, 0x14）。
  match @serialization.decode(b"\x0b\x14", wg_schema()) {
    Err(e) =>
      assert_true(e is @serialization.InvalidWireType(offset=1, tag=0x14UL))
    Ok(_) => assert_true(false)
  }
  // 未闭合分组：SGroup(1) + varint 字段后输入截止。
  match @serialization.decode(b"\x0b\x10\x2a", wg_schema()) {
    Err(e) => assert_true(e is @serialization.UnexpectedEof(offset=3))
    Ok(_) => assert_true(false)
  }
  // 分组内部字段畸形（截断 varint）向上传播。
  match @serialization.decode(b"\x0b\x10\xff", wg_schema()) {
    Err(e) => assert_true(e is @serialization.UnexpectedEof(offset=2))
    Ok(_) => assert_true(false)
  }
}
