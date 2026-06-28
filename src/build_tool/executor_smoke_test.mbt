// executor_smoke_test.mbt —— Executor 框架烟雾测试（任务 4.1）。
//
// 仅做最小行为冒烟校验，确保框架可编译且核心语义正确；完整属性测试见任务 4.2。

///|
/// 构造一个动作的便捷助手（测试用）。
fn mk_action(
  id : String,
  inputs : Array[String],
  outputs : Array[String],
  command : String,
) -> Action {
  { id, inputs, outputs, command }
}

///|
/// AC1 + AC5/AC6：指纹确定且对字段敏感；BuildLog 记录后同动作 up-to-date。
test "action fingerprint is deterministic and field-sensitive" {
  let a = mk_action("c", ["a.c"], ["a.o"], "cc -c a.c")
  let b = mk_action("c", ["a.c"], ["a.o"], "cc -c a.c")
  // 相同动作 → 相同指纹。
  @test.assert_eq(a.fingerprint(), b.fingerprint())
  // 命令不同 → 指纹不同。
  let c = mk_action("c", ["a.c"], ["a.o"], "cc -O2 -c a.c")
  assert_true(a.fingerprint() != c.fingerprint())
  // BuildLog 记录后 up-to-date；未记录的动作不 up-to-date。
  let log = BuildLog::new()
  assert_false(log.is_up_to_date(a))
  log.record(a, Executed(output_hash="h"))
  assert_true(log.is_up_to_date(a))
  assert_false(log.is_up_to_date(c))
}

///|
/// AC2：DryRunExecutor 仅记录动作并返回 Skipped，无外部副作用。
test "dry-run executor records actions and skips" {
  let dry = DryRunExecutor::new()
  let a = mk_action("t", [], ["t.o"], "build t")
  let r = dry.execute(a)
  @test.assert_eq(r, Skipped)
  @test.assert_eq(dry.recorded().length(), 1)
}

///|
/// AC3：CallbackExecutor 以回调返回值作为 output_hash 产出 Executed。
test "callback executor uses callback output hash" {
  let exec = CallbackExecutor::new(fn(action) { "out:" + action.id })
  let r = exec.execute(mk_action("x", [], ["x.o"], "cmd"))
  @test.assert_eq(r, Executed(output_hash="out:x"))
}

///|
/// AC4/AC7：并行分层——依赖在前、被依赖在后；全波次展开为全部动作各一次。
test "parallel schedule layers by dependency, no dup or miss" {
  // a -> b, a -> c, b -> d, c -> d：期望 [[a], [b, c], [d]]。
  let a = mk_action("a", [], ["a.o"], "ca")
  let b = mk_action("b", ["a.o"], ["b.o"], "cb")
  let c = mk_action("c", ["a.o"], ["c.o"], "cc")
  let d = mk_action("d", ["b.o", "c.o"], ["d.o"], "cd")
  let sched = build_parallel_schedule([a, b, c, d], [
    ("a", "b"),
    ("a", "c"),
    ("b", "d"),
    ("c", "d"),
  ])
  // 展开全部动作 id，校验不重不漏。
  let seen : Array[String] = []
  for wave in sched.waves {
    for act in wave {
      seen.push(act.id)
    }
  }
  seen.sort()
  // 比较以 join 后的字符串进行（String 的相等断言不触发 Array Show 弃用告警），
  // 语义等价于逐元素比较有序的动作 id 序列。
  @test.assert_eq(seen.join(","), "a,b,c,d")
  // 首波仅含无依赖的 a；末波仅含 d。
  @test.assert_eq(sched.waves[0].length(), 1)
  @test.assert_eq(sched.waves[0][0].id, "a")
  let last = sched.waves[sched.waves.length() - 1]
  @test.assert_eq(last.length(), 1)
  @test.assert_eq(last[0].id, "d")
}

///|
/// run_actions：首次全部执行；再次运行（指纹未变）全部增量跳过。
test "run_actions executes then incrementally skips" {
  let a = mk_action("a", [], ["a.o"], "ca")
  let b = mk_action("b", ["a.o"], ["b.o"], "cb")
  let sched = build_parallel_schedule([a, b], [("a", "b")])
  let mut calls = 0
  let exec = CallbackExecutor::new(fn(action) {
    calls = calls + 1
    "h:" + action.id
  })
  let log = run_actions(sched, exec as &Executor, BuildLog::new())
  @test.assert_eq(calls, 2)
  assert_true(log.is_up_to_date(a))
  assert_true(log.is_up_to_date(b))
  // 再次运行：指纹未变，全部跳过，回调不再触发。
  let _ = run_actions(sched, exec as &Executor, log)
  @test.assert_eq(calls, 2)
}
