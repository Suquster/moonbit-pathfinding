// prop_fifo_test.mbt —— 串行与 FIFO 顺序不变量属性测试（task 16.3）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// 一条不变量，复用共享 PBT 包 @infra_pbt 的种子驱动随机源 `Rng` 与不变量断言
// 模板 `holds_for_all`（默认迭代 100 次，满足 ≥100 迭代基线，三后端逐位一致、
// 可重放）。
//
//   Feature: moonbit-infra-suite, Property 22: Actor 串行与 FIFO 顺序不变量
//   --------------------------------------------------------------------
//   *对任意* 单一发送者向单一 actor 投递的消息序列：actor 一次仅处理一条消息
//   （串行不变量），且严格按投递顺序处理这些消息（FIFO 不变量）。
//   （Requirement 10.3 / 10.4）
//
// **Validates: Requirements 10.3, 10.4**
//
// 建模方式（与 16.2 调度模型一致）：以 `Scheduler[Array[Int], Int]` 承载确定性
// 串行调度。处理函数把每条消息 append 到状态数组：
//   * FIFO 视角 —— 全部投递完毕并 `run_until_idle` 后，actor 的状态数组应逐位
//     等于「投递顺序」本身（消息既未丢失、未重排、未重复）；
//   * 串行视角 —— 逐次 `step` 时，每一步恰好处理一条消息：状态数组长度每步加一，
//     新追加元素恰为当前 FIFO 队首消息，且任一中间时刻状态数组都等于投递序列的
//     一个前缀。
//
// 命名约定：本文件所有本地辅助使用独立前缀 `ff_` / `gen_ff_` / `prop_ff_`，
// 与同包既有测试互不冲突。

// ---------------------------------------------------------------------------
// 生成器（generator）—— 随机长度的消息序列
// ---------------------------------------------------------------------------

///|
/// 随机消息序列生成器：产出长度 0~12 的 `Array[Int]`，元素取值于 [-100, 100]。
///
/// 刻意允许长度为 0（空序列边界）与元素重复——逐位（positional）比较使「重排 /
/// 丢失 / 重复」在含重复值的序列上同样可被检测。
fn gen_ff_messages(rng : @infra_pbt.Rng) -> Array[Int] {
  let n = rng.next_range(0, 12)
  let msgs : Array[Int] = []
  for _i in 0..<n {
    msgs.push(rng.next_range(-100, 100))
  }
  msgs
}

