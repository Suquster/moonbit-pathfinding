// conformance_test.mbt —— protobuf 官方运行时一致性黄金语料回归（T9.1）。
//
// 本测试把 Google 权威 protobuf 运行时（见 conformance/gen_corpus.py，离线生成
// conformance/corpus.golden）产出的真实 wire 字节固化为下方 16 进制黄金向量，
// 断言本库**独立实现**的 `encode_typed` 产出、`decode_typed` 消费的字节与之
// **逐字节一致**——即与真实 protobuf 的跨实现互通（C3 正确性对标）。
//
// 覆盖全部 proto3 wire 分支：Varint(int32/int64/uint32/uint64/sint32/sint64/
// bool/enum)、I32(fixed32/sfixed32/float)、I64(fixed64/sfixed64/double)、
// LEN(string/bytes/嵌套消息)、packed repeated、map。
//
// 字段号升序排列，使权威运行时的规范字段序与本库的定义序发射一致，黄金向量稳定。
//
// 黄金向量需离线由 `python3 conformance/gen_corpus.py` 重新生成（CI 不联网）。

///|
/// 与 conformance/conformance.proto 等价的内嵌 schema 源（测试自包含，无文件 IO）。
let conformance_proto : String =
  #|syntax = "proto3";
  #|enum Color {
  #|  UNKNOWN = 0;
  #|  RED = 1;
  #|  GREEN = 2;
  #|}
  #|message Scalars {
  #|  int32 f_int32 = 1;
  #|  int64 f_int64 = 2;
  #|  uint32 f_uint32 = 3;
  #|  uint64 f_uint64 = 4;
  #|  sint32 f_sint32 = 5;
  #|  sint64 f_sint64 = 6;
  #|  fixed32 f_fixed32 = 7;
  #|  fixed64 f_fixed64 = 8;
  #|  sfixed32 f_sfixed32 = 9;
  #|  sfixed64 f_sfixed64 = 10;
  #|  float f_float = 11;
  #|  double f_double = 12;
  #|  bool f_bool = 13;
  #|  string f_string = 14;
  #|  bytes f_bytes = 15;
  #|  Color f_enum = 16;
  #|}
  #|message Nested {
  #|  Scalars inner = 1;
  #|  int32 tag = 2;
  #|}
  #|message Packed {
  #|  repeated int32 vals = 1;
  #|  repeated sint64 svals = 2;
  #|}
  #|message WithMap {
  #|  map<string, int32> m = 1;
  #|}

// ─── 权威黄金 wire 向量（protobuf 6.33.6 运行时；hex 见 corpus.golden）────────

///|
let golden_scalars_all : String = "08ffffffffffffffffff0110feffffffffffffffff0118ffffffff0f20ffffffffffffffffff012801309593d89fee473d7856341241f0debc9a785634124dfeffffff51fdffffffffffffff5d0000c03f6100000000000002c06801720668c3a96c6c6f7a0300ff10800102"

///|
let golden_scalars_int32_one : String = "0801"

///|
let golden_nested : String = "0a050807720178102a"

///|
let golden_packed : String = "0a0601ac02f0a2041203010306"

///|
let golden_map_single : String = "0a050a016b1005"

// ─────────────────────────────── hex 辅助 ──────────────────────────────────

