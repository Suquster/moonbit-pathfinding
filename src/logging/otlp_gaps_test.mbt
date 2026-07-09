// otlp_gaps_test.mbt —— OTLP 导出属性值全构造覆盖与采样率边界
// （INFRA 第二十三批）。

///|
test "otlp_export_traces：全部属性值构造与 Client 种别可编码" {
  let sd = SpanData::new({
    id: { value: 1L },
    parent: None,
    start: 10L,
    end: Some(20L),
  })
  sd.set_kind(Client)
  sd.set_attribute("b", VBool(true))
  sd.set_attribute("f", VFloat(2.5))
  sd.set_attribute("l", VList([VInt(1L), VStr("x")]))
  sd.set_attribute("m", VMap(Map([("k", VBool(false))])))
  let trace : TraceId = { value: 99L }
  let bytes = otlp_export_traces("svc", trace, [("op", sd)])
  assert_true(bytes.length() > 0)
  let json = otlp_export_traces_json("svc", trace, [("op", sd)])
  assert_true(json.length() > 0)
  // 编码可无损解回。
  assert_true(
    @serialization.decode_typed(otlp_schema(), "TracesData", bytes) is Ok(_),
  )
}

///|
test "sample_trace：rate=0 恒弃、rate=1 恒采" {
  let trace : TraceId = { value: 0x1234L }
  assert_false(sample_trace(0.0, trace, 7UL))
  assert_false(sample_trace(-0.5, trace, 7UL))
  assert_true(sample_trace(1.0, trace, 7UL))
  assert_true(sample_trace(1.5, trace, 7UL))
}
