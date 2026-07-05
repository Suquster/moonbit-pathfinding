// unknown_reencode_test.mbt —— 外来字节的未知字段逐字节回写（T9.2/T9.3 深化）。
//
// Feature: serialization, Property: unknown-field byte-level re-encode
//
// 跨版本互通的关键契约：用**旧 schema** 解码**新版本写方**产出的字节（含旧
// schema 不认识的字段）时，未知字段必须原样保留；再编码产出的字节与原始输入
// **逐字节一致**（已知字段按定义序在前、未知字段按 wire 序在后的输入布局下）。
// 这保证中间件 / 代理即使不升级 schema 也不会丢弃或破坏新字段。
//
// **Validates: Requirements 2.1, 2.2, 2.7**

///|
/// 旧 schema：只认识字段 1。
let ur_old_proto : String =
  #|syntax = "proto3";
  #|message M {
  #|  int32 a = 1;
  #|}

///|
/// 嵌套场景 schema：外层认识字段 1（嵌套消息），内层只认识字段 1。
let ur_nested_proto : String =
  #|syntax = "proto3";
  #|message Inner {
  #|  int32 x = 1;
  #|}
  #|message Outer {
  #|  Inner inner = 1;
  #|}

///|
/// 顶层未知字段全 wire 类型覆盖：Varint / LEN / I64 / I32 的未知字段经
/// 解码-再编码逐字节保真。
test "unknown fields of every wire type re-encode byte-identically" {
  let schema = match parse_proto_full(ur_old_proto) {
    Ok(s) => s
    Err(_) => abort("unexpected proto parse error")
  }
  // 「新版本写方」的字节：已知字段 1 + 未知字段 2(varint)/3(LEN)/4(I64)/5(I32)。
  let src = Message::from_fields([
    FieldEntry::new(1, FieldValue::varint(7)),
    FieldEntry::new(2, FieldValue::varint(300)),
    FieldEntry::new(3, FieldValue::bytes(b"xyz")),
    FieldEntry::new(4, FieldValue::i64(0x0102030405060708)),
    FieldEntry::new(5, FieldValue::i32(0xdeadbeef)),
  ])
  let bytes = encode(src)
  let msg = match decode_typed(schema, "M", bytes) {
    Ok(m) => m
    Err(_) => abort("unexpected decode error")
  }
  // 未知字段号与 wire 类型逐一保留。
  assert_eq(msg.unknown.length(), 4)
  assert_eq(msg.unknown[0].number, 2)
  assert_eq(msg.unknown[1].number, 3)
  assert_eq(msg.unknown[2].number, 4)
  assert_eq(msg.unknown[3].number, 5)
  // 再编码逐字节一致。
  match encode_typed(schema, "M", msg) {
    Ok(out) => assert_eq(out, bytes)
    Err(_) => abort("unexpected encode error")
  }
}

///|
/// 嵌套消息内部的未知字段同样逐字节保真（未知性在每层独立判定）。
test "unknown fields inside nested messages re-encode byte-identically" {
  let schema = match parse_proto_full(ur_nested_proto) {
    Ok(s) => s
    Err(_) => abort("unexpected proto parse error")
  }
  // 内层：已知字段 1 + 未知字段 9（varint）与 10（LEN）。
  let inner = Message::from_fields([
    FieldEntry::new(1, FieldValue::varint(42)),
    FieldEntry::new(9, FieldValue::varint(65536)),
    FieldEntry::new(10, FieldValue::bytes(b"tail")),
  ])
  let outer = Message::from_fields([
    FieldEntry::new(1, FieldValue::bytes(encode(inner))),
  ])
  let bytes = encode(outer)
  let msg = match decode_typed(schema, "Outer", bytes) {
    Ok(m) => m
    Err(_) => abort("unexpected decode error")
  }
  match encode_typed(schema, "Outer", msg) {
    Ok(out) => assert_eq(out, bytes)
    Err(_) => abort("unexpected encode error")
  }
}
