// prop_span_tree_test.mbt —— span 树父子不变量与时长非负属性测试（任务 8.2）。
//
//   Feature: logging, Property 10: span 树父子不变量（span-tree invariant）
//   --------------------------------------------------------------------
//   *对任意* enter_span/exit_span 进入/退出序列，每个非根 span 的父标识等于其
//   进入时刻的激活 span 标识，且每个已结束 span 的时长非负。该属性同时固化
//   OTel 语义（SpanData 属性/事件/状态/kind）旁路叠加后既有 span 树构建与时长
//   计算行为不变（Requirement 5.5 / 5.6）。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。每次场景先 reset_logger。

///|
/// 单次场景：随机深度地连续进入嵌套 span，并对每个 span 旁路叠加 SpanData（设
/// 属性/事件/状态/kind），断言：根 span 无父、嵌套 span 父为外层 span、退出后
/// 全部已结束 span 时长非负——即 OTel 旁路叠加不改既有 span 树与时长语义。
fn pst_span_tree(rng : @infra_pbt.Rng) -> Bool {
  reset_logger()
  let _trace = begin_trace()
  let depth = rng.next_range(1, 6)
  let spans : Array[Span] = []
  let mut prev : SpanId? = None
  for d in 0..<depth {
    let s = enter_span("s\{d}")
    // OTel 旁路叠加（不得影响既有 span 树/时长）。
    let sd = SpanData::new(s)
    sd.set_attribute("depth", VInt(d.to_int64()))
    sd.set_status(SpanStatus::Ok)
    sd.set_kind(SpanKind::Server)
    sd.add_event("entered", s.start, { "d": VInt(d.to_int64()) })
    if d == 0 {
      if !(s.parent is None) {
        return false
      }
    } else if s.parent != prev {
      return false
    }
    prev = Some(s.id)
    spans.push(s)
  }
  // 逆序退出。
  for d = spans.length() - 1; d >= 0; d = d - 1 {
    exit_span(spans[d])
  }
  // 全部已结束 span 时长非负。
  for fs in finished_spans() {
    match span_duration(fs) {
      Some(dur) => if dur < 0L { return false }
      None => return false
    }
  }
  true
}

///|
/// Feature: logging, Property 10: span 树父子不变量（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 5.5, 5.6**
test "Feature: logging, Property 10: span-tree invariant (holds_for_all)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { pst_span_tree(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// 具体见证：嵌套 span 形成树，OTel SpanData 叠加后时长仍非负。
test "span tree invariant holds with otel overlay (witness)" {
  reset_logger()
  let _t = begin_trace()
  let root = enter_span("root")
  let child = enter_span("child")
  assert_true(root.parent is None)
  assert_true(child.parent == Some(root.id))
  let sd = SpanData::new(child)
  sd.set_attribute("k", VStr("v"))
  exit_span(child)
  exit_span(root)
  for fs in finished_spans() {
    match span_duration(fs) {
      Some(d) => assert_true(d >= 0L)
      None => fail("已结束 span 应有时长")
    }
  }
}
