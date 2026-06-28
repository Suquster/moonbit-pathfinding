// actor_bench_test.mbt —— 方向十（Actor_Framework）基准 **小规模负载可运行见证**
// （黑盒单元测试，任务 17.3，Requirement 12.1）。
//
// 主文件 actor_bench.mbt 已覆盖**大规模** smoke / artifact / guard（运行重、靠近真实
// 基准量级）。本黑盒 _test.mbt 仅经 @actor 的**公开 API** 直接构造**小规模**等价
// 负载，断言其**确定性可重放**结果（trace 长度、完成计数、路由分发计数、ask `Replied`
// 命中数、监督重启次数）。两者互补：此处运行快、三后端（wasm-gc / js / native）稳定，
// 为五类基准负载提供轻量"可运行见证"。
//
// 黑盒文件只能访问 @actor 的 pub 项，故不复用主文件的包内私有运行函数，而是用公开
// 类型（ActorSystem / Behavior / Router / AskBroker / ask / worker_pool_demo 等）重建
// 同形态的小规模负载。所有规模均以**命名常量**表达（禁止 magic number）。
//
// native 后端运行前需先：`export LIBRARY_PATH=/usr/lib64:/usr/lib`。
//
// _Requirements: 12.1_

// ───────────────────────────── 小规模负载规模（命名常量） ───────────────

///|
/// ① 小规模高频 send：单 actor 串行消费的消息条数。
let smoke_send_msgs : Int = 20

///|
/// ② 小规模海量调度：actor 数量。
let smoke_scheduling_actors : Int = 3

///|
/// ② 小规模海量调度：每个 actor 的消息条数（总调度量 = 数量 × 每 actor 条数 = 12）。
let smoke_scheduling_msgs_per_actor : Int = 4

///|
/// ③ 小规模 ask 往返：连续发起的请求-响应往返次数。
let smoke_ask_round_trips : Int = 5

///|
/// ③ 小规模 ask 往返：单次 ask 的驱动步数预算（每次至多一条请求待处理，少量步即命中）。
let smoke_ask_step_budget : Int = 8

///|
/// ④ 小规模路由分发：worker 数量。
let smoke_router_workers : Int = 4

///|
/// ④ 小规模路由分发：分发的消息条数（被 worker 数整除，便于 RoundRobin 均分断言）。
let smoke_router_msgs : Int = 8

///|
/// ⑤ 小规模监督重启：受监督 worker 数量。
let smoke_supervision_workers : Int = 3

///|
/// ⑤ 小规模监督重启：分发的任务总数。
let smoke_supervision_tasks : Int = 6

///|
/// ⑤ 小规模监督重启：注入单点失败的任务下标（触发该 worker 在 OneForOne 下重启一次）。
let smoke_supervision_fault_at : Int = 2

///|
/// ⑤ 小规模监督重启：种子驱动确定性调度的种子（同种子两次运行逐事件一致）。
let smoke_supervision_seed : UInt64 = 0xD1B54A32D192ED03

// ───────────────────────────── 共享行为构造 ─────────────────────────────

///|
/// 计数 actor 行为：每条消息使状态累加该消息的整型值（高频 send / 海量调度 / 路由
/// 分发共用）。投递值 1 时，终态即等于收到的消息条数。
fn smoke_counting_behavior() -> @actor.Behavior[Int, Int] {
  @actor.Behavior::new(fn(_ctx, s, m) { @actor.Updated(s + m) })
}

///|
/// ask 见证的消息协议：携带关联 id 的查询；被请求方经 broker 回填其当前计数为响应。
priv enum SmokeAskMsg {
  Query(@actor.CorrelationId)
}

///|
/// ask 应答 actor 行为：收到 `Query(cid)` 经 `broker` 回填当前状态计数并 +1。
fn smoke_ask_responder(
  broker : @actor.AskBroker[Int],
) -> @actor.Behavior[Int, SmokeAskMsg] {
  @actor.Behavior::new(fn(_ctx, s, msg) {
    match msg {
      Query(cid) => {
        broker.fulfill(cid, s)
        @actor.Updated(s + 1)
      }
    }
  })
}

// ───────────────────────────── 五类小规模负载见证 ───────────────────────

///|
/// 见证 ①（小规模高频 send）：单 actor 投递 `smoke_send_msgs` 条消息后串行消费至空闲，
/// 处理事件总数（trace 长度）应恰等于投递条数。
test "witness: small high-frequency send drains exactly N messages" {
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
  let counter = sys.spawn(0, smoke_counting_behavior())
  for _ in 0..<smoke_send_msgs {
    counter.send(1)
  }
  sys.run_until_idle()
  // trace 长度 == 投递条数（每条消息恰处理一次）。
  @test.assert_eq(sys.trace_of().length(), smoke_send_msgs)
  // 计数终态同样等于条数（消息值均为 1）。
  @test.assert_eq(sys.state_of(counter).unwrap(), smoke_send_msgs)
}

///|
/// 见证 ②（小规模海量调度）：`smoke_scheduling_actors` 个 actor 各投递
/// `smoke_scheduling_msgs_per_actor` 条消息，统一调度至空闲后 trace 长度应等于二者之积
/// （3 × 4 = 12）。
test "witness: small massive scheduling processes actors x msgs events" {
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
  let refs : Array[@actor.ActorRef[Int]] = []
  for _ in 0..<smoke_scheduling_actors {
    refs.push(sys.spawn(0, smoke_counting_behavior()))
  }
  for r in refs {
    for _ in 0..<smoke_scheduling_msgs_per_actor {
      r.send(1)
    }
  }
  sys.run_until_idle()
  let expected = smoke_scheduling_actors * smoke_scheduling_msgs_per_actor
  @test.assert_eq(sys.trace_of().length(), expected)
  // 每个 actor 恰处理 msgs_per_actor 条。
  for r in refs {
    @test.assert_eq(sys.state_of(r).unwrap(), smoke_scheduling_msgs_per_actor)
  }
}

