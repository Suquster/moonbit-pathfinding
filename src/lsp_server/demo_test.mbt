// demo_test.mbt —— 端到端会话 demo 单元测试（任务 16.2）。
//
// 针对 demo.mbt 的 `run_session_demo()`（旁路新增的端到端会话脚本），覆盖
// Requirement 9.2（确定性）与 Requirement 9.3（增量后诊断 == 全量替换诊断）的
// **具体见证**：
//   * 确定性（R9.2）：两次独立调用 `run_session_demo()` 产出逐位相等的
//     `Array[SessionStep]`（`SessionStep` 派生 Eq/Show）。
//   * 步骤序列：步骤数量与标签序列固定为 initialize → initialized → didOpen →
//     didChange → diagnostics → completion → definition → references → rename →
//     hover → shutdown → exit。
//   * 增量 = 全量（R9.3）：didChange 步骤输出报告
//     incrementalEqualsFullText=true 且 incrementalEqualsFullDiagnostics=true。
//   * 关键见证：shutdown 结果为 null、exit 退出码为 0（已收到 shutdown）。
//
// 断言策略：复合等值统一走派生 `Eq`（`assert_true(a == b)`），保持本包零告警约定。

// ───────────────────────────── 测试辅助 ───────────────────────────────

///|
/// 在步骤序列中按标签查找首个匹配步骤的输出；缺失时 `fail`。
fn demo_test_output_of(
  steps : Array[SessionStep],
  label : String,
) -> @lsp_binding.Json {
  for s in steps {
    if s.label == label {
      return s.output
    }
  }
  abort("expected a session step labeled " + label)
}

///|
/// 从 JSON 对象中按 key 取出布尔字段；缺失 / 类型不符返回 `false`。
fn demo_test_bool_field(json : @lsp_binding.Json, key : String) -> Bool {
  match json {
    @lsp_binding.JObj(fields) => {
      for kv in fields {
        if kv.0 == key {
          match kv.1 {
            @lsp_binding.JBool(b) => return b
            _ => return false
          }
        }
      }
      false
    }
    _ => false
  }
}

///|
/// 从 JSON 对象中按 key 取出字段的 JSON 值；缺失返回 `JNull`。
fn demo_test_field(json : @lsp_binding.Json, key : String) -> @lsp_binding.Json {
  match json {
    @lsp_binding.JObj(fields) => {
      for kv in fields {
        if kv.0 == key {
          return kv.1
        }
      }
      @lsp_binding.JNull
    }
    _ => @lsp_binding.JNull
  }
}

// ───────────────────────────── R9.2 确定性 ────────────────────────────

///|
/// 两次独立调用 `run_session_demo()` 产出逐位相等的步骤序列（确定性，R9.2）。
test "run_session_demo: two runs produce identical step sequences (determinism)" {
  let first = run_session_demo()
  let second = run_session_demo()
  // `Array[SessionStep]` 经 SessionStep 派生 Eq 逐元素比较。
  assert_true(first == second)
}

// ───────────────────────────── 步骤数量与标签序列 ─────────────────────

///|
/// 步骤数量与标签序列固定（确定性脚本的结构见证）。
test "run_session_demo: step count and label sequence are fixed" {
  let steps = run_session_demo()
  let labels : Array[String] = []
  for s in steps {
    labels.push(s.label)
  }
  let expected : Array[String] = [
    "initialize", "initialized", "didOpen", "didChange", "diagnostics", "completion",
    "definition", "references", "rename", "hover", "shutdown", "exit",
  ]
  assert_eq(steps.length(), 12)
  assert_true(labels == expected)
}

// ───────────────────────────── R9.3 增量 = 全量 ───────────────────────

///|
/// didChange 步骤报告增量文本/诊断与全量替换逐条相等（R9.3）。脚本内部已用
/// `guard ... else { abort(..) }` 强制该不变量，此处对其外化见证作单元断言。
test "run_session_demo: didChange reports incremental equals full replacement" {
  let steps = run_session_demo()
  let did_change = demo_test_output_of(steps, "didChange")
  // incrementalEqualsFullText=true（变更后文本逐字符等于全量替换文本）。
  assert_true(demo_test_bool_field(did_change, "incrementalEqualsFullText"))
  // incrementalEqualsFullDiagnostics=true（二者诊断逐条相等）。
  assert_true(
    demo_test_bool_field(did_change, "incrementalEqualsFullDiagnostics"),
  )
}

// ───────────────────────────── 关键步骤见证 ───────────────────────────

///|
/// shutdown 结果为 null（任务 5 生命周期：shutdown 成功响应 result=null）。
test "run_session_demo: shutdown step result is null" {
  let steps = run_session_demo()
  let shutdown = demo_test_output_of(steps, "shutdown")
  assert_true(shutdown == @lsp_binding.JNull)
}

///|
/// exit 退出码为 0（已收到 shutdown → 干净退出，R1.6 投影）。`exitCode` 字段经
/// `demo_jint` 编码为 `JNum("0")`。
test "run_session_demo: exit step reports exit code 0 after shutdown" {
  let steps = run_session_demo()
  let exit = demo_test_output_of(steps, "exit")
  assert_true(demo_test_field(exit, "exitCode") == @lsp_binding.JNum("0"))
}
