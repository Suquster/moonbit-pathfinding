// prop_isolation_test.mbt —— 错误隔离不变量属性测试（task 16.4）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// 一条不变量，复用共享 PBT 包 @infra_pbt 的种子驱动随机源 `Rng` 与不变量断言
// 模板 `holds_for_all`（默认迭代 100 次，满足 ≥100 迭代基线，三后端逐位一致、
// 可重放）。
//
//   Feature: moonbit-infra-suite, Property 23: Actor 错误隔离不变量
//   --------------------------------------------------------------------
//   *对任意* 在处理消息期间抛出未捕获错误的 actor，框架应终止该 actor 并通知其
//   监督者（supervisor），且不影响其他 actor 的运行。
//   （Requirement 10.6）
//
// **Validates: Requirements 10.6**
//
// 建模方式（与 16.2 调度模型一致）：在同一 `Scheduler[Array[Int], Int]` 上随机
// 构造两个 actor——
//   * 崩溃 actor（bad）：处理函数对负值消息返回 `Errored`（一次未捕获错误信号），
//     对非负消息正常 append；其投递序列由「若干非负正常消息 + 在随机位置插入的
//     毒丸消息 -1」构成，因而必然在该毒丸处崩溃；
//   * 正常 actor（good）：处理函数对任意消息均 append，永不崩溃。
// 断言（错误隔离不变量）：
//   1. 崩溃 actor 终态为 `Failed`，supervisor 恰被通知一次且携带其 actor id；
//   2. 崩溃 actor 仅处理了毒丸之前的正常消息（崩溃后残留消息被丢弃，pending 归零）；
//   3. 正常 actor 不受影响——仍 `Running`，且逐位完整处理其全部投递消息。
//
// 命名约定：本文件所有本地辅助使用独立前缀 `iso_` / `gen_iso_` / `prop_iso_`，
// 与同包既有测试互不冲突。

// ---------------------------------------------------------------------------
// 随机场景（generator）—— 两个 actor 的投递序列 + 随机崩溃位置
// ---------------------------------------------------------------------------

///|
/// 错误隔离测试的单次随机场景（isolation case）。
///
///   * `good_msgs`   —— 正常 actor 的投递序列（值域 [-100, 100]，永不触发崩溃）；
///   * `bad_normal`  —— 崩溃 actor 在崩溃前的非负正常消息（值域 [0, 100]）；
///   * `crash_at`    —— 毒丸消息 -1 在 `bad_normal` 中的插入位置 [0, len]，
///                       即崩溃 actor 在处理完前 `crash_at` 条正常消息后崩溃。
struct IsoCase {
  good_msgs : Array[Int]
  bad_normal : Array[Int]
  crash_at : Int
}

///|
/// 随机场景生成器：good 序列长 0~12、bad 正常前缀长 0~10，崩溃位置随机。
fn gen_iso_case(rng : @infra_pbt.Rng) -> IsoCase {
  let n_good = rng.next_range(0, 12)
  let good_msgs : Array[Int] = []
  for _i in 0..<n_good {
    good_msgs.push(rng.next_range(-100, 100))
  }
  let n_bad = rng.next_range(0, 10)
  let bad_normal : Array[Int] = []
  for _i in 0..<n_bad {
    // 非负，确保正常消息不会被误判为崩溃信号。
    bad_normal.push(rng.next_range(0, 100))
  }
  // 崩溃位置含端点：0 表示立即崩溃，n_bad 表示处理完全部正常消息后崩溃。
  let crash_at = rng.next_range(0, n_bad)
  { good_msgs, bad_normal, crash_at }
}

