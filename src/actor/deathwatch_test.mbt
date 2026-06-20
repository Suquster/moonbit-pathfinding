// deathwatch_test.mbt —— 监视注册表单元测试（任务 7.2）。
//
// 覆盖：登记/撤销、重复登记幂等见证（投递语义属性见任务 11）。
// _Requirements: 7.1, 7.3_

///|
/// 登记后 active_count 增加；collect_terminations 收集监视者并置非 active。
test "watch registers and collect_terminations delivers once" {
  let reg : WatchRegistry[Int] = WatchRegistry::new()
  let watcher : ActorId = { value: 1 }
  let target : ActorId = { value: 2 }
  reg.watch(watcher, target, fn(id, _reason) { id.value * 100 })
  assert_eq(reg.active_count(), 1)
  let delivered = reg.collect_terminations(target, StoppedNormally)
  assert_eq(delivered.length(), 1)
  assert_eq(delivered[0].0, watcher)
  assert_eq(delivered[0].1, 200)
  // 收集后置非 active：再次收集不再投递（至多一条）。
  assert_eq(reg.active_count(), 0)
  assert_eq(reg.collect_terminations(target, StoppedNormally).length(), 0)
}

///|
/// 重复登记幂等：同一 (watcher, target) 不产生重复条目。
test "watch is idempotent for the same watcher-target pair" {
  let reg : WatchRegistry[Int] = WatchRegistry::new()
  let watcher : ActorId = { value: 1 }
  let target : ActorId = { value: 2 }
  reg.watch(watcher, target, fn(_id, _r) { 0 })
  reg.watch(watcher, target, fn(_id, _r) { 0 })
  assert_eq(reg.active_count(), 1)
}

///|
/// unwatch 后该监视不再投递。
test "unwatch cancels the watch" {
  let reg : WatchRegistry[Int] = WatchRegistry::new()
  let watcher : ActorId = { value: 1 }
  let target : ActorId = { value: 2 }
  reg.watch(watcher, target, fn(_id, _r) { 9 })
  reg.unwatch(watcher, target)
  assert_eq(reg.active_count(), 0)
  assert_eq(reg.collect_terminations(target, FailedWith("x")).length(), 0)
}
