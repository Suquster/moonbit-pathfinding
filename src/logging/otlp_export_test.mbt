// otlp_export_test.mbt —— T7.1 真·OTLP 导出器的黑盒验证。
//
// 三层保证：
//   1. 黄金见证：固定 span 的 OTLP protobuf 字节十六进制快照（外部已用官方
//      opentelemetry-proto Python 绑定解码验证，见
//      docs/verification/otlp-export-t7.md）；
//   2. 结构往返：导出的字节可被本仓 decode_typed 按同一模式解回，且与
//      构造的 TypedMessage 逐字段相等（编码无损）；
//   3. 一致性：trace/span id 字节与 W3C traceparent 十六进制逐字节一致；
//      发射确定性（同输入两次导出逐字节相等）。

///|
/// 固定 span 样本：trace=0x1122334455667788，span=42，parent=7，
/// kind=Server，status=Ok，一个属性 + 一个带字段的事件。
fn otlp_sample() -> (TraceId, String, SpanData) {
  let sd = SpanData::new({
    id: { value: 42L },
    parent: Some({ value: 7L }),
    start: 1000L,
    end: Some(2500L),
  })
  sd.set_kind(Server)
  sd.set_status(SpanStatus::Ok)
  sd.set_attribute("http.method", VStr("GET"))
  sd.add_event("retry", 1500L, Map([("attempt", VInt(2L))]))
  ({ value: 0x1122334455667788L }, "handle_request", sd)
}

///|
/// 字节 → 小写十六进制（黄金快照用）。
fn otlp_hex(b : Bytes) -> String {
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let sb = StringBuilder::new()
  for byte in b {
    let v = byte.to_int()
    sb.write_char(digits[v >> 4])
    sb.write_char(digits[v & 0xF])
  }
  sb.to_string()
}

///|
test "Feature: logging, Golden: OTLP protobuf bytes for a fixed span (externally verified)" {
  let (trace, name, sd) = otlp_sample()
  let bytes = otlp_export_traces("pathfinding-demo", trace, [(name, sd)])
  // 外部验证：该十六进制经官方 opentelemetry-proto（Python）TracesData 解码，
  // 逐字段等于本样本（docs/verification/otlp-export-t7.md）。
  let expected_hex =
    #|0ac3010a240a220a0c736572766963652e6e616d6512120a107061746866696e64696e672d64656d6f129a010a100a076c6f6767696e671205302e322e301285010a10000000000000000011223344556677881208000000000000002a220800000000000000072a0e68616e646c655f72657175657374300239e80300000000000041c4090000000000004a140a0b687474702e6d6574686f6412050a034745545a1f09dc05000000000000120572657472791a0d0a07617474656d7074120218027a021801
  assert_eq(otlp_hex(bytes), expected_hex)
}

///|
test "Feature: logging, Contract: exported OTLP bytes decode back to the built message losslessly" {
  let (trace, name, sd) = otlp_sample()
  let built = otlp_traces_data("svc", trace, [(name, sd)])
  let bytes = otlp_export_traces("svc", trace, [(name, sd)])
  match @serialization.decode_typed(otlp_schema(), "TracesData", bytes) {
    Ok(decoded) => assert_true(decoded == built)
    Err(_) => fail("OTLP 字节应能被同模式解码")
  }
}

///|
test "Feature: logging, Contract: OTLP ids match W3C traceparent hex byte-for-byte" {
  let (trace, name, sd) = otlp_sample()
  let bytes = otlp_export_traces("svc", trace, [(name, sd)])
  let hex = otlp_hex(bytes)
  // traceparent（trace_context.mbt）：trace_id = 16 个 0 + hex(低 64 位)。
  let tp = inject_traceparent({ trace, span: Some(sd.span.id) })
  // "00-{trace32}-{span16}-01"
  let trace_hex = tp[3:35].to_owned()
  let span_hex = tp[36:52].to_owned()
  assert_eq(trace_hex, "00000000000000001122334455667788")
  assert_eq(span_hex, "000000000000002a")
  assert_true(hex.contains(trace_hex))
  assert_true(hex.contains(span_hex))
}

///|
test "Feature: logging, Contract: OTLP/JSON carries aligned field names and values" {
  let (trace, name, sd) = otlp_sample()
  let json = otlp_export_traces_json("pathfinding-demo", trace, [(name, sd)])
  assert_true(json.contains("resource_spans") || json.contains("resourceSpans"))
  assert_true(json.contains("handle_request"))
  assert_true(json.contains("service.name"))
  assert_true(json.contains("http.method"))
}

///|
test "Feature: logging, Golden: OTLP links and status message (externally verified)" {
  let sd = SpanData::new({
    id: { value: 5L },
    parent: None,
    start: 10L,
    end: Some(20L),
  })
  sd.add_link({ value: 0xABCDL }, { value: 0x1234L }, Map([("src", VStr("q"))]))
  sd.set_status_with_message(SpanStatus::Error, "boom")
  let bytes = otlp_export_traces("svc", { value: 3L }, [("linked", sd)])
  // 外部验证：官方 opentelemetry-proto 解码后 links[0].trace_id/span_id、
  // link 属性、status{code=ERROR, message="boom"} 逐字段相等
  // （docs/verification/otlp-export-t7.md）。
  let expected_hex =
    #|0a9c010a170a150a0c736572766963652e6e616d6512050a037376631280010a100a076c6f6767696e671205302e322e30126c0a1000000000000000000000000000000003120800000000000000052a066c696e6b65643001390a000000000000004114000000000000006a280a100000000000000000000000000000abcd12080000000000001234220a0a0373726312030a01717a081204626f6f6d1802
  assert_eq(otlp_hex(bytes), expected_hex)
  match @serialization.decode_typed(otlp_schema(), "TracesData", bytes) {
    Ok(_) => ()
    Err(_) => fail("含 links/status message 的 OTLP 字节应可解回")
  }
}

///|
test "Feature: logging, Property: OTLP emission is deterministic and total on random spans" {
  let rng = @infra_pbt.rng_new(20260705UL)
  for _ in 0..<100 {
    let sd = SpanData::new({
      id: { value: rng.next_range(1, 1 << 30).to_int64() },
      parent: if rng.next_bool() {
        Some({ value: rng.next_range(1, 1 << 30).to_int64() })
      } else {
        None
      },
      start: rng.next_range(0, 1 << 30).to_int64(),
      end: if rng.next_bool() {
        Some(rng.next_range(0, 1 << 30).to_int64())
      } else {
        None
      },
    })
    if rng.next_bool() {
      sd.set_attribute("k", VInt(rng.next_range(0, 1000).to_int64()))
    }
    let trace : TraceId = { value: rng.next_range(1, 1 << 30).to_int64() }
    let b1 = otlp_export_traces("svc", trace, [("s", sd)])
    let b2 = otlp_export_traces("svc", trace, [("s", sd)])
    assert_true(b1 == b2)
    assert_true(b1.length() > 0)
    // 且始终可解回。
    assert_true(
      @serialization.decode_typed(otlp_schema(), "TracesData", b1) is Ok(_),
    )
  }
}
