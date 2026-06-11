// direction_proofs_test.mbt —— 各方向 `{方向}_proof.mbt` 占位谓词的运行期测试。
//
// 验证占位谓词可编译、可被运行期测试调用，并在最小正反例上行为正确，
// 为后续各方向独立子 spec 升级到真实类型谓词时提供安全网。

// --- Regex_Engine ---

///|
test "nfa_dfa_consistent true when results agree" {
  inspect(nfa_dfa_consistent(true, true), content="true")
  inspect(nfa_dfa_consistent(false, false), content="true")
}

///|
test "nfa_dfa_consistent false when results disagree" {
  inspect(nfa_dfa_consistent(true, false), content="false")
}

// --- Mini_Compiler ---

///|
test "scope_binding_consistent true when all used names bound" {
  let r = scope_binding_consistent(["x", "y", "z"], ["x", "z"])
  inspect(r, content="true")
}

///|
test "scope_binding_consistent false for free variable" {
  let r = scope_binding_consistent(["x"], ["x", "y"])
  inspect(r, content="false")
}

// --- Parser_Combinator ---

///|
test "fail_does_not_consume true when failure keeps position" {
  inspect(fail_does_not_consume(false, 3, 3), content="true")
}

///|
test "fail_does_not_consume false when failure advanced position" {
  inspect(fail_does_not_consume(false, 3, 5), content="false")
}

///|
test "fail_does_not_consume true on success regardless of position" {
  inspect(fail_does_not_consume(true, 3, 5), content="true")
}

// --- Codegen_Infra ---

///|
test "ssa_single_assignment_counts true when each var defined once" {
  inspect(ssa_single_assignment_counts([1, 1, 1]), content="true")
}

///|
test "ssa_single_assignment_counts false on redefinition" {
  inspect(ssa_single_assignment_counts([1, 2, 1]), content="false")
}

///|
test "interference_distinct true when adjacent colors differ" {
  inspect(interference_distinct([(0, 1), (1, 2)]), content="true")
}

///|
test "interference_distinct false when adjacent colors equal" {
  inspect(interference_distinct([(0, 1), (2, 2)]), content="false")
}

// --- Serialization ---

///|
test "decode_failure_no_partial true on success" {
  inspect(decode_failure_no_partial(true, true), content="true")
}

///|
test "decode_failure_no_partial true on clean failure" {
  inspect(decode_failure_no_partial(false, false), content="true")
}

///|
test "decode_failure_no_partial false on partial object after failure" {
  inspect(decode_failure_no_partial(false, true), content="false")
}

// --- Logging_Library ---

///|
test "level_threshold_filter true when emission matches threshold" {
  inspect(level_threshold_filter(3, 2, true), content="true")
  inspect(level_threshold_filter(1, 2, false), content="true")
}

///|
test "level_threshold_filter false when below-threshold event emitted" {
  inspect(level_threshold_filter(1, 2, true), content="false")
}

// --- LSP_Binding / LSP_Server ---

///|
test "illegal_message_keeps_alive true for valid message" {
  inspect(illegal_message_keeps_alive(true, false, true), content="true")
}

///|
test "illegal_message_keeps_alive true when invalid but error responded" {
  inspect(illegal_message_keeps_alive(false, true, true), content="true")
}

///|
test "illegal_message_keeps_alive false when process terminated" {
  inspect(illegal_message_keeps_alive(false, true, false), content="false")
}

// --- DST_Framework ---

///|
test "deterministic_replay true for identical schedules" {
  inspect(deterministic_replay([0, 2, 1, 3], [0, 2, 1, 3]), content="true")
}

///|
test "deterministic_replay false for divergent schedules" {
  inspect(deterministic_replay([0, 1, 2], [0, 2, 1]), content="false")
}

// --- Actor_Framework ---

///|
test "fifo_order_preserved true when processed in send order" {
  inspect(fifo_order_preserved([1, 2, 3], [1, 2, 3]), content="true")
}

///|
test "fifo_order_preserved false when reordered" {
  inspect(fifo_order_preserved([1, 2, 3], [1, 3, 2]), content="false")
}

///|
test "error_isolation true when only crashed actor removed" {
  inspect(error_isolation([1, 2, 3], 2, [1, 3]), content="true")
}

///|
test "error_isolation false when surviving actor also affected" {
  inspect(error_isolation([1, 2, 3], 2, [1]), content="false")
}
