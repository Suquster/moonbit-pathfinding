// demo_test.mbt —— 端到端 demo 流程单元测试（任务 13.3）。
//
// 覆盖 Requirement 11.2（嵌套 span / 采样 / 脱敏 / 多格式输出）与 11.3
// （run_demo 注入 → run_downstream 提取后下游与父进程同 trace-id）。

///|
/// run_demo 串联全链路：2 个 span、3 条事件双格式输出、敏感字段脱敏、
/// traceparent 形态正确。
test "run_demo produces nested spans, sampling, redaction and multi-format output" {
  let outcome = run_demo()
  // 嵌套 span：root + db = 2 个已结束 span。
  @test.assert_eq(outcome.span_count, 2)
  // 3 条事件（Info/Debug/Warn）→ 3 行 JSON + 3 行 logfmt。
  @test.assert_eq(outcome.json_lines.length(), 3)
  @test.assert_eq(outcome.logfmt_lines.length(), 3)
  // 脱敏：password / token 原值不出现在任何输出行；掩码至少出现在含敏感字段的行。
  let mut redacted_count = 0
  for line in outcome.json_lines {
    assert_false(line.contains("hunter2"))
    assert_false(line.contains("secret-bearer"))
    if line.contains("[REDACTED]") {
      redacted_count = redacted_count + 1
    }
  }
  // Info（password）与 Debug（token）两行被脱敏；Warn 行无敏感字段。
  @test.assert_eq(redacted_count, 2)
  for line in outcome.logfmt_lines {
    assert_false(line.contains("hunter2"))
    assert_false(line.contains("secret-bearer"))
  }
  // 嵌套字段（headers）以 JSON 对象出现（未脱敏）。
  assert_true(outcome.json_lines[0].contains("\"accept\":\"application/json\""))
  // traceparent 形态：长度 55、可被严格提取。
  @test.assert_eq(outcome.traceparent.length(), 55)
  assert_true(extract_traceparent(outcome.traceparent) is Some(_))
}

///|
/// run_demo 注入 traceparent → run_downstream 提取后，下游与父进程归属同一 trace-id。
test "run_downstream shares trace id with run_demo (cross-process)" {
  let outcome = run_demo()
  match run_downstream(outcome.traceparent) {
    Some(tid) => @test.assert_eq(tid.value, outcome.trace.value)
    None => fail("下游应能从 traceparent 提取上下文")
  }
}

///|
/// 非法 traceparent 下游返回 None。
test "run_downstream returns none on malformed traceparent" {
  assert_true(run_downstream("not-a-traceparent") is None)
}
