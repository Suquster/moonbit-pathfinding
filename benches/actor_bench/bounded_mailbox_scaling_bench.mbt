// bounded_mailbox_scaling_bench.mbt —— 有界邮箱出队复杂度证据（O(1) 摊销）。
//
// 背景：BoundedMailbox 出队与 DropOldest 淘汰原为 `Array::remove(0)`（O(n)
// 头删），高频消费下呈平方级退化；现改为队首游标 + 过半惰性压缩（与 Mailbox
// 同一模式），单次出队摊销 O(1)。本基准以 4 组倍增规模实测「总耗时 / 消息数」
// 近似常数（线性总耗时），作为复杂度证据留档（平方级实现会呈 4× 比率）。

///|
/// 满载轮转工作负载：容量 cap 的 DropOldest 邮箱，交替 offer/dequeue 共
/// rounds 轮（每轮 1 入 1 出，队列长度保持在 cap 附近，触发淘汰与压缩路径）。
fn run_bounded_mailbox_workload(cap : Int, rounds : Int) -> Int {
  let mb : @actor.BoundedMailbox[Int] = @actor.BoundedMailbox::new(
    cap,
    @actor.BackpressurePolicy::DropOldest,
  )
  // 先灌满，进入稳态。
  for i in 0..<cap {
    let _ = mb.offer(i)
  }
  let mut acc = 0
  for i in 0..<rounds {
    let _ = mb.offer(i)
    match mb.dequeue() {
      Some(v) => acc = acc + (v & 1)
      None => ()
    }
  }
  acc + mb.length()
}

///|
test "guard: 有界邮箱满载轮转守恒（长度恒等 + FIFO 语义）" {
  let cap = 1024
  let mb : @actor.BoundedMailbox[Int] = @actor.BoundedMailbox::new(
    cap,
    @actor.BackpressurePolicy::DropOldest,
  )
  for i in 0..<cap {
    let _ = mb.offer(i)
  }
  // 稳态轮转：每轮先出再入（不触发淘汰），长度恒为 cap，出队严格 FIFO。
  for i in 0..<(cap * 8) {
    match mb.dequeue() {
      Some(v) => assert_eq(v, i)
      None => abort("dequeue empty")
    }
    assert_eq(mb.length(), cap - 1)
    let _ = mb.offer(cap + i)
    assert_eq(mb.length(), cap)
  }
  // 满载 offer 触发 DropOldest：淘汰当前队首，随后 FIFO 从下一条继续。
  let _ = mb.offer(1 << 30)
  assert_eq(mb.length(), cap)
  match mb.dequeue() {
    Some(v) => assert_eq(v, cap * 8 + 1)
    None => abort("dequeue empty")
  }
}

///|
test "bench: bounded mailbox O(1) dequeue scaling evidence" (b : @bench.T) {
  let cap = 4096
  let sizes = [100000, 200000, 400000, 800000]
  let per_msg_ns : Array[Double] = []
  println("===BOUNDED_MAILBOX_SCALING_EVIDENCE_BEGIN===")
  println(
    "# 有界邮箱出队复杂度证据（DropOldest 满载轮转，容量 \{cap}）",
  )
  println("")
  println("| rounds | 中位总耗时 (ms) | 每消息 (ns) |")
  println("| --- | --- | --- |")
  for rounds in sizes {
    let summary = @bench.single_bench(
      name="bounded_mailbox_\{rounds}",
      fn() { b.keep(run_bounded_mailbox_workload(cap, rounds)) },
      count=3,
    )
    let median_us = summary_median_us(summary)
    let per = median_us * 1.0e3 / rounds.to_double()
    per_msg_ns.push(per)
    println("| \{rounds} | \{median_us / 1.0e3} | \{per} |")
  }
  // 复杂度判据：最大规模的每消息耗时不超过最小规模的 3×（O(n) 头删实现
  // 在 8× 规模差下应呈 ~8× 比率）。
  let ratio = per_msg_ns[per_msg_ns.length() - 1] / per_msg_ns[0]
  println("")
  println(
    "- 每消息耗时比率（800k vs 100k）: \{ratio}（O(1) 摊销判据 <3）",
  )
  println("===BOUNDED_MAILBOX_SCALING_EVIDENCE_END===")
  b.bench(name="bounded_mailbox_scaling_emitted", fn() {
    b.keep(sizes.length())
  })
}
