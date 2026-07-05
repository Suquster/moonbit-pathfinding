// throughput_test.mbt —— 高吞吐批量驱动与逐步驱动的终态一致性差分测试。

///|
fn tp_counting() -> @actor.Behavior[Int, Int] {
  @actor.Behavior::new(fn(_ctx, s, m) { @actor.Updated(s + m) })
}

///|
test "throughput: 终态与逐步驱动一致（多 actor 计数）" {
  let mk = fn() {
    let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
    let refs : Array[@actor.ActorRef[Int]] = []
    for _ in 0..<17 {
      refs.push(sys.spawn(0, tp_counting()))
    }
    for i in 0..<refs.length() {
      for k in 0..<(3 + i % 5) {
        refs[i].send(k + 1)
      }
    }
    (sys, refs)
  }
  let (a, ra) = mk()
  a.run_until_idle()
  let (b, rb) = mk()
  b.run_until_idle_throughput()
  @test.assert_eq(a.trace_of().length(), b.trace_of().length())
  for i in 0..<ra.length() {
    @test.assert_eq(a.state_of(ra[i]), b.state_of(rb[i]))
  }
}

///|
test "throughput: 处理中派生消息（actor 间转发链）全部送达" {
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
  let sink = sys.spawn(0, tp_counting())
  // 转发者：收到 m 后向 sink 直接投递 m（处理中产生新消息，驱动须继续排空）。
  let fwd = sys.spawn(
    0,
    @actor.Behavior::new(fn(_ctx, s, m) {
      sink.send(m)
      @actor.Updated(s + 1)
    }),
  )
  for k in 0..<50 {
    fwd.send(k + 1)
  }
  sys.run_until_idle_throughput()
  @test.assert_eq(sys.state_of(fwd), Some(50))
  @test.assert_eq(sys.state_of(sink), Some(50 * 51 / 2))
  @test.assert_eq(sys.trace_of().length(), 100)
}

///|
test "throughput: 显式停止在返回前完成结算" {
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
  let a = sys.spawn(0, tp_counting())
  a.send(1)
  a.stop()
  sys.run_until_idle_throughput()
  let stopped = match sys.status_of(a) {
    Some(@actor.ActorStatus::Stopped) => true
    _ => false
  }
  @test.assert_eq(stopped, true)
}
