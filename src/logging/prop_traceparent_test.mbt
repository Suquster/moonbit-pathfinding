// prop_traceparent_test.mbt —— traceparent 注入/提取往返属性测试（任务 9.2）。
//
//   Feature: logging, Property 11: traceparent 注入/提取往返
//   --------------------------------------------------------------------
//   *对任意* 合法 TraceContext ctx，注入为 traceparent 文本再提取，所得 trace-id /
//   span-id / flags 与原上下文一致：extract_traceparent(inject_traceparent(ctx))
//   为 Some(w)，三分量与 ctx 标识及采样标志一致，注入文本满足
//   `00-<32hex>-<16hex>-<2hex>` 形态（长度 55、严格可提取）。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。

///|
/// 合法 TraceContext 生成器：trace 取全 64 位随机标识；span 为 None 或非零标识。
fn tp_gen_ctx() -> @infra_pbt.Gen[TraceContext] {
  @infra_pbt.Gen::new(fn(rng) {
    let tval = rng.next().reinterpret_as_int64()
    let span : SpanId? = if rng.next_bool() {
      let sv0 = rng.next().reinterpret_as_int64()
      Some({ value: if sv0 == 0L { 1L } else { sv0 } })
    } else {
      None
    }
    { trace: ({ value: tval } : TraceId), span }
  })
}

///|
/// Feature: logging, Property 11: traceparent 注入/提取往返（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 6.1, 6.2, 6.6**
test "Feature: logging, Property 11: traceparent inject/extract round-trip (holds_for_all)" {
  let ok = @infra_pbt.holds_for_all(tp_gen_ctx(), fn(ctx) {
    let s = inject_traceparent(ctx)
    // 注入文本形态：长度恰 55（2+1+32+1+16+1+2）。
    if s.length() != 55 {
      return false
    }
    match extract_traceparent(s) {
      Some(w) => {
        // 严格提取成功即蕴含 32hex/16hex/2hex 形态；再校验采样位与往返。
        if !(w.is_sampled()) {
          return false
        }
        let back = w.to_trace_context()
        if back.trace.value != ctx.trace.value {
          return false
        }
        match (ctx.span, back.span) {
          (Some(a), Some(b)) => a.value == b.value
          (None, None) => true
          _ => false
        }
      }
      None => false
    }
  })
  assert_true(ok)
}

///|
/// 具体见证：注入再提取还原 trace/span 标识，sampled 位为真。
test "traceparent round-trips identifiers (witness)" {
  let ctx : TraceContext = {
    trace: { value: 0x0123456789abcdefL },
    span: Some({ value: 0x1122334455667788L }),
  }
  let s = inject_traceparent(ctx)
  assert_eq(s.length(), 55)
  assert_true(s.contains("0123456789abcdef")) // trace 低 64 位 hex
  assert_true(s.contains("1122334455667788")) // span hex
  match extract_traceparent(s) {
    Some(w) => {
      assert_true(w.is_sampled())
      let back = w.to_trace_context()
      assert_eq(back.trace.value, ctx.trace.value)
      assert_true(back.span == ctx.span)
    }
    None => fail("合法 traceparent 应提取成功")
  }
}
