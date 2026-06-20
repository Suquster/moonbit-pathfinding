// streaming_wbtest.mbt —— streaming.mbt 的最小内联烟雾测试（属性测试见任务 7.4）。
//
// 采用白盒测试（_wbtest.mbt）以便在同包内直接构造只读结构 `AnyValue`
// （`pub struct`，包外只读）。仅验证核心往返语义在代表性输入上成立：
//   * Any 包装往返：decode_any(encode_any(a)) == a；
//   * 流式帧化往返：decode_from(encode_to(m)) == m（含同一流多条消息顺序读）。

///|
/// Any 往返：含非空 type_url 与非空 value。
test "encode_any/decode_any 往返（非空）" {
  let any = AnyValue::{
    type_url: "type.googleapis.com/demo.Msg",
    value: Bytes::from_array([0x01, 0x02, 0x03, 0xFF]),
  }
  let decoded = match decode_any(encode_any(any)) {
    Ok(v) => v
    Err(_) => fail("decode_any 不应失败")
  }
  assert_eq(decoded, any)
}

///|
/// Any 往返：空 type_url 与空 value（边界）。
test "encode_any/decode_any 往返（空字段）" {
  let any = AnyValue::{ type_url: "", value: Bytes::from_array([]) }
  let decoded = match decode_any(encode_any(any)) {
    Ok(v) => v
    Err(_) => fail("decode_any 不应失败")
  }
  assert_eq(decoded, any)
}

///|
/// 流式帧化：单条消息往返，且读毕游标耗尽。
test "encode_to/decode_from 单条往返" {
  let schema = parse_proto_full(demo_proto()).unwrap()
  let msg = demo_message()
  let name = demo_message_name
  let sink = ByteSink::new()
  match encode_to(sink, schema, name, msg) {
    Ok(_) => ()
    Err(_) => fail("encode_to 不应失败")
  }
  let source = ByteSource::new(sink.to_bytes())
  let decoded = match decode_from(source, schema, name) {
    Ok(v) => v
    Err(_) => fail("decode_from 不应失败")
  }
  // 与既有 encode_typed/decode_typed 语义一致的往返不动点。
  let re = encode_typed(schema, name, decoded).unwrap()
  let direct = encode_typed(schema, name, msg).unwrap()
  assert_eq(re, direct)
  assert_true(source.is_exhausted())
}

///|
/// 流式帧化：同一流顺序排布两条消息，按序读出且游标正确推进。
test "encode_to/decode_from 多条顺序往返" {
  let schema = parse_proto_full(demo_proto()).unwrap()
  let msg = demo_message()
  let name = demo_message_name
  let sink = ByteSink::new()
  let _ = encode_to(sink, schema, name, msg)
  let _ = encode_to(sink, schema, name, msg)
  let source = ByteSource::new(sink.to_bytes())
  let first = decode_from(source, schema, name).unwrap()
  assert_true(!source.is_exhausted())
  let second = decode_from(source, schema, name).unwrap()
  assert_true(source.is_exhausted())
  let direct = encode_typed(schema, name, msg).unwrap()
  assert_eq(encode_typed(schema, name, first).unwrap(), direct)
  assert_eq(encode_typed(schema, name, second).unwrap(), direct)
}
