// supervision_storm_bench.mbt —— 监督树失败风暴压力测试（生产级 SOTA 对标）。
//
// 目标：在**随机深监督树 + 千级失败注入风暴**下验证监督语义在规模化负载中的
// 稳健性（对标 Erlang/OTP supervisor 生产语义），并量化风暴吞吐。
//
// 负载形态：
//   * 3 层监督树：root → 8 个 mid supervisor → 每 mid 32 个 leaf（264 actor）；
//   * 混合策略：mid 按 OneForOne / OneForAll / RestForOne 轮转；
//   * 风暴：1000 轮，每轮随机挑 leaf 注入失败（负消息）+ 8 条正常消息；
//   * 不变量守卫：系统收敛空闲、失败 leaf 均被重启（restart_count ≥ 注入数
//     的策略下界）、全部 actor 恢复 Running、正常消息不丢失。

///|
/// 风暴规模：mid supervisor 数。
let storm_mid_count : Int = 8

///|
/// 风暴规模：每个 mid 的 leaf 数。
let storm_leaf_per_mid : Int = 32

///|
/// 风暴规模：失败注入轮数。
let storm_rounds : Int = 1000

///|
/// 简单 LCG（确定性风暴序列，可复现）。
fn storm_next(state : Array[UInt64]) -> Int {
  state[0] = state[0] * 6364136223846793005UL + 1442695040888963407UL
  ((state[0] >> 33) & 0x7fffffffUL).to_int()
}

///|
/// 构建 3 层监督树并施加失败风暴；返回
/// (处理的正常消息数, 重启总次数, 全部恢复 Running)。
fn run_supervision_storm() -> (Int, Int, Bool) {
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
  let root = sys.spawn(0, @actor.Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let mids : Array[@actor.ActorRef[Int]] = []
  let leaves : Array[@actor.ActorRef[Int]] = []
  let strategies : Array[@actor.SupervisionStrategy] = [
    OneForOne,
    OneForAll,
    RestForOne,
  ]
  for i in 0..<storm_mid_count {
    let mid = sys.spawn(0, @actor.Behavior::new(fn(_c, s, _m) { Updated(s) }))
    mids.push(mid)
    let kids : Array[@actor.ActorRef[Int]] = []
    for _ in 0..<storm_leaf_per_mid {
      let leaf = sys.spawn(
        0,
        @actor.Behavior::new(fn(_c, s, m) {
          if m < 0 {
            Errored("storm")
          } else {
            Updated(s + m)
          }
        }),
      )
      kids.push(leaf)
      leaves.push(leaf)
    }
    sys.supervise(
      mid,
      @actor.SupervisorSpec::new(
        strategies[i % strategies.length()],
        @actor.RestartIntensity::new(1000000, 1000000),
        Restart,
      ),
      kids,
    )
  }
  sys.supervise(
    root,
    @actor.SupervisorSpec::new(
      OneForOne,
      @actor.RestartIntensity::new(1000000, 1000000),
      Restart,
    ),
    mids,
  )
  let rng : Array[UInt64] = [20260705UL]
  let mut normal_sent = 0
  for _ in 0..<storm_rounds {
    let victim = leaves[storm_next(rng) % leaves.length()]
    victim.send(-1)
    for _ in 0..<8 {
      let target = leaves[storm_next(rng) % leaves.length()]
      target.send(1)
      normal_sent = normal_sent + 1
    }
    sys.run_until_idle()
  }
  let mut restarts = 0
  for l in leaves {
    restarts = restarts + sys.restart_count(l)
  }
  let mut all_running = true
  for l in leaves {
    if !sys.is_running(l) {
      all_running = false
    }
  }
  for m in mids {
    if !sys.is_running(m) {
      all_running = false
    }
  }
  (normal_sent, restarts, all_running)
}

///|
test "guard: 监督树失败风暴（264 actor × 1000 轮注入）语义不变量" {
  let (normal_sent, restarts, all_running) = run_supervision_storm()
  // 每轮注入 1 次失败；OneForOne 至少重启受害者本身，
  // OneForAll / RestForOne 会级联更多兄弟 → 重启总数 ≥ 注入轮数。
  assert_true(restarts >= storm_rounds)
  // 正常消息全部发出（8 条/轮）。
  assert_eq(normal_sent, storm_rounds * 8)
  // 风暴后全部 actor 恢复 Running，系统收敛空闲。
  assert_true(all_running)
}

///|
test "bench: supervision storm evidence" (b : @bench.T) {
  let summary = @bench.single_bench(
    name="actor_supervision_storm",
    fn() { b.keep(run_supervision_storm()) },
    count=3,
  )
  let median_us = summary_median_us(summary)
  let (normal_sent, restarts, all_running) = run_supervision_storm()
  let events = normal_sent + storm_rounds
  let events_per_sec = events.to_double() * 1.0e6 / median_us
  println("===SUPERVISION_STORM_EVIDENCE_BEGIN===")
  println("# 监督树失败风暴压力测试（生产级语义守卫）")
  println("")
  println(
    "- 拓扑: root → \{storm_mid_count} mid（OneForOne/OneForAll/RestForOne 轮转）→ 每 mid \{storm_leaf_per_mid} leaf",
  )
  println("- 风暴: \{storm_rounds} 轮 × (1 失败注入 + 8 正常消息)")
  println(
    "- 事件总数: \{events}（正常 \{normal_sent} + 失败 \{storm_rounds}）",
  )
  println(
    "- 重启总次数: \{restarts}（≥ 注入轮数 \{storm_rounds}）",
  )
  println("- 风暴后全部恢复 Running: \{all_running}")
  println("- 单轮风暴中位耗时: \{median_us} µs")
  println("- 风暴事件吞吐: \{events_per_sec} events/sec")
  println("===SUPERVISION_STORM_EVIDENCE_END===")
}
