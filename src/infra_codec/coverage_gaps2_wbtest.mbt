// 黑盒测试：CBOR Show 渲染各分支与 64 位头值往返。

///|
test "cbor：CborValue Show 全构造子渲染" {
  let v = CborMap([
    (CborText("k"), CborArray([CborUInt(1UL), CborNInt(2UL)])),
    (CborBool(true), CborBytes([1, 2])),
    (CborNull, CborFloat(1.5)),
  ])
  let s = "\{v}"
  assert_true(s.contains("CborMap") && s.contains("CborArray"))
  assert_true(s.contains("CborText") && s.contains("CborBytes([1, 2]"))
  assert_true(s.contains("CborBool(true)") && s.contains("CborNull"))
  assert_true(s.contains("CborFloat"))
}

///|
test "cbor：8 字节头值（info=27）编解码往返" {
  let big = CborUInt(4294967296UL) // 2^32：需要 8 字节头。
  let bytes = cbor_encode(big)
  assert_true(cbor_decode(bytes) == Some(big))
  // 截断的 8 字节头拒绝。
  assert_true(cbor_decode([0x1B, 0x00, 0x00]) is None)
}
