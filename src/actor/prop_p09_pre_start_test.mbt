// prop_p09_pre_start_test.mbt —— Property 9：pre_start 至多一次且先于处理（任务 11.10）。
//
//   Feature: actor, Property 9: pre_start 至多一次且先于处理
//   ------------------------------------------------------------------
//   *对任意* 生命周期转换序列，每个 actor 的 pre_start 至多被调用一次，且其调用
//   先于该 actor 的任何消息处理。
//
// **Validates: Requirements 3.1, 3.7**

///|
/// 单次场景：pre_start 给初始状态打基底标记 1000，处理消息累加；处理任意条消息后
/// pre_start 恰被调用一次（计数器为 1），且状态含基底（说明 pre_start 先于处理）。
fn p09_pre_start(rng : @infra_pbt.Rng) -> Bool {
  let calls : Array[Int] = []
  let hooks : LifecycleHooks[Int] = LifecycleHooks::new(
    fn(s) {
      calls.push(1)
      s + 1000
    },
    fn(_s) {  },
    fn(_s, _r) {  },
    fn(s) { s },
  )
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let a = sys.spawn(0, Behavior::new(fn(_c, s, m) { Updated(s + m) }), hooks~)
  let n = rng.next_range(0, 8)
  let mut sum = 0
  for _i in 0..<n {
    let v = rng.next_range(1, 10)
    sum = sum + v
    a.send(v)
  }
  sys.run_until_idle()
  if n == 0 {
    // 无消息：pre_start 懒调用未触发（至多一次 → 0 次合法）。
    return calls.length() <= 1
  }
  // 有消息：pre_start 恰一次，且状态 = 1000(基底) + sum（先于处理生效）。
  if calls.length() != 1 {
    return false
  }
  sys.state_of(a) == Some(1000 + sum)
}

///|
/// Feature: actor, Property 9: pre_start 至多一次且先于处理（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 3.1, 3.7**
test "Feature: actor, Property 9: pre_start runs at most once before any message (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p09_pre_start(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
