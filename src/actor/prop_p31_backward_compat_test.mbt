// prop_p31_backward_compat_test.mbt —— Property 31：向后兼容（任务 15.2）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// 第 31 条不变量，复用共享 PBT 包 @infra_pbt 的种子驱动随机源 `Rng`、生成器
// `Gen` 与不变量断言模板 `holds_for_all`（默认迭代 100 次，满足 ≥100 迭代基线，
// 三后端逐位一致、可重放）。
//
//   Feature: actor, Property 31: 向后兼容
//   --------------------------------------------------------------------
//   *对任意* 仅使用既有 `Scheduler` API（`new`/`spawn`/`step`/`run_until_idle`/
//   `state_of`/`status_of`/`is_running`/`pending`）与 `ActorRef::send`/`stop` 的
//   随机消息/操作序列，`Scheduler[S, M]` 的处理结果（状态 / 生命周期状态 /
//   待处理条数 / 运行标志）与 `0.1.0` 骨架语义**逐字段一致**。
//
// **Validates: Requirements 14.3, 14.6**
//
// 既有核心语义（0.1.0 骨架，requirements R14.3）—— 本测试以一个**独立的纯参照
// 实现**复刻之，并与 `Scheduler` 逐字段比对：
//   * 邮箱 FIFO —— `send` 追加队尾，处理时从队首取出；
//   * 串行处理 —— 单 actor 一次仅处理一条消息（每次 `step` 至多处理一条）；
//   * 空邮箱挂起 —— 邮箱为空的 actor 被跳过，不消耗处理步；
//   * 未捕获错误终止该 actor —— 处理函数返回 `Errored` 时该 actor 置 `Failed`、
//     关闭并丢弃残留消息，且不影响其他 actor；
//   * `stop` 在处理完当前消息后停止 —— `stop` 关闭邮箱；后续调度扫描到该
//     「`Running` 且邮箱已关闭」的 actor 时将其置 `Stopped` 并丢弃残留消息。
//
// 参照实现刻意**不调用** `Scheduler`，而以独立的可变记录 + 朴素 fold over 操作
// 序列复刻 0.1.0 的 `step` 扫描算法（登记顺序扫描、关闭即停、空即跳过、首个可处理
// actor 取一条消息），从而成为 `Scheduler` 的独立预言（oracle）。
//
// 命名约定：本文件所有本地辅助使用独立前缀 `bc_` / `gen_bc_` / `prop_bc_`，
// 与同包既有测试互不冲突。

// ---------------------------------------------------------------------------
// 被测域（domain）—— 状态 Array[Int]、消息 Int
// ---------------------------------------------------------------------------
//
// 处理函数语义（与 0.1.0 骨架的串行处理一致）：
//   * 负值消息 → `Errored("boom")`（一次未捕获错误信号，触发终止与隔离）；
//   * 非负消息 → 追加到状态数组并 `Updated`。
// 该处理函数同时用于 `Scheduler` 与参照实现，确保两侧处理规则完全一致。

///|
/// 生命周期状态的参照编码（0=Running，1=Stopped，2=Failed）。
const BC_RUNNING : Int = 0

///|
const BC_STOPPED : Int = 1

///|
const BC_FAILED : Int = 2

// ---------------------------------------------------------------------------
// 独立参照实现（pure oracle）—— 复刻 0.1.0 骨架的串行调度语义
// ---------------------------------------------------------------------------

///|
/// 参照 actor 单元（reference cell）—— 不依赖 `Scheduler`，独立承载运行态。
struct BcCell {
  state : Array[Int]
  mailbox : Array[Int]
  mut closed : Bool
  mut status : Int
  mut reason : String
}

///|
/// 创建一个初始空的参照 actor 单元（`Running`、空邮箱、空状态）。
fn bc_cell_new() -> BcCell {
  { state: [], mailbox: [], closed: false, status: BC_RUNNING, reason: "" }
}

