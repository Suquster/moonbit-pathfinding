// invariant_test.mbt —— 运行时不变量单元测试（任务 7.2）。
//
// 覆盖恒假不变量令运行以 `Failed` 终止、原因字符串标识被违反不变量名称与逻辑
// 时间戳的见证（R7.3）。

///|
/// 恒假不变量使运行失败，原因含不变量名与「逻辑时间」标识。
test "always-false invariant fails the run with name and timestamp" {
  let inv = Invariant::new("永假", fn(_w) { false })
  let sc = DesScenario::new([Task::new(0, "a")], [], [inv], null_protocol(), 16)
  let r = run_des(1, sc)
  match r.status {
    Failed(reason~) => {
      assert_true(tcontains(reason, "永假"))
      assert_true(tcontains(reason, "逻辑时间"))
    }
    Completed => fail("expected Failed due to violated invariant")
  }
}

///|
/// 恒真不变量不影响正常完成。
test "always-true invariant leaves run completed" {
  let inv = Invariant::new("永真", fn(_w) { true })
  let sc = DesScenario::new(
    [Task::new(0, "a"), Task::new(1, "b")],
    [],
    [inv],
    null_protocol(),
    16,
  )
  let r = run_des(2, sc)
  match r.status {
    Completed => ()
    Failed(reason~) => fail("expected Completed, got \{reason}")
  }
}
