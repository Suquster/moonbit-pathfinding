// linearizability_test.mbt —— 线性一致性检查单元测试（任务 14.2）。
//
// 覆盖一个可线性化历史返回 Linearizable、一个违反顺序规约历史返回 NotLinearizable
// 且 conflict 非空的见证（R7.4 / R7.5）。

///|
/// 顺序历史 put 5 后 get 5：可线性化。
test "is_linearizable accepts a sequential consistent history" {
  let model : RegisterModel = { init: 0 }
  let h : Array[OpEvent] = [
    OpEvent::invoke(0, "put", 5, 0UL),
    OpEvent::ret(0, "put", 0, 1UL),
    OpEvent::invoke(0, "get", 0, 2UL),
    OpEvent::ret(0, "get", 5, 3UL),
  ]
  match is_linearizable(h, model) {
    Linearizable => ()
    NotLinearizable(..) => fail("expected Linearizable")
  }
}

///|
/// put 5 后 get 读到 9（≠5）且实时晚于 put：不可线性化，conflict 非空。
test "is_linearizable rejects an inconsistent history with conflict" {
  let model : RegisterModel = { init: 0 }
  let h : Array[OpEvent] = [
    OpEvent::invoke(0, "put", 5, 0UL),
    OpEvent::ret(0, "put", 0, 1UL),
    OpEvent::invoke(0, "get", 0, 2UL),
    OpEvent::ret(0, "get", 9, 3UL),
  ]
  match is_linearizable(h, model) {
    NotLinearizable(conflict~) => assert_true(conflict.length() > 0)
    Linearizable => fail("expected NotLinearizable")
  }
}
