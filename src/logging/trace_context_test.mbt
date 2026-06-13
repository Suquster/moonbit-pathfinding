// trace_context_test.mbt —— 非法提取、sampled 位、桥接续记单元测试（任务 9.3）。
//
// 覆盖 Requirement 6.3（sampled 位）/ 6.4（非法提取返回 None 不产部分上下文）/
// 6.5（to_trace_context 桥接后经 with_context 续记保持 trace 关联）。

///|
/// 字段数 / 分量长度 / hex 字符不符规范的 traceparent 一律返回 None。
test "extract_traceparent rejects malformed inputs" {
  // 分量数不足（缺 flags）。
  assert_true(
    extract_traceparent("00-" + "0".repeat(32) + "-" + "0".repeat(16)) is None,
  )
  // trace-id 长度错误（31 hex）。
  assert_true(
    extract_traceparent("00-" + "0".repeat(31) + "-" + "0".repeat(16) + "-01")
    is None,
  )
  // span-id 长度错误（15 hex）。
  assert_true(
    extract_traceparent("00-" + "0".repeat(32) + "-" + "0".repeat(15) + "-01")
    is None,
  )
  // flags 长度错误（1 hex）。
  assert_true(
    extract_traceparent("00-" + "0".repeat(32) + "-" + "0".repeat(16) + "-1")
    is None,
  )
  // 非 hex 字符。
  assert_true(
    extract_traceparent("00-" + "g".repeat(32) + "-" + "0".repeat(16) + "-01")
    is None,
  )
  // 多余分量。
  assert_true(
    extract_traceparent(
      "00-" + "0".repeat(32) + "-" + "0".repeat(16) + "-01-extra",
    )
    is None,
  )
  // 空串。
  assert_true(extract_traceparent("") is None)
}

///|
/// sampled 位判定：flags 最低位为 1 ⟹ sampled，为 0 ⟹ 非 sampled（Requirement 6.3）。
test "is_sampled reflects lowest flag bit" {
  let trace_id = "0".repeat(31) + "1"
  let span_id = "0".repeat(15) + "2"
  match extract_traceparent("00-" + trace_id + "-" + span_id + "-01") {
    Some(w) => assert_true(w.is_sampled())
    None => fail("应提取成功")
  }
  match extract_traceparent("00-" + trace_id + "-" + span_id + "-00") {
    Some(w) => assert_false(w.is_sampled())
    None => fail("应提取成功")
  }
  // flags=03 最低位仍为 1。
  match extract_traceparent("00-" + trace_id + "-" + span_id + "-03") {
    Some(w) => assert_true(w.is_sampled())
    None => fail("应提取成功")
  }
}

///|
/// to_trace_context 桥接后经 with_context 续记，下游事件保持父 trace 标识
/// （Requirement 6.5）。
test "to_trace_context bridges into with_context preserving trace" {
  reset_logger()
  let ctx : TraceContext = {
    trace: { value: 0xABCDEF12L },
    span: Some({ value: 7L }),
  }
  let tp = inject_traceparent(ctx)
  let extracted = match extract_traceparent(tp) {
    Some(w) => w
    None => {
      fail("应提取成功")
      return
    }
  }
  let bridged = extracted.to_trace_context()
  assert_eq(bridged.trace.value, ctx.trace.value)
  // 在桥接上下文下续记，事件归属同一 trace。
  let tid = with_context(bridged, fn() {
    log(Level::Info, { "msg": VStr("downstream") })
    current_trace()
  })
  assert_eq(tid.value, ctx.trace.value)
  let e = captured_events()[0]
  assert_true(e.fields.get("trace") == Some(VInt(ctx.trace.value)))
}