///|
/// 逐位比较两个 `Array[Int]` 是否相等（长度相同且对应元素相等）。
fn iso_int_arrays_eq(xs : Array[Int], ys : Array[Int]) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  for i in 0..<xs.length() {
    if xs[i] != ys[i] {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Property 23：错误隔离不变量 —— 谓词实现
// ---------------------------------------------------------------------------

///|
/// 单次场景：崩溃 actor 在毒丸处被终止并通知 supervisor、其残留消息被丢弃，
/// 而正常 actor 完整处理其全部消息、运行不受影响（错误隔离）。
fn prop_iso_error_isolation(rng : @infra_pbt.Rng) -> Bool {
  let c = gen_iso_case(rng)
  // supervisor 通知收集（闭包按引用捕获）。
  let notices : Array[(Int, String)] = []
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  // 崩溃 actor：负值消息触发一次未捕获错误信号，非负消息正常 append。
  let bad = sched.spawn(
    [],
    fn(s, m) {
      if m < 0 {
        Errored("boom")
      } else {
        s.push(m)
        Updated(s)
      }
    },
    supervisor=fn(id, reason) { notices.push((id.value, reason)) },
  )
  // 正常 actor：任意消息均 append，永不崩溃。
  let good = sched.spawn([], fn(s, m) {
    s.push(m)
    Updated(s)
  })
  // 构造崩溃 actor 的投递序列：前 crash_at 条正常消息 + 毒丸 -1 + 其余正常消息。
  for i in 0..<c.crash_at {
    bad.send(c.bad_normal[i])
  }
  bad.send(-1)
  for i in c.crash_at..<c.bad_normal.length() {
    bad.send(c.bad_normal[i])
  }
  // 正常 actor 投递其全部消息。
  for i in 0..<c.good_msgs.length() {
    good.send(c.good_msgs[i])
  }
  sched.run_until_idle()

  // (1) 崩溃 actor 终态为 Failed，且不再运行。
  match sched.status_of(bad) {
    Some(Failed(reason)) => if reason != "boom" { return false }
    _ => return false
  }
  if sched.is_running(bad) {
    return false
  }
  // (2) 崩溃 actor 仅处理了毒丸之前的正常消息；残留消息被丢弃（pending 归零）。
  let expected_bad : Array[Int] = []
  for i in 0..<c.crash_at {
    expected_bad.push(c.bad_normal[i])
  }
  match sched.state_of(bad) {
    Some(processed) =>
      if !iso_int_arrays_eq(processed, expected_bad) {
        return false
      }
    None => return false
  }
  if sched.pending(bad) != 0 {
    return false
  }
  // (3) supervisor 恰被通知一次，且携带崩溃 actor 的正确 id 与错误描述。
  if notices.length() != 1 {
    return false
  }
  if notices[0].0 != bad.id.value || notices[0].1 != "boom" {
    return false
  }
  // (4) 错误隔离：正常 actor 不受影响——仍运行、完整处理全部消息、邮箱清空。
  if !sched.is_running(good) {
    return false
  }
  if sched.pending(good) != 0 {
    return false
  }
  match sched.state_of(good) {
    Some(processed) => iso_int_arrays_eq(processed, c.good_msgs)
    None => false
  }
}

// ---------------------------------------------------------------------------
// 单元测试（具体见证）—— 锁定代表性场景
// ---------------------------------------------------------------------------

///|
/// Property 23 的具体见证：崩溃 actor 处理 [5, 7] 后遇 -1 崩溃，残留 [9] 被丢弃，
/// supervisor 恰被通知一次；正常 actor 不受影响，完整处理 [1, 2, 3]。
test "uncaught error isolates the failed actor while others keep running (witness)" {
  let notices : Array[(Int, String)] = []
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  let bad = sched.spawn(
    [],
    fn(s, m) {
      if m < 0 {
        Errored("boom")
      } else {
        s.push(m)
        Updated(s)
      }
    },
    supervisor=fn(id, reason) { notices.push((id.value, reason)) },
  )
  let good = sched.spawn([], fn(s, m) {
    s.push(m)
    Updated(s)
  })
  bad.send(5)
  bad.send(7)
  bad.send(-1)
  bad.send(9)
  good.send(1)
  good.send(2)
  good.send(3)
  sched.run_until_idle()
  // 崩溃 actor 被隔离终止。
  @test.assert_eq(sched.status_of(bad), Some(Failed("boom")))
  @test.assert_eq(sched.state_of(bad), Some([5, 7]))
  @test.assert_eq(sched.pending(bad), 0)
  assert_false(sched.is_running(bad))
  // supervisor 恰好收到一次通知。
  @test.assert_eq(notices.length(), 1)
  @test.assert_eq(notices[0], (bad.id.value, "boom"))
  // 正常 actor 不受影响，完整处理其全部消息。
  assert_true(sched.is_running(good))
  @test.assert_eq(sched.state_of(good), Some([1, 2, 3]))
  @test.assert_eq(sched.pending(good), 0)
}

///|
/// Property 23 的具体见证（立即崩溃）：崩溃 actor 第一条即毒丸，状态保持初始空，
/// 仍通知 supervisor 一次；正常 actor 照常完整处理。
test "actor crashing on its first message is isolated (witness)" {
  let notices : Array[(Int, String)] = []
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  let bad = sched.spawn(
    [],
    fn(s, m) {
      if m < 0 {
        Errored("boom")
      } else {
        s.push(m)
        Updated(s)
      }
    },
    supervisor=fn(id, reason) { notices.push((id.value, reason)) },
  )
  let good = sched.spawn([], fn(s, m) {
    s.push(m)
    Updated(s)
  })
  bad.send(-1)
  good.send(42)
  sched.run_until_idle()
  @test.assert_eq(sched.status_of(bad), Some(Failed("boom")))
  @test.assert_eq(sched.state_of(bad), Some([]))
  @test.assert_eq(notices.length(), 1)
  assert_true(sched.is_running(good))
  @test.assert_eq(sched.state_of(good), Some([42]))
}

// ---------------------------------------------------------------------------
// Property 23：Actor 错误隔离不变量（holds_for_all 模板，≥100 迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 23: Actor 错误隔离不变量
///
/// 对任意在处理消息期间抛出未捕获错误的 actor，框架终止该 actor（`Failed`）并
/// 通知其 supervisor 恰一次，且不影响其他 actor——正常 actor 仍 `Running` 并完整
/// 处理其全部消息。复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100
/// 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 10.6**
test "Feature: moonbit-infra-suite, Property 23: uncaught error terminates the actor and notifies supervisor while isolating others (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { prop_iso_error_isolation(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
