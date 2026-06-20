// task_body_test.mbt —— 可执行任务体的内联烟雾测试（任务 9.1）。
//
// 完整的确定性可复现属性测试（相同 seed + 相同任务集 → 逐事件相同轨迹）属
// 任务 9.3，此处仅做两项最小冒烟验证：
//   (1) 单任务执行产出确定的事件轨迹（含发送物化为 EvSend + EvDeliver）；
//   (2) 两次 run_executable 在相同输入下产出逐事件相等的轨迹。

///|
/// 单任务体执行：追加一条日志并发送一条消息，校验产出轨迹形态确定。
test "run_executable 单任务确定性轨迹" {
  let t = ExecutableTask::new(1, "leader", fn(ctx) {
    ctx.append(value=42)
    ctx.send(to=2, payload=7, after=3UL)
    TDone
  })
  let trace = run_executable(123UL, [t], max_steps=8)
  // 期望：EvScheduled → EvSend → EvDeliver → EvCompleted。
  assert_true(trace.length() == 4)
  assert_true(trace[0] is EvScheduled(time=1UL, task_id=1))
  assert_true(trace[1] is EvSend(time=1UL, from=1, to=2, ..))
  assert_true(trace[2] is EvDeliver(time=4UL, from=1, to=2, ..))
  assert_true(trace[3] is EvCompleted(time=1UL, task_id=1))
}

///|
/// 相同 seed + 相同任务集 → 两次执行逐事件相等（确定性可复现的冒烟版）。
test "run_executable 两次执行相等" {
  let mk = fn() -> Array[ExecutableTask] {
    [
      ExecutableTask::new(2, "b", fn(ctx) {
        ctx.send(to=1, payload=5, after=1UL)
        TDone
      }),
      ExecutableTask::new(1, "a", fn(ctx) {
        ctx.append(value=9)
        TDone
      }),
      ExecutableTask::new(3, "c", fn(_ctx) { TDone }),
    ]
  }
  let a = run_executable(999UL, mk(), max_steps=16)
  let b = run_executable(999UL, mk(), max_steps=16)
  assert_true(a == b)
}