///|
/// 单个 16 进制字符 → 0..15；非法返回 -1。
fn conf_hex_digit(c : Char) -> Int {
  let v = c.to_int()
  if v >= '0'.to_int() && v <= '9'.to_int() {
    v - '0'.to_int()
  } else if v >= 'a'.to_int() && v <= 'f'.to_int() {
    v - 'a'.to_int() + 10
  } else if v >= 'A'.to_int() && v <= 'F'.to_int() {
    v - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
/// 16 进制串 → `Bytes`（每两字符一字节）。
fn conf_hex_to_bytes(h : String) -> Bytes {
  let cs = h.iter().to_array()
  let out : Array[Byte] = []
  let mut i = 0
  while i + 1 < cs.length() + 1 && i + 1 <= cs.length() - 1 {
    let hi = conf_hex_digit(cs[i])
    let lo = conf_hex_digit(cs[i + 1])
    out.push(((hi << 4) | lo).to_byte())
    i = i + 2
  }
  Bytes::from_array(out)
}

///|
/// 解析内嵌 schema，失败即 fail（schema 错误应在开发期暴露）。
fn conf_schema() -> ProtoSchema raise {
  match parse_proto_full(conformance_proto) {
    Ok(s) => s
    Err(e) => fail("conformance.proto 解析失败：\{e}")
  }
}

///|
/// 构造 scalars_all 用例对应的类型化消息（与 gen_corpus.py 取值一一对应）。
fn conf_scalars_all_msg() -> TypedMessage {
  TypedMessage::new()
  .set(1, TInt(-1L))
  .set(2, TInt(-2L))
  .set(3, TUInt(0xFFFFFFFFUL))
  .set(4, TUInt(0xFFFFFFFFFFFFFFFFUL))
  .set(5, TInt(-1L))
  .set(6, TInt(-1234567890123L))
  .set(7, TUInt(305419896UL))
  .set(8, TUInt(0x123456789ABCDEF0UL))
  .set(9, TInt(-2L))
  .set(10, TInt(-3L))
  .set(11, TFloatV((1.5 : Float)))
  .set(12, TDoubleV(-2.25))
  .set(13, TBoolV(true))
  .set(14, TStringV("héllo"))
  .set(15, TBytesV(b"\x00\xff\x10"))
  .set(16, TEnumV(2))
}

// ───────────────────────────────── 测试 ────────────────────────────────────

///|
/// 断言本库独立编码 == 权威 protobuf 黄金字节（逐字节）。
fn conf_check_encode(
  schema : ProtoSchema,
  name : String,
  msg : TypedMessage,
  golden : String,
) -> Unit raise {
  let expected = conf_hex_to_bytes(golden)
  match encode_typed(schema, name, msg) {
    Ok(bytes) => assert_true(bytes == expected)
    Err(e) => fail("\{name} 编码失败：\{e}")
  }
}

///|
/// 解码权威黄金字节后再编码，断言复现同一字节（round-trip 逐字节）。
fn conf_check_roundtrip(
  schema : ProtoSchema,
  name : String,
  golden : String,
) -> Unit raise {
  let bytes = conf_hex_to_bytes(golden)
  match decode_typed(schema, name, bytes) {
    Ok(msg) =>
      match encode_typed(schema, name, msg) {
        Ok(re) => assert_true(re == bytes)
        Err(e) => fail("\{name} 再编码失败：\{e}")
      }
    Err(e) => fail("\{name} 解码失败：\{e}")
  }
}

///|
/// encode 一致性：本库独立编码 == 权威 protobuf 黄金字节（逐字节）。
test "conformance: encode matches authoritative protobuf golden bytes" {
  let schema = conf_schema()
  conf_check_encode(
    schema,
    "Scalars",
    conf_scalars_all_msg(),
    golden_scalars_all,
  )
  conf_check_encode(
    schema,
    "Scalars",
    TypedMessage::new().set(1, TInt(1L)),
    golden_scalars_int32_one,
  )
  let inner = TypedMessage::new().set(1, TInt(7L)).set(14, TStringV("x"))
  conf_check_encode(
    schema,
    "Nested",
    TypedMessage::new().set(1, TMsg(inner)).set(2, TInt(42L)),
    golden_nested,
  )
  conf_check_encode(
    schema,
    "Packed",
    TypedMessage::new()
    .set(1, TList([TInt(1L), TInt(300L), TInt(70000L)]))
    .set(2, TList([TInt(-1L), TInt(-2L), TInt(3L)])),
    golden_packed,
  )
  conf_check_encode(
    schema,
    "WithMap",
    TypedMessage::new().set(1, TMap([(TStringV("k"), TInt(5L))])),
    golden_map_single,
  )
}

///|
/// decode 一致性 + round-trip：解码权威黄金字节后再编码必须复现同一字节。
test "conformance: decode authoritative golden bytes round-trips byte-exact" {
  let schema = conf_schema()
  conf_check_roundtrip(schema, "Scalars", golden_scalars_all)
  conf_check_roundtrip(schema, "Scalars", golden_scalars_int32_one)
  conf_check_roundtrip(schema, "Nested", golden_nested)
  conf_check_roundtrip(schema, "Packed", golden_packed)
  conf_check_roundtrip(schema, "WithMap", golden_map_single)
}

///|
/// decode 逐字段语义：从权威字节解出的取值与构造取值逐字段相等。
test "conformance: decoded field values match constructed values" {
  let schema = conf_schema()
  let bytes = conf_hex_to_bytes(golden_scalars_all)
  match decode_typed(schema, "Scalars", bytes) {
    Ok(msg) => {
      assert_true(msg.get(1) == Some(TInt(-1L)))
      assert_true(msg.get(4) == Some(TUInt(0xFFFFFFFFFFFFFFFFUL)))
      assert_true(msg.get(6) == Some(TInt(-1234567890123L)))
      assert_true(msg.get(11) == Some(TFloatV((1.5 : Float))))
      assert_true(msg.get(12) == Some(TDoubleV(-2.25)))
      assert_true(msg.get(14) == Some(TStringV("héllo")))
      assert_true(msg.get(16) == Some(TEnumV(2)))
    }
    Err(e) => fail("解码失败：\{e}")
  }
}

///|
/// 未知字段保真：以仅声明前 3 个字段的裁剪 schema 解码完整 Scalars 字节，
/// 字段 4..16 进入 unknown 原样保留，再编码必须逐字节复现原黄金字节（T9.2 关键）。
test "conformance: unknown fields preserved byte-exact across re-encode" {
  let full = conf_schema()
  // 裁剪 schema：Scalars 仅保留字段 1/2/3。
  let trimmed_proto =
    #|syntax = "proto3";
    #|message Scalars {
    #|  int32 f_int32 = 1;
    #|  int64 f_int64 = 2;
    #|  uint32 f_uint32 = 3;
    #|}
  let trimmed = match parse_proto_full(trimmed_proto) {
    Ok(s) => s
    Err(e) => fail("trimmed 解析失败：\{e}")
  }
  ignore(full)
  let bytes = conf_hex_to_bytes(golden_scalars_all)
  match decode_typed(trimmed, "Scalars", bytes) {
    Ok(msg) => {
      // 字段 4..16 应保留为 unknown（至少存在若干条）。
      assert_true(msg.unknown.length() > 0)
      match encode_typed(trimmed, "Scalars", msg) {
        Ok(re) => assert_true(re == bytes)
        Err(e) => fail("再编码失败：\{e}")
      }
    }
    Err(e) => fail("裁剪解码失败：\{e}")
  }
}