///|
/// 参照 `send`：未关闭则 FIFO 入队队尾；已关闭则丢弃（与 `ActorRef::send` 一致）。
fn bc_send(cell : BcCell, msg : Int) -> Unit {
  if cell.closed {
    return
  }
  cell.mailbox.push(msg)
}

///|
/// 参照 `stop`：关闭邮箱（与 `ActorRef::stop` 一致）；停止语义在 `bc_step` 中生效。
fn bc_stop(cell : BcCell) -> Unit {
  cell.closed = true
}

///|
/// 参照 `step`：复刻 `Scheduler::step` 的登记顺序扫描算法，至多处理一条消息。
///
/// 扫描顺序与副作用严格对齐 0.1.0 骨架：
///   * 跳过非 `Running` 的 actor；
///   * `Running` 且邮箱已关闭 → 置 `Stopped`、丢弃残留消息，并继续扫描下一个；
///   * 邮箱为空 → 跳过（挂起，不占处理步）；
///   * 否则取队首一条消息处理：非负 `Updated` 追加，负值 `Errored` 置 `Failed`、
///     关闭并丢弃残留，随即返回 `true`。
///
/// 返回是否确实处理了一条消息（`true` 有进展，`false` 已空闲）。
fn bc_step(cells : Array[BcCell]) -> Bool {
  for cell in cells {
    if cell.status != BC_RUNNING {
      continue
    }
    // stop 请求：处理完先前消息后，此处停止消息循环。
    if cell.closed {
      cell.mailbox.clear()
      cell.status = BC_STOPPED
      continue
    }
    // 空邮箱：挂起，不消耗处理步。
    if cell.mailbox.is_empty() {
      continue
    }
    // 串行处理：本步仅处理这一条消息（FIFO 取队首）。
    let msg = cell.mailbox.remove(0)
    if msg < 0 {
      // 未捕获错误：终止该 actor 并隔离，丢弃残留消息。
      cell.status = BC_FAILED
      cell.reason = "boom"
      cell.closed = true
      cell.mailbox.clear()
    } else {
      cell.state.push(msg)
    }
    return true
  }
  false
}

///|
/// 参照 `run_until_idle`：反复 `bc_step` 直至无就绪 actor。
fn bc_run_until_idle(cells : Array[BcCell]) -> Unit {
  while bc_step(cells) {

  }
}

// ---------------------------------------------------------------------------
// 操作序列（generator）—— 仅使用既有 API 的随机操作
// ---------------------------------------------------------------------------
//
// 操作编码（op kind）：0=Send，1=Step，2=Stop。每个操作携带目标 actor 下标与
// （对 Send）一个消息值。消息值约 1/5 概率为毒丸负值 -1，以触发未捕获错误路径。

///|
/// 单个随机操作（reference op）。
struct BcOp {
  kind : Int
  actor : Int
  value : Int
}

///|
/// 一次随机场景：actor 数量 + 操作序列。
struct BcScenario {
  actor_count : Int
  ops : Array[BcOp]
}

///|
/// 随机场景生成器：1~4 个 actor，0~30 个操作；操作类型与目标随机。
fn gen_bc_scenario(rng : @infra_pbt.Rng) -> BcScenario {
  let actor_count = rng.next_range(1, 4)
  let n_ops = rng.next_range(0, 30)
  let ops : Array[BcOp] = []
  for _i in 0..<n_ops {
    let actor = rng.next_below(actor_count)
    // 操作类型权重：Send 偏多，夹杂 Step 与少量 Stop。
    let r = rng.next_below(10)
    let kind = if r <= 5 {
      0 // Send
    } else if r <= 8 {
      1 // Step
    } else {
      2 // Stop
    }
    // Send 的消息值：约 1/5 为毒丸 -1，其余为非负值 [0, 100]。
    let value = if rng.next_below(5) == 0 { -1 } else { rng.next_range(0, 100) }
    ops.push({ kind, actor, value })
  }
  { actor_count, ops }
}

