// ten_k_actor_bench.mbt —— 方向十「万级 actor」吞吐基准与正确性门禁（任务 T10）。
//
// 目标：在 **10 000 个 actor × 10 条消息 = 100 000 条调度事件**的负载上量化
// ActorSystem 的消息吞吐（msgs/sec），并以「全部消息恰好处理一次」为正确性
// 门禁（`moon test` 三后端常跑）。计时经 `@bench.single_bench` 采集（微秒），
// 证据由 bench 块 println 输出，随 benches/results/ 工件流留档。

///|
/// 万级 actor 吞吐：actor 数量。
let ten_k_actor_count : Int = 10000

///|
/// 万级 actor 吞吐：每个 actor 的消息条数。
let ten_k_msgs_per_actor : Int = 10

///|
/// 构建 10k actor 系统、投递全部消息并调度至空闲；返回处理事件总数。
fn run_ten_k_actor_workload() -> Int {
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
  let refs : Array[@actor.ActorRef[Int]] = []
  for _ in 0..<ten_k_actor_count {
    refs.push(sys.spawn(0, counting_behavior()))
  }
  for r in refs {
    for _ in 0..<ten_k_msgs_per_actor {
      r.send(1)
    }
  }
  sys.run_until_idle_throughput()
  sys.trace_of().length()
}

///|
test "guard: 10k actor × 10 msgs 全部恰好处理一次" {
  let processed = run_ten_k_actor_workload()
  assert_eq(processed, ten_k_actor_count * ten_k_msgs_per_actor)
}

///|
test "bench: 10k actor throughput evidence" (b : @bench.T) {
  let total = ten_k_actor_count * ten_k_msgs_per_actor
  let summary = @bench.single_bench(
    name="actor_ten_k_throughput",
    fn() { b.keep(run_ten_k_actor_workload()) },
    count=3,
  )
  // single_bench 计时单位为微秒；median 为单轮（total 条消息）的中位耗时。
  let median_us = summary_median_us(summary)
  let msgs_per_sec = total.to_double() * 1.0e6 / median_us
  println("===TEN_K_ACTOR_EVIDENCE_BEGIN===")
  println("# 万级 actor 吞吐基准（ActorSystem）")
  println("")
  println(
    "- actor 数: \{ten_k_actor_count}; 每 actor 消息: \{ten_k_msgs_per_actor}; 总消息: \{total}",
  )
  println("- 单轮中位耗时: \{median_us / 1.0e3} ms（采样 3）")
  println("- 消息吞吐: \{msgs_per_sec} msgs/sec")
  println(
    "- 正确性门禁: 全部消息恰好处理一次（见同名 guard 测试）",
  )
  println("===TEN_K_ACTOR_EVIDENCE_END===")
  b.bench(name="ten_k_actor_emitted", fn() { b.keep(total) })
}
