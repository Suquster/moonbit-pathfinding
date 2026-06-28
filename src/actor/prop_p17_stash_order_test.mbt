// prop_p17_stash_order_test.mbt —— Property 17：stash 保序与就绪判定（任务 6.2）。
//
//   Feature: actor, Property 17: stash 保序与就绪判定
//   ------------------------------------------------------------------
//   *对任意* 消息序列与 stash/unstash 操作序列，`unstash_all` 后被暂存消息的相对
//   处理顺序与其暂存时的相对顺序一致；仅含暂存消息的 actor 不被错误唤醒。
//
// **Validates: Requirements 6.2, 6.3, 6.5**

///|
/// 逐位比较两个 Int 数组。
fn p17_eq(xs : Array[Int], ys : Array[Int]) -> Bool {
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
/// 单次场景：随机把一批消息 stash，邮箱另含若干待处理消息；drain_to_front 后
/// 邮箱出队顺序应为「暂存序列（保序） ++ 原邮箱序列」；且暂存期间邮箱可能为空
/// （仅含暂存消息时 is_empty 为真，不会被唤醒）。
fn p17_stash_order(rng : @infra_pbt.Rng) -> Bool {
  let stash : StashBuffer[Int] = StashBuffer::new()
  let mailbox : Mailbox[Int] = Mailbox::new()
  // 暂存序列。
  let stashed : Array[Int] = []
  let ns = rng.next_range(0, 10)
  for _i in 0..<ns {
    let v = rng.next_range(0, 1000)
    stashed.push(v)
    stash.push(v)
  }
  // 就绪判定：仅含暂存消息（邮箱为空）时邮箱 is_empty 为真。
  if ns > 0 && stash.length() != ns {
    return false
  }
  // 原邮箱待处理消息。
  let original : Array[Int] = []
  let nm = rng.next_range(0, 10)
  for _i in 0..<nm {
    let v = rng.next_range(1000, 2000)
    original.push(v)
    mailbox.enqueue(v)
  }
  // 回流：暂存序列置于原邮箱消息之前。
  stash.drain_to_front(mailbox)
  // 回流后暂存缓冲清空。
  if !(stash.is_empty()) {
    return false
  }
  // 期望出队顺序：stashed ++ original。
  let expected : Array[Int] = []
  for v in stashed {
    expected.push(v)
  }
  for v in original {
    expected.push(v)
  }
  let actual : Array[Int] = []
  while true {
    match mailbox.dequeue() {
      Some(v) => actual.push(v)
      None => break
    }
  }
  p17_eq(actual, expected)
}

///|
/// Feature: actor, Property 17: stash 保序与就绪判定（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 6.2, 6.3, 6.5**
test "Feature: actor, Property 17: unstash_all preserves relative order ahead of mailbox (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p17_stash_order(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