///|
/// 逐位比较两个 `Array[Int]` 是否相等（长度相同且对应元素相等）。
fn ff_int_arrays_eq(xs : Array[Int], ys : Array[Int]) -> Bool {
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
// Property 22：FIFO 顺序不变量 —— 谓词实现
// ---------------------------------------------------------------------------

///|
/// 单次场景：单一发送者向单一 actor 顺序投递整条消息序列，`run_until_idle` 后
/// actor 状态数组应逐位等于投递顺序（FIFO：未丢失、未重排、未重复）。
fn prop_ff_fifo_order(rng : @infra_pbt.Rng) -> Bool {
  let msgs = gen_ff_messages(rng)
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  // 处理函数把每条消息 append 到状态数组，从而状态数组即为「处理顺序」。
  let a = sched.spawn([], fn(s, m) {
    s.push(m)
    Updated(s)
  })
  // 单一发送者按投递顺序送出全部消息。
  for i in 0..<msgs.length() {
    a.send(msgs[i])
  }
  sched.run_until_idle()
  // 处理顺序应逐位等于投递顺序（FIFO）。
  match sched.state_of(a) {
    Some(processed) => if !ff_int_arrays_eq(processed, msgs) { return false }
    None => return false
  }
  // 全部消息均已处理（邮箱清空），且 actor 仍在运行（无错误终止）。
  if sched.pending(a) != 0 {
    return false
  }
  sched.is_running(a)
}

// ---------------------------------------------------------------------------
// Property 22：串行处理不变量 —— 谓词实现
// ---------------------------------------------------------------------------

///|
/// 单次场景：投递整条消息序列后逐次 `step`，断言每一步恰好处理一条消息
/// （串行不变量），且任一中间时刻状态数组都等于投递序列的一个前缀（FIFO）。
fn prop_ff_serial_one_at_a_time(rng : @infra_pbt.Rng) -> Bool {
  let msgs = gen_ff_messages(rng)
  let n = msgs.length()
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  let a = sched.spawn([], fn(s, m) {
    s.push(m)
    Updated(s)
  })
  for i in 0..<n {
    a.send(msgs[i])
  }
  // 逐步推进：第 i 步（0-based）应恰好处理第 i 条消息。
  for i in 0..<n {
    // 步前：尚有 n - i 条待处理。
    if sched.pending(a) != n - i {
      return false
    }
    let did = sched.step()
    // 有待处理消息时，step 必然有进展（处理了一条）。
    if !did {
      return false
    }
    // 步后：恰处理一条 —— 待处理数减一。
    if sched.pending(a) != n - i - 1 {
      return false
    }
    // 步后状态应等于投递序列长度为 i+1 的前缀（串行 + FIFO）。
    let expected_prefix : Array[Int] = []
    for k in 0..<=i {
      expected_prefix.push(msgs[k])
    }
    match sched.state_of(a) {
      Some(processed) =>
        if !ff_int_arrays_eq(processed, expected_prefix) {
          return false
        }
      None => return false
    }
  }
  // 全部处理完毕后再 step 应为空闲（不会无中生有地处理消息）。
  if sched.step() {
    return false
  }
  // 终态：状态数组逐位等于完整投递序列。
  match sched.state_of(a) {
    Some(processed) => ff_int_arrays_eq(processed, msgs)
    None => false
  }
}

// ---------------------------------------------------------------------------
// 单元测试（具体见证）—— 锁定代表性场景
// ---------------------------------------------------------------------------

///|
/// Property 22 的具体见证（FIFO）：顺序投递 [3, 1, 4, 1, 5, 9] 后，处理顺序与
/// 投递顺序逐位一致（含重复元素 1）。
test "single actor processes a delivered sequence in fifo order (witness)" {
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  let a = sched.spawn([], fn(s, m) {
    s.push(m)
    Updated(s)
  })
  let msgs = [3, 1, 4, 1, 5, 9]
  for i in 0..<msgs.length() {
    a.send(msgs[i])
  }
  sched.run_until_idle()
  @test.assert_eq(sched.state_of(a), Some([3, 1, 4, 1, 5, 9]))
  @test.assert_eq(sched.pending(a), 0)
  assert_true(sched.is_running(a))
}

///|
/// Property 22 的具体见证（串行）：投递三条消息后逐步 step，每步恰处理一条，
/// 中间状态严格为投递序列的前缀。
test "single actor processes exactly one message per step (witness)" {
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  let a = sched.spawn([], fn(s, m) {
    s.push(m)
    Updated(s)
  })
  a.send(7)
  a.send(8)
  a.send(9)
  @test.assert_eq(sched.pending(a), 3)
  let _ = sched.step()
  @test.assert_eq(sched.state_of(a), Some([7]))
  @test.assert_eq(sched.pending(a), 2)
  let _ = sched.step()
  @test.assert_eq(sched.state_of(a), Some([7, 8]))
  @test.assert_eq(sched.pending(a), 1)
  let _ = sched.step()
  @test.assert_eq(sched.state_of(a), Some([7, 8, 9]))
  @test.assert_eq(sched.pending(a), 0)
  // 已空闲：再 step 无进展。
  assert_false(sched.step())
}

// ---------------------------------------------------------------------------
// Property 22：Actor 串行与 FIFO 顺序不变量（holds_for_all 模板，≥100 迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 22: Actor 串行与 FIFO 顺序不变量（FIFO 顺序）
///
/// 对任意单一发送者投递的随机消息序列，actor 严格按投递顺序处理这些消息：
/// `run_until_idle` 后其状态数组逐位等于投递顺序。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，默认迭代 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 10.3, 10.4**
test "Feature: moonbit-infra-suite, Property 22: single sender messages are processed in fifo order (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { prop_ff_fifo_order(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// Feature: moonbit-infra-suite, Property 22: Actor 串行与 FIFO 顺序不变量（串行处理）
///
/// 对任意单一发送者投递的随机消息序列，actor 一次仅处理一条消息：逐步 `step`
/// 时每步恰处理一条，任一中间时刻状态数组都等于投递序列的一个前缀。复用
/// @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 10.3, 10.4**
test "Feature: moonbit-infra-suite, Property 22: actor processes exactly one message per step (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { prop_ff_serial_one_at_a_time(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