///|
/// 见证 ③（小规模 ask 往返）：对单个应答 actor 连续发起 `smoke_ask_round_trips` 次
/// ask，每次都应在步数预算内命中 `Replied`，命中数恰等于往返次数。
test "witness: small ask round-trip replies every time within budget" {
  let broker : @actor.AskBroker[Int] = @actor.AskBroker::new()
  let sys : @actor.ActorSystem[Int, SmokeAskMsg] = @actor.ActorSystem::new()
  let responder = sys.spawn(0, smoke_ask_responder(broker))
  let mut replied = 0
  for _ in 0..<smoke_ask_round_trips {
    let result = @actor.ask(
      sys,
      broker,
      responder,
      fn(id) { Query(id) },
      smoke_ask_step_budget,
    )
    match result {
      @actor.Replied(_) => replied = replied + 1
      @actor.Timeout => ()
    }
  }
  @test.assert_eq(replied, smoke_ask_round_trips)
}

///|
/// 见证 ④（小规模路由分发，三策略）：以 `smoke_router_workers` 个 worker 分发
/// `smoke_router_msgs` 条消息，断言**各 worker 的精确计数**。
///
///   * RoundRobin     —— 均匀轮询，每 worker 恰得 msgs / workers 条（8 / 4 = 2）；
///   * Broadcast      —— 每条复制到全部 worker，每 worker 恰得 msgs 条（8）；
///   * ConsistentHash —— 按键哈希分发：总计数守恒（== msgs）、同键稳定落点（确定性）。
test "witness: small router dispatch yields exact per-worker counts" {
  // ── RoundRobin：每 worker 恰 msgs / workers 条 ──
  {
    let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
    let workers : Array[@actor.ActorRef[Int]] = []
    for _ in 0..<smoke_router_workers {
      workers.push(sys.spawn(0, smoke_counting_behavior()))
    }
    let router = @actor.Router::new(@actor.RoundRobin, workers)
    for _ in 0..<smoke_router_msgs {
      router.route(1)
    }
    sys.run_until_idle()
    let per_worker = smoke_router_msgs / smoke_router_workers
    for w in workers {
      @test.assert_eq(sys.state_of(w).unwrap(), per_worker)
    }
  }
  // ── Broadcast：每 worker 恰得全部 msgs 条 ──
  {
    let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
    let workers : Array[@actor.ActorRef[Int]] = []
    for _ in 0..<smoke_router_workers {
      workers.push(sys.spawn(0, smoke_counting_behavior()))
    }
    let router = @actor.Router::new(@actor.Broadcast, workers)
    for _ in 0..<smoke_router_msgs {
      router.route(1)
    }
    sys.run_until_idle()
    for w in workers {
      @test.assert_eq(sys.state_of(w).unwrap(), smoke_router_msgs)
    }
  }
  // ── ConsistentHash：总计数守恒 + 同键稳定落点（确定性可重放）──
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
  let workers : Array[@actor.ActorRef[Int]] = []
  for _ in 0..<smoke_router_workers {
    workers.push(sys.spawn(0, smoke_counting_behavior()))
  }
  let router = @actor.Router::new(@actor.ConsistentHash, workers)
  for i in 0..<smoke_router_msgs {
    router.route_keyed("key#\{i}", 1)
  }
  sys.run_until_idle()
  // 总计数守恒：各 worker 计数之和 == 投递条数（无丢失、无重复）。
  let mut total = 0
  for w in workers {
    total = total + sys.state_of(w).unwrap()
  }
  @test.assert_eq(total, smoke_router_msgs)
  // 确定性：同一路由键始终映射到同一 worker。
  @test.assert_eq(
    router.worker_for_key("key#0"),
    router.worker_for_key("key#0"),
  )
}

///|
/// 见证 ⑤（小规模监督重启）：以 `worker_pool_demo` 在 `smoke_supervision_fault_at`
/// 注入单点失败，OneForOne 下该 worker 重启一次、其余不受影响：
///
///   * `completed` == 任务总数 − 1（注入失败的任务不计入完成，其余全部完成）；
///   * `restarts`  == 1（单点失败恰触发一次重启）。
///
/// 同种子两次运行得到**完全一致**的报告（确定性可重放，与基准量级负载同形态）。
test "witness: small supervision restart completes all but the faulted task" {
  let tasks : Array[@actor.Task] = []
  for i in 0..<smoke_supervision_tasks {
    tasks.push({ id: i, payload: i })
  }
  let report = @actor.worker_pool_demo(
    smoke_supervision_workers,
    tasks,
    Some(smoke_supervision_fault_at),
    smoke_supervision_seed,
  )
  // 注入的失败任务不计入完成，其余可完成任务全部完成。
  @test.assert_eq(report.completed, smoke_supervision_tasks - 1)
  // 单点失败恰触发一次重启。
  @test.assert_eq(report.restarts, 1)
  // 同种子重放：逐字段一致。
  let replay = @actor.worker_pool_demo(
    smoke_supervision_workers,
    tasks,
    Some(smoke_supervision_fault_at),
    smoke_supervision_seed,
  )
  @test.assert_eq(replay.completed, report.completed)
  @test.assert_eq(replay.restarts, report.restarts)
}
