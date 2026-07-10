// typed_gaps_wbtest.mbt —— 类型化编解码内部辅助分支覆盖收口
// （INFRA 第二十一批）：类型默认值全谱、默认值判定非标量兜底、
// wire 类别映射、packed 载荷对 Len 类别的拒绝见证。

///|
test "typed_default/typed_is_default 全谱与非标量兜底" {
  assert_true(typed_default(PBool) == TBoolV(false))
  assert_true(typed_default(PSInt32) == TInt(0L))
  assert_true(typed_default(PFixed64) == TUInt(0UL))
  assert_true(typed_default(PEnum("E")) == TEnumV(0))
  assert_true(typed_default(PString) == TStringV(""))
  assert_true(typed_default(PBytes) == TBytesV(b""))
  assert_true(typed_default(PMessage("M")) is TMsg(_))
  // 默认值判定：标量各臂 + 非标量（TMsg/TList/TMap）恒 false。
  assert_true(typed_is_default(TBoolV(false)))
  assert_false(typed_is_default(TBoolV(true)))
  assert_true(typed_is_default(TFloatV((0.0 : Float))))
  assert_true(typed_is_default(TDoubleV(0.0)))
  assert_true(typed_is_default(TBytesV(b"")))
  assert_false(typed_is_default(TBytesV(b"\x01")))
  assert_false(typed_is_default(TMsg(TypedMessage::new())))
  assert_false(typed_is_default(TList([])))
  assert_false(typed_is_default(TMap([])))
}

///|
test "proto_wire_type/proto_is_numeric_scalar 类别映射" {
  assert_true(proto_wire_type(PString) == Len)
  assert_true(proto_wire_type(PBytes) == Len)
  assert_true(proto_wire_type(PMessage("M")) == Len)
  assert_true(proto_wire_type(PFloat) == I32)
  assert_true(proto_wire_type(PSFixed64) == I64)
  assert_true(proto_wire_type(PEnum("E")) == Varint)
  assert_false(proto_is_numeric_scalar(PString))
  assert_false(proto_is_numeric_scalar(PMessage("M")))
  assert_true(proto_is_numeric_scalar(PBool))
  assert_false(proto_is_scalar(PMessage("M")))
  assert_true(proto_is_scalar(PBytes))
}

///|
test "typed packed 载荷解码：Len 类别拒绝与畸形传播" {
  // Len 类别（string）不可 packed：直接拒绝。
  assert_true(typed_unpack(PString, b"\x01a") is Err(_))
  // Varint 载荷截断传播。
  assert_true(typed_unpack(PInt32, b"\x80") is Err(_))
  // I32/I64 载荷截断。
  assert_true(typed_unpack(PFloat, b"\x01\x02") is Err(_))
  assert_true(typed_unpack(PDouble, b"\x01\x02\x03") is Err(_))
  // 合法 packed：两个 varint 与两个 fixed32。
  match typed_unpack(PInt32, b"\x03\x7f") {
    Ok(vs) => assert_true(vs == [TInt(3L), TInt(127L)])
    Err(_) => assert_true(false)
  }
  match typed_unpack(PFixed32, b"\x01\x00\x00\x00\x02\x00\x00\x00") {
    Ok(vs) => assert_true(vs == [TUInt(1UL), TUInt(2UL)])
    Err(_) => assert_true(false)
  }
}

///|
test "typed_default：浮点/双精度缺省值构造" {
  assert_true(typed_default(PFloat) == TFloatV((0.0 : Float)))
  assert_true(typed_default(PDouble) == TDoubleV(0.0))
}