// ---------------------------------------------------------------------------
// 逐字段比对（field-by-field equality）
// ---------------------------------------------------------------------------

///|
/// 逐位比较两个 `Array[Int]` 是否相等（长度相同且对应元素相等）。
fn bc_int_arrays_eq(xs : Array[Int], ys : Array[Int]) -> Bool {
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

///|
/// 将 `Scheduler` 的 `ActorStatus` 与参照编码逐字段比较（含 `Failed` 的原因）。
fn bc_status_eq(
  actual : ActorStatus?,
  ref_status : Int,
  ref_reason : String,
) -> Bool {
  match actual {
    Some(Running) => ref_status == BC_RUNNING
    Some(Stopped) => ref_status == BC_STOPPED
    Some(Failed(reason)) => ref_status == BC_FAILED && reason == ref_reason
    None => false
  }
}

///|
/// 逐字段比较 `Scheduler` 与参照实现的全部可观测字段：
/// `state_of` / `status_of` / `pending` / `is_running`，对每个 actor 均需一致。
fn bc_compare_all(
  sched : Scheduler[Array[Int], Int],
  refs : Array[ActorRef[Int]],
  cells : Array[BcCell],
) -> Bool {
  for i in 0..<refs.length() {
    let r = refs[i]
    let cell = cells[i]
    // 状态数组逐位一致。
    match sched.state_of(r) {
      Some(st) => if !bc_int_arrays_eq(st, cell.state) { return false }
      None => return false
    }
    // 生命周期状态逐字段一致。
    if !bc_status_eq(sched.status_of(r), cell.status, cell.reason) {
      return false
    }
    // 待处理条数一致。
    if sched.pending(r) != cell.mailbox.length() {
      return false
    }
    // 运行标志一致。
    if sched.is_running(r) != (cell.status == BC_RUNNING) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Property 31：向后兼容不变量 —— 谓词实现
// ---------------------------------------------------------------------------

///|
/// 单次场景：在 `Scheduler` 与参照实现上施加同一随机操作序列，每个操作后逐字段
/// 比对，且每次 `step` 的返回值（是否有进展）亦须一致；最后 `run_until_idle`
/// 两侧并再次逐字段比对。任一处不一致即判定向后兼容性被破坏。
fn prop_bc_backward_compat(rng : @infra_pbt.Rng) -> Bool {
  let scenario = gen_bc_scenario(rng)
  // 处理函数：负值触发未捕获错误，非负追加并更新（两侧规则一致）。
  let handle = fn(s : Array[Int], m : Int) -> ActorOutcome[Array[Int]] {
    if m < 0 {
      Errored("boom")
    } else {
      s.push(m)
      Updated(s)
    }
  }
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  let refs : Array[ActorRef[Int]] = []
  let cells : Array[BcCell] = []
  for _i in 0..<scenario.actor_count {
    refs.push(sched.spawn([], handle))
    cells.push(bc_cell_new())
  }
  // 初始状态即应一致。
  if !bc_compare_all(sched, refs, cells) {
    return false
  }
  // 逐操作驱动并逐字段比对。
  for op in scenario.ops {
    let r = refs[op.actor]
    let cell = cells[op.actor]
    match op.kind {
      0 => {
        r.send(op.value)
        bc_send(cell, op.value)
      }
      1 => {
        let did = sched.step()
        let ref_did = bc_step(cells)
        // step 的「是否有进展」返回值亦须逐字段一致。
        if did != ref_did {
          return false
        }
      }
      _ => {
        r.stop()
        bc_stop(cell)
      }
    }
    // 每个操作后逐字段比对全部 actor。
    if !bc_compare_all(sched, refs, cells) {
      return false
    }
  }
  // 收尾：两侧 run_until_idle 后再次逐字段比对。
  sched.run_until_idle()
  bc_run_until_idle(cells)
  bc_compare_all(sched, refs, cells)
}

// ---------------------------------------------------------------------------
// 单元测试（具体见证）—— 锁定代表性场景
// ---------------------------------------------------------------------------

///|
/// Property 31 的具体见证：纯 FIFO/串行场景，处理结果与参照逐字段一致。
test "scheduler matches 0.1.0 reference on a fifo sequence (witness)" {
  let handle = fn(s : Array[Int], m : Int) -> ActorOutcome[Array[Int]] {
    if m < 0 {
      Errored("boom")
    } else {
      s.push(m)
      Updated(s)
    }
  }
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  let a = sched.spawn([], handle)
  for m in [3, 1, 4, 1, 5] {
    a.send(m)
  }
  sched.run_until_idle()
  // 参照实现独立计算。
  let cell = bc_cell_new()
  for m in [3, 1, 4, 1, 5] {
    bc_send(cell, m)
  }
  bc_run_until_idle([cell])
  @test.assert_eq(sched.state_of(a), Some(cell.state))
  assert_true(bc_status_eq(sched.status_of(a), cell.status, cell.reason))
  @test.assert_eq(sched.pending(a), cell.mailbox.length())
  @test.assert_eq(sched.is_running(a), cell.status == BC_RUNNING)
}

///|
/// Property 31 的具体见证：未捕获错误终止 + stop 停止，两侧逐字段一致。
test "scheduler matches 0.1.0 reference on error and stop semantics (witness)" {
  let handle = fn(s : Array[Int], m : Int) -> ActorOutcome[Array[Int]] {
    if m < 0 {
      Errored("boom")
    } else {
      s.push(m)
      Updated(s)
    }
  }
  let sched : Scheduler[Array[Int], Int] = Scheduler::new()
  let bad = sched.spawn([], handle)
  let stopped = sched.spawn([], handle)
  // bad：处理 5、7 后遇 -1 崩溃，残留 9 被丢弃。
  for m in [5, 7, -1, 9] {
    bad.send(m)
  }
  // stopped：投递两条后请求停止 —— 调度扫描时丢弃残留并置 Stopped。
  stopped.send(1)
  stopped.send(2)
  stopped.stop()
  sched.run_until_idle()
  let bad_cell = bc_cell_new()
  let stopped_cell = bc_cell_new()
  for m in [5, 7, -1, 9] {
    bc_send(bad_cell, m)
  }
  bc_send(stopped_cell, 1)
  bc_send(stopped_cell, 2)
  bc_stop(stopped_cell)
  bc_run_until_idle([bad_cell, stopped_cell])
  // bad：Failed("boom")，状态 [5, 7]，pending 0。
  @test.assert_eq(sched.state_of(bad), Some(bad_cell.state))
  assert_true(
    bc_status_eq(sched.status_of(bad), bad_cell.status, bad_cell.reason),
  )
  @test.assert_eq(sched.pending(bad), bad_cell.mailbox.length())
  assert_false(sched.is_running(bad))
  // stopped：Stopped，残留消息被丢弃。
  assert_true(
    bc_status_eq(
      sched.status_of(stopped),
      stopped_cell.status,
      stopped_cell.reason,
    ),
  )
  @test.assert_eq(sched.pending(stopped), stopped_cell.mailbox.length())
  assert_false(sched.is_running(stopped))
}

// ---------------------------------------------------------------------------
// Property 31：向后兼容（holds_for_all 模板，≥100 迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: actor, Property 31: 向后兼容
///
/// 对任意仅使用既有 `Scheduler`/`spawn`/`send`/`stop` API 的随机操作序列，
/// `Scheduler` 的处理结果（状态 / 生命周期状态 / 待处理条数 / 运行标志）与
/// `0.1.0` 骨架语义逐字段一致。复用 @infra_pbt 的 `holds_for_all` 不变量模板，
/// 默认迭代 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 14.3, 14.6**
test "Feature: actor, Property 31: scheduler is backward compatible with the 0.1.0 skeleton field-by-field (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { prop_bc_backward_compat(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
