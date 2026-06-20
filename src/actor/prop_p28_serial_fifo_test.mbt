// prop_p28_serial_fifo_test.mbt —— Property 28：串行处理与 FIFO 顺序（任务 11.4）。
//
//   Feature: actor, Property 28: 串行处理与 FIFO 顺序（ActorSystem 路径）
//   ------------------------------------------------------------------
//   *对任意* 单一发送者投递的消息序列，ActorSystem 一次仅处理一条消息（串行），
//   且严格按投递顺序处理（FIFO）。
//
// **Validates: Requirements 10.3, 10.4**

///|
/// 逐位比较两个 Int 数组。
fn p28_eq(xs : Array[Int], ys : Array[Int]) -> Bool {
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
/// 单次场景：单 actor 把每条消息 append 到状态数组，run_until_idle 后状态逐位等于
/// 投递顺序（FIFO）；逐步 step 时每步恰处理一条（串行）。
fn p28_serial_fifo(rng : @infra_pbt.Rng) -> Bool {
  let msgs : Array[Int] = []
  let n = rng.next_range(0, 12)
  for _i in 0..<n {
    msgs.push(rng.next_range(-100, 100))
  }
  // FIFO 视角。
  let sys : ActorSystem[Array[Int], Int] = ActorSystem::new()
  let a = sys.spawn(
    [],
    Behavior::new(fn(_ctx, s, m) {
      s.push(m)
      Updated(s)
    }),
  )
  for m in msgs {
    a.send(m)
  }
  sys.run_until_idle()
  match sys.state_of(a) {
    Some(processed) => if not(p28_eq(processed, msgs)) { return false }
    None => return false
  }
  // 串行视角：逐步 step，每步处理一条 → trace 长度每步加一。
  let sys2 : ActorSystem[Array[Int], Int] = ActorSystem::new()
  let b = sys2.spawn(
    [],
    Behavior::new(fn(_ctx, s, m) {
      s.push(m)
      Updated(s)
    }),
  )
  for m in msgs {
    b.send(m)
  }
  for i in 0..<n {
    let did = sys2.step()
    if not(did) {
      return false
    }
    if sys2.trace_of().length() != i + 1 {
      return false
    }
  }
  // 处理完毕后再 step 应空闲。
  not(sys2.step())
}

///|
/// Feature: actor, Property 28: 串行处理与 FIFO 顺序（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 10.3, 10.4**
test "Feature: actor, Property 28: ActorSystem processes serially in FIFO order (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p28_serial_fifo(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
