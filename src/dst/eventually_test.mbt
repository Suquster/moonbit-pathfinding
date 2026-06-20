// eventually_test.mbt —— 最终性断言与不变量轨迹检查的内联烟雾测试（任务 9.2）。
//
// 完整属性测试（相同种子逐事件可复现 / invariant 违例报告 / eventually 未成立
// 报告）属任务 9.3，此处仅做最小冒烟验证：
//   (1) 迟早成立的谓词返回 EHolds 并定位首个成立的步；
//   (2) 永不成立的谓词返回 ENeverHeld；
//   (3) check_invariant_over 在违例时报告步号、全程成立时返回 None。

///|
/// 构造一条简单轨迹用于检查：单任务追加日志并发送一条消息。
fn sample_trace() -> Array[SimEvent] {
  let t = ExecutableTask::new(1, "leader", fn(ctx) {
    ctx.send(to=2, payload=7, after=3UL)
    TDone
  })
  run_executable(123UL, [t], max_steps=8)
}

///|
/// 迟早成立：谓词「前缀已包含至少 1 个事件」在第 0 步即首次成立。
test "eventually 迟早成立返回 EHolds" {
  let trace = sample_trace()
  let r = eventually(trace, fn(prefix) { prefix.length() >= 1 })
  assert_true(r == EHolds(step=0))
}

///|
/// 定位首次成立：谓词「前缀长度达到 3」在第 2 步（前缀 trace[0..=2]）首次成立。
test "eventually 定位首个成立前缀" {
  let trace = sample_trace()
  let r = eventually(trace, fn(prefix) { prefix.length() >= 3 })
  assert_true(r == EHolds(step=2))
}

///|
/// 永不成立：谓词恒假，遍历完整轨迹仍未成立，返回 ENeverHeld（AC6 失败语义）。
test "eventually 永不成立返回 ENeverHeld" {
  let trace = sample_trace()
  let r = eventually(trace, fn(_prefix) { false })
  assert_true(r == ENeverHeld)
}

///|
/// 不变量全程成立：恒真不变量在任一前缀均成立，返回 None。
test "check_invariant_over 全程成立返回 None" {
  let trace = sample_trace()
  let r = check_invariant_over(trace, name="始终成立", fn(_prefix) { true })
  assert_true(r is None)
}

///|
/// 不变量违例：限制「前缀长度不超过 1」，在第 1 步首次违反，报告含名称与步号。
test "check_invariant_over 违例报告步号" {
  let trace = sample_trace()
  let r = check_invariant_over(trace, name="长度上限", fn(prefix) {
    prefix.length() <= 1
  })
  match r {
    Some(msg) => {
      assert_true(msg.contains("长度上限"))
      assert_true(msg.contains("步 1"))
    }
    None => assert_true(false)
  }
}
