// typed_coverage_wbtest.mbt —— typed.mbt 私有防御分支的白盒回归。
//
// 以下分支在公开 encode_typed/decode_typed 路径上不可达：packed 拆包只对
// 数值标量发起（proto_is_numeric_scalar），故 `proto_wire_type` 的 `Len`
// 类别与 `typed_unpack` 的 `Len => Err` 分支、以及 `write_scalar_to_buf`
// 收到 VBytes（仅 string/bytes/message 产出）的防御分支都进不来。这里直接
// 白盒触发，锁定其防御语义。

///|
test "wb: proto_wire_type maps Len-class types" {
  assert_true(proto_wire_type(PString) is Len)
  assert_true(proto_wire_type(PBytes) is Len)
  assert_true(proto_wire_type(PMessage("X")) is Len)
}

///|
test "wb: typed_unpack rejects Len-class element type" {
  match typed_unpack(PString, b"\x01\x02") {
    Ok(_) => fail("Len 类元素不可 packed 拆包")
    Err(_) => assert_true(true)
  }
}

///|
test "wb: write_scalar_to_buf rejects non-numeric (VBytes) value" {
  let empty = ProtoSchema::empty()
  let buf : Array[Byte] = []
  match write_scalar_to_buf(empty, PString, TStringV("x"), buf) {
    Ok(_) => fail("非数值标量不能写入 packed 缓冲")
    Err(_) => assert_true(true)
  }
}
