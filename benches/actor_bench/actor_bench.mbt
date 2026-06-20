// benches/actor_bench — 方向十（Actor_Framework）原生基准与三后端 smoke guard。
//
// 覆盖五类代表性负载（Requirement 12.1）：
//   ① 高频 `send`     —— actor_send_<N>
//   ② 海量 actor 调度 —— actor_scheduling_<A>x<M>
//   ③ ask 往返        —— actor_ask_roundtrip_<N>
//   ④ 路由分发        —— actor_router_{round_robin,broadcast,consistent_hash}_<N>
//   ⑤ 监督重启        —— actor_supervision_restart_<W>x<T>
//
// 工件输出（Requirement 12.2）：`render_actor_bench_artifact` 产出含机器标识 /
// 后端目标 / 负载规模 / 计时统计（min/mean/median/std_dev/...，单位微秒）的 JSON。
//
// 运行（native）：`export LIBRARY_PATH=/usr/lib64:/usr/lib && moon bench benches/actor_bench --target native`。
// 工件（任一后端）：`moon test benches/actor_bench`（artifact 测试会 println JSON）。
//
// _Requirements: 12.1, 12.2_

// ───────────────────────────── 负载规模（命名常量） ─────────────────────

///|
/// 机器标识 —— 写入工件的「machine_id」字段（运行环境标识，Requirement 12.2）。
let bench_machine_id : String = "b81dace926e09bd26ac488c2f775cc82b419067b1d7e335441fe134b85713027"

///|
/// 工件 schema 标识（版本化，便于下游解析）。
let bench_artifact_schema : String = "moonbit-pathfinding.actor-bench.v1"

///|
/// ① 高频 send：单 actor 入队并串行消费的消息条数。
let send_workload_msgs : Int = 5000

///|
/// ② 海量 actor 调度：actor 数量。
let massive_actor_count : Int = 200

///|
/// ② 海量 actor 调度：每个 actor 的消息条数（总调度量 = actor 数 × 每 actor 条数）。
let massive_msgs_per_actor : Int = 50

///|
/// ③ ask 往返：连续发起的请求-响应往返次数。
let ask_roundtrip_count : Int = 500

///|
/// ③ ask 往返：单次 ask 的驱动步数预算（每次至多一条请求待处理，少量步即可命中）。
let ask_step_budget : Int = 8

///|
/// ④ 路由分发：worker 数量。
let router_worker_count : Int = 8

///|
/// ④ 路由分发：分发的消息条数。
let router_dispatch_msgs : Int = 2000

///|
/// ⑤ 监督重启：受监督 worker 数量。
let supervision_worker_count : Int = 8

///|
/// ⑤ 监督重启：分发的任务总数。
let supervision_task_count : Int = 400

///|
/// ⑤ 监督重启：注入失败的任务下标（触发该 worker 在 OneForOne 下重启恢复）。
let supervision_fault_at : Int = 17

///|
/// ⑤ 监督重启：种子驱动确定性调度的种子。
let supervision_seed : UInt64 = 0x9E3779B97F4A7C15

///|
/// 工件计时采样次数 —— 每类负载用 `single_bench` 采集的样本数（保持工件生成轻量）。
let artifact_sample_count : UInt = 3

// ───────────────────────────── ask 工作负载消息 ─────────────────────────

///|
/// ask 基准的消息协议：携带关联 id 的查询请求；被请求方回填其当前计数作为响应。
priv enum AskBenchMsg {
  Query(@actor.CorrelationId)
}

///|
/// ask 应答 actor 行为：收到 `Query(cid)` 时经 `broker` 回填当前状态计数并 +1。
fn ask_responder(
  broker : @actor.AskBroker[Int],
) -> @actor.Behavior[Int, AskBenchMsg] {
  @actor.Behavior::new(fn(_ctx, s, msg) {
    match msg {
      Query(cid) => {
        broker.fulfill(cid, s)
        @actor.Updated(s + 1)
      }
    }
  })
}

// ───────────────────────────── 五类工作负载（纯运行函数） ────────────────

///|
/// 计数 actor 行为：每条消息使状态 +1（高频 send / 海量调度 / 路由分发共用）。
fn counting_behavior() -> @actor.Behavior[Int, Int] {
  @actor.Behavior::new(fn(_ctx, s, _m) { @actor.Updated(s + 1) })
}

///|
/// ① 高频 send：单 actor 入队 `send_workload_msgs` 条消息后串行消费至空闲。
/// 返回处理事件总数（trace 长度），供 `keep` 防止优化消除。
fn run_send_workload() -> Int {
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
  let counter = sys.spawn(0, counting_behavior())
  for _ in 0..<send_workload_msgs {
    counter.send(1)
  }
  sys.run_until_idle()
  sys.trace_of().length()
}

///|
/// ② 海量 actor 调度：派生 `massive_actor_count` 个 actor，各投递
/// `massive_msgs_per_actor` 条消息后统一调度至空闲。
fn run_massive_scheduling_workload() -> Int {
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
  let refs : Array[@actor.ActorRef[Int]] = []
  for _ in 0..<massive_actor_count {
    refs.push(sys.spawn(0, counting_behavior()))
  }
  for r in refs {
    for _ in 0..<massive_msgs_per_actor {
      r.send(1)
    }
  }
  sys.run_until_idle()
  sys.trace_of().length()
}

///|
/// ③ ask 往返：对单个应答 actor 连续发起 `ask_roundtrip_count` 次 ask，统计命中
/// `Replied` 的次数。
fn run_ask_roundtrip_workload() -> Int {
  let broker : @actor.AskBroker[Int] = @actor.AskBroker::new()
  let sys : @actor.ActorSystem[Int, AskBenchMsg] = @actor.ActorSystem::new()
  let responder = sys.spawn(0, ask_responder(broker))
  let mut replied = 0
  for _ in 0..<ask_roundtrip_count {
    let result = @actor.ask(
      sys,
      broker,
      responder,
      fn(id) { Query(id) },
      ask_step_budget,
    )
    match result {
      @actor.Replied(_) => replied = replied + 1
      @actor.Timeout => ()
    }
  }
  replied
}

///|
/// ④ 路由分发：按给定策略把 `router_dispatch_msgs` 条消息分发给
/// `router_worker_count` 个 worker，再调度至空闲。ConsistentHash 以可变路由键分发。
fn run_router_workload(strategy : @actor.RoutingStrategy) -> Int {
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::new()
  let workers : Array[@actor.ActorRef[Int]] = []
  for _ in 0..<router_worker_count {
    workers.push(sys.spawn(0, counting_behavior()))
  }
  let router = @actor.Router::new(strategy, workers)
  for i in 0..<router_dispatch_msgs {
    match strategy {
      @actor.ConsistentHash => router.route_keyed("key#\{i}", 1)
      _ => router.route(1)
    }
  }
  sys.run_until_idle()
  sys.trace_of().length()
}

///|
/// ⑤ 监督重启：构造 `supervision_task_count` 个任务、在 `supervision_fault_at`
/// 注入失败，经 `worker_pool_demo` 在 OneForOne 下重启恢复并完成全部可完成任务。
/// 返回完成任务数。
fn run_supervision_restart_workload() -> Int {
  let tasks : Array[@actor.Task] = []
  for i in 0..<supervision_task_count {
    tasks.push({ id: i, payload: i })
  }
  let report = @actor.worker_pool_demo(
    supervision_worker_count,
    tasks,
    Some(supervision_fault_at),
    supervision_seed,
  )
  report.completed
}

// ───────────────────────────── 计时工件（JSON，R12.2） ──────────────────

///|
/// 渲染单个工作负载的工件条目（JSON 对象）：负载名、负载规模、计时统计（微秒）。
/// 计时统计直接复用 `@bench.Summary` 的 `ToJson`（min/mean/median/std_dev/...）。
fn render_workload_entry(
  label : String,
  load_scale : String,
  summary : @bench.Summary,
) -> String {
  let parts : Array[String] = [
    "{\"workload\":\"",
    label,
    "\",\"load_scale\":\"",
    load_scale,
    "\",\"timing_us\":",
    summary.to_json().stringify(escape_slash=true),
    "}",
  ]
  parts.join("")
}

///|
/// 采集五类负载的计时统计并渲染为完整 JSON 工件（含机器标识 / 后端目标 / 负载规模 /
/// 计时统计，Requirement 12.2）。以 `Array[String]` + `join` 构建，无 O(n²) 拼接。
fn render_actor_bench_artifact() -> String {
  // 逐类负载采集计时（单位：微秒）。
  let send = @bench.single_bench(
    name="actor_send",
    fn() { ignore(run_send_workload()) },
    count=artifact_sample_count,
  )
  let scheduling = @bench.single_bench(
    name="actor_scheduling",
    fn() { ignore(run_massive_scheduling_workload()) },
    count=artifact_sample_count,
  )
  let ask = @bench.single_bench(
    name="actor_ask_roundtrip",
    fn() { ignore(run_ask_roundtrip_workload()) },
    count=artifact_sample_count,
  )
  let router = @bench.single_bench(
    name="actor_router_round_robin",
    fn() { ignore(run_router_workload(@actor.RoundRobin)) },
    count=artifact_sample_count,
  )
  let supervision = @bench.single_bench(
    name="actor_supervision_restart",
    fn() { ignore(run_supervision_restart_workload()) },
    count=artifact_sample_count,
  )

  // 负载规模描述（命名常量驱动，禁止 magic number）。
  let entries : Array[String] = [
    render_workload_entry(
      "high_frequency_send",
      "messages=\{send_workload_msgs}",
      send,
    ),
    render_workload_entry(
      "massive_actor_scheduling",
      "actors=\{massive_actor_count},msgs_per_actor=\{massive_msgs_per_actor},total=\{massive_actor_count * massive_msgs_per_actor}",
      scheduling,
    ),
    render_workload_entry(
      "ask_round_trip",
      "round_trips=\{ask_roundtrip_count},step_budget=\{ask_step_budget}",
      ask,
    ),
    render_workload_entry(
      "router_dispatch",
      "strategy=round_robin,workers=\{router_worker_count},msgs=\{router_dispatch_msgs}",
      router,
    ),
    render_workload_entry(
      "supervision_restart",
      "workers=\{supervision_worker_count},tasks=\{supervision_task_count},fault_at=\{supervision_fault_at}",
      supervision,
    ),
  ]
  let doc : Array[String] = [
    "{\"schema\":\"",
    bench_artifact_schema,
    "\",\"machine_id\":\"",
    bench_machine_id,
    "\",\"backend_target\":\"",
    bench_backend_target(),
    "\",\"generator\":\"benches/actor_bench/actor_bench.mbt\",\"timing_unit\":\"microseconds\",\"samples\":\{artifact_sample_count.reinterpret_as_int()},\"workloads\":[",
    entries.join(","),
    "]}",
  ]
  doc.join("")
}

// ───────────────────────────── smoke guard（三后端） ────────────────────

///|
/// Smoke guard：高频 send 串行消费全部消息，trace 长度等于投递条数。
test "smoke: high-frequency send drains all messages serially" {
  let processed = run_send_workload()
  assert_eq(processed, send_workload_msgs)
}

///|
/// Smoke guard：海量 actor 调度处理全部消息（trace 长度 = actor 数 × 每 actor 条数）。
test "smoke: massive actor scheduling processes every message" {
  let processed = run_massive_scheduling_workload()
  assert_eq(processed, massive_actor_count * massive_msgs_per_actor)
}

///|
/// Smoke guard：ask 往返每次都命中 `Replied`（应答 actor 总在预算内回填）。
test "smoke: ask round-trip replies within budget" {
  let replied = run_ask_roundtrip_workload()
  assert_eq(replied, ask_roundtrip_count)
}

///|
/// Smoke guard：三种路由策略均处理消息且不丢失。RoundRobin / ConsistentHash 每条
/// 消息命中一个 worker（trace == msgs）；Broadcast 复制到全部 worker（trace == msgs × workers）。
test "smoke: router dispatch delivers under all strategies" {
  assert_eq(run_router_workload(@actor.RoundRobin), router_dispatch_msgs)
  assert_eq(run_router_workload(@actor.ConsistentHash), router_dispatch_msgs)
  assert_eq(
    run_router_workload(@actor.Broadcast),
    router_dispatch_msgs * router_worker_count,
  )
}

///|
/// Smoke guard：监督重启在单点注入失败后仍完成全部可完成任务（注入的失败任务不计入完成）。
test "smoke: supervision restart completes all completable tasks" {
  let completed = run_supervision_restart_workload()
  assert_eq(completed, supervision_task_count - 1)
}

///|
/// 工件 guard（Requirement 12.2）：生成 JSON 工件并校验含机器标识 / 后端目标 /
/// 五类负载规模 / 计时统计字段；同时 println 工件供采集留痕。
test "artifact: actor_bench emits machine/backend/scale/timing json" {
  let artifact = render_actor_bench_artifact()
  assert_true(artifact.contains(bench_artifact_schema))
  assert_true(artifact.contains(bench_machine_id))
  assert_true(
    artifact.contains("\"backend_target\":\"\{bench_backend_target()}\""),
  )
  // 五类负载。
  assert_true(artifact.contains("high_frequency_send"))
  assert_true(artifact.contains("massive_actor_scheduling"))
  assert_true(artifact.contains("ask_round_trip"))
  assert_true(artifact.contains("router_dispatch"))
  assert_true(artifact.contains("supervision_restart"))
  // 计时统计（来自 @bench.Summary）。
  assert_true(artifact.contains("\"median\":"))
  assert_true(artifact.contains("\"mean\":"))
  println(artifact)
}

// ───────────────────────────── 原生 moon bench 工作负载 ──────────────────

///|
/// Bench ①：高频 send。
test "bench: high-frequency send" (b : @bench.T) {
  b.bench(name="actor_send_\{send_workload_msgs}", fn() {
    b.keep(run_send_workload())
  })
}

///|
/// Bench ②：海量 actor 调度。
test "bench: massive actor scheduling" (b : @bench.T) {
  b.bench(
    name="actor_scheduling_\{massive_actor_count}x\{massive_msgs_per_actor}",
    fn() { b.keep(run_massive_scheduling_workload()) },
  )
}

///|
/// Bench ③：ask 往返。
test "bench: ask round-trip" (b : @bench.T) {
  b.bench(name="actor_ask_roundtrip_\{ask_roundtrip_count}", fn() {
    b.keep(run_ask_roundtrip_workload())
  })
}

///|
/// Bench ④a：路由分发（RoundRobin）。
test "bench: router dispatch round-robin" (b : @bench.T) {
  b.bench(name="actor_router_round_robin_\{router_dispatch_msgs}", fn() {
    b.keep(run_router_workload(@actor.RoundRobin))
  })
}

///|
/// Bench ④b：路由分发（Broadcast）。
test "bench: router dispatch broadcast" (b : @bench.T) {
  b.bench(name="actor_router_broadcast_\{router_dispatch_msgs}", fn() {
    b.keep(run_router_workload(@actor.Broadcast))
  })
}

///|
/// Bench ④c：路由分发（ConsistentHash）。
test "bench: router dispatch consistent-hash" (b : @bench.T) {
  b.bench(name="actor_router_consistent_hash_\{router_dispatch_msgs}", fn() {
    b.keep(run_router_workload(@actor.ConsistentHash))
  })
}

///|
/// Bench ⑤：监督重启（OneForOne 注入失败后重启恢复）。
test "bench: supervision restart" (b : @bench.T) {
  b.bench(
    name="actor_supervision_restart_\{supervision_worker_count}x\{supervision_task_count}",
    fn() { b.keep(run_supervision_restart_workload()) },
  )
}

// ───────────────────────────── 回归 guard（R12.3） ──────────────────────
//
// 设计：记入一张「基线中位数表」（命名常量，单位与工件一致 —— 微秒）与声明容差，
// 比较函数将一次运行的中位数与 baseline×(1+tolerance) 比较，超出即判回归并产出
// **可审计的失败报告**（结构化文本：负载名、基线、实测、容差、允许上限、相对增幅、
// 是否回归）。由于跨机器墙钟计时不稳定，基线值标注为「示意/可更新基线」；guard 判定
// 逻辑本身与基线数值无关、确定性可测（见下方合成数值见证测试），真实计时不进入断言。

///|
/// 回归 guard 的声明容差（相对比例）：实测中位数超过 baseline×(1+tolerance) 判为回归。
/// 跨机器墙钟计时不稳定，统一采用较宽松的 +50% 声明容差（可按机器重新声明）。
let bench_guard_tolerance_ratio : Double = 0.50

///|
/// ① 高频 send 的示意/可更新基线中位数（µs）。
let baseline_send_us : Double = 1500.0

///|
/// ② 海量 actor 调度的示意/可更新基线中位数（µs）。
let baseline_scheduling_us : Double = 4000.0

///|
/// ③ ask 往返的示意/可更新基线中位数（µs）。
let baseline_ask_us : Double = 900.0

///|
/// ④ 路由分发（RoundRobin）的示意/可更新基线中位数（µs）。
let baseline_router_us : Double = 1800.0

///|
/// ⑤ 监督重启的示意/可更新基线中位数（µs）。
let baseline_supervision_us : Double = 1200.0

///|
/// 回归 guard 单条比较输入：负载名、基线中位数（µs）、实测中位数（µs）、声明容差（相对比例）。
priv struct GuardSample {
  workload : String
  baseline_us : Double
  measured_us : Double
  tolerance_ratio : Double
}

///|
/// 回归 guard 单条判定结果：在样本基础上补充允许上限（µs）与是否回归。
priv struct GuardVerdict {
  workload : String
  baseline_us : Double
  measured_us : Double
  allowed_us : Double
  tolerance_ratio : Double
  regressed : Bool
}

///|
/// 比较函数（R12.3）：计算允许上限 baseline×(1+tolerance)，实测超出即判定回归。
fn evaluate_guard_sample(sample : GuardSample) -> GuardVerdict {
  let allowed = sample.baseline_us * (1.0 + sample.tolerance_ratio)
  {
    workload: sample.workload,
    baseline_us: sample.baseline_us,
    measured_us: sample.measured_us,
    allowed_us: allowed,
    tolerance_ratio: sample.tolerance_ratio,
    regressed: sample.measured_us > allowed,
  }
}

///|
/// 将 µs 数值四舍五入为整数（确定性显示，规避 Double 跨后端字符串差异致 flaky）。
fn guard_round(x : Double) -> Int {
  if x >= 0.0 {
    (x + 0.5).to_int()
  } else {
    (x - 0.5).to_int()
  }
}

///|
/// 相对增幅百分比（整数，四舍五入）：(measured-baseline)/baseline×100；baseline≤0 记为 0。
fn guard_delta_pct(baseline : Double, measured : Double) -> Int {
  if baseline <= 0.0 {
    0
  } else {
    guard_round((measured - baseline) / baseline * 100.0)
  }
}

///|
/// 渲染可审计的回归 guard 报告（结构化、确定性）。返回 `(是否存在回归, 报告文本)`。
/// 以 `Array[String]` + `join` 构建，禁止 O(n²) 拼接。
fn render_guard_report(samples : Array[GuardSample]) -> (Bool, String) {
  let mut any_regression = false
  let lines : Array[String] = [
    "ACTOR-BENCH REGRESSION GUARD (timing unit: microseconds)",
    "schema=\{bench_artifact_schema} machine_id=\{bench_machine_id} backend=\{bench_backend_target()}",
    "columns: workload | baseline_us | measured_us | tolerance_pct | allowed_us | delta_pct | verdict",
  ]
  for sample in samples {
    let v = evaluate_guard_sample(sample)
    if v.regressed {
      any_regression = true
    }
    let row : Array[String] = [
      v.workload,
      guard_round(v.baseline_us).to_string(),
      guard_round(v.measured_us).to_string(),
      "\{guard_round(v.tolerance_ratio * 100.0)}%",
      guard_round(v.allowed_us).to_string(),
      "\{guard_delta_pct(v.baseline_us, v.measured_us)}%",
      if v.regressed {
        "REGRESSED"
      } else {
        "OK"
      },
    ]
    lines.push(row.join(" | "))
  }
  let status = if any_regression { "FAIL" } else { "PASS" }
  lines.push("status: \{status}")
  (any_regression, lines.join("\n"))
}

///|
/// 记入的基线表（命名常量驱动）：固定顺序的 `(负载名, 基线中位数 µs, 声明容差比例)`。
/// 顺序与 `collect_actor_bench_medians` 采集顺序一致。
fn actor_bench_baseline_table() -> Array[(String, Double, Double)] {
  [
    ("high_frequency_send", baseline_send_us, bench_guard_tolerance_ratio),
    (
      "massive_actor_scheduling", baseline_scheduling_us, bench_guard_tolerance_ratio,
    ),
    ("ask_round_trip", baseline_ask_us, bench_guard_tolerance_ratio),
    ("router_dispatch", baseline_router_us, bench_guard_tolerance_ratio),
    (
      "supervision_restart", baseline_supervision_us, bench_guard_tolerance_ratio,
    ),
  ]
}

///|
/// 将一次运行的五类中位数（固定顺序）与基线表配对成 guard 样本。
fn actor_bench_guard_samples(measured : Array[Double]) -> Array[GuardSample] {
  let table = actor_bench_baseline_table()
  let samples : Array[GuardSample] = []
  let n = if measured.length() < table.length() {
    measured.length()
  } else {
    table.length()
  }
  for i in 0..<n {
    let (name, base, tol) = table[i]
    samples.push({
      workload: name,
      baseline_us: base,
      measured_us: measured[i],
      tolerance_ratio: tol,
    })
  }
  samples
}

///|
/// 从 `@bench.Summary` 工件中提取 median（µs）。Summary 字段不公开，经其 `ToJson` 读取。
fn summary_median_us(summary : @bench.Summary) -> Double {
  let json = summary.to_json()
  if json is Object(obj) {
    match obj.get("median") {
      Some(m) => if m is Number(n, ..) { n } else { 0.0 }
      None => 0.0
    }
  } else {
    0.0
  }
}

///|
/// 采集五类负载的真实中位数（µs，固定顺序），供真实回归 guard 使用。
fn collect_actor_bench_medians() -> Array[Double] {
  [
    summary_median_us(
      @bench.single_bench(
        name="actor_send",
        fn() { ignore(run_send_workload()) },
        count=artifact_sample_count,
      ),
    ),
    summary_median_us(
      @bench.single_bench(
        name="actor_scheduling",
        fn() { ignore(run_massive_scheduling_workload()) },
        count=artifact_sample_count,
      ),
    ),
    summary_median_us(
      @bench.single_bench(
        name="actor_ask_roundtrip",
        fn() { ignore(run_ask_roundtrip_workload()) },
        count=artifact_sample_count,
      ),
    ),
    summary_median_us(
      @bench.single_bench(
        name="actor_router_round_robin",
        fn() { ignore(run_router_workload(@actor.RoundRobin)) },
        count=artifact_sample_count,
      ),
    ),
    summary_median_us(
      @bench.single_bench(
        name="actor_supervision_restart",
        fn() { ignore(run_supervision_restart_workload()) },
        count=artifact_sample_count,
      ),
    ),
  ]
}

///|
/// 见证测试（R12.3）：以**确定性合成数值**断言 guard 比较判定与可审计报告内容，
/// 三后端稳定通过（不依赖真实墙钟计时）。
test "guard: regression verdict and audit report are deterministic on synthetic medians" {
  // 比较函数：恰在容差边界内（150 = 100×1.5）不算回归，越界（151>150）即回归。
  let within = evaluate_guard_sample({
    workload: "w",
    baseline_us: 100.0,
    measured_us: 150.0,
    tolerance_ratio: 0.50,
  })
  assert_eq(within.allowed_us, 150.0)
  assert_eq(within.regressed, false)
  let over = evaluate_guard_sample({
    workload: "w",
    baseline_us: 100.0,
    measured_us: 151.0,
    tolerance_ratio: 0.50,
  })
  assert_eq(over.regressed, true)

  // 一组合成样本：第三类（ask）注入回归，其余在容差内 → 报告 status=FAIL。
  let samples : Array[GuardSample] = [
    {
      workload: "high_frequency_send",
      baseline_us: 1000.0,
      measured_us: 1200.0,
      tolerance_ratio: 0.50,
    },
    {
      workload: "massive_actor_scheduling",
      baseline_us: 2000.0,
      measured_us: 2500.0,
      tolerance_ratio: 0.50,
    },
    {
      workload: "ask_round_trip",
      baseline_us: 800.0,
      measured_us: 2000.0,
      tolerance_ratio: 0.50,
    },
    {
      workload: "router_dispatch",
      baseline_us: 1500.0,
      measured_us: 1500.0,
      tolerance_ratio: 0.50,
    },
    {
      workload: "supervision_restart",
      baseline_us: 1000.0,
      measured_us: 900.0,
      tolerance_ratio: 0.50,
    },
  ]
  let (failed, report) = render_guard_report(samples)
  assert_eq(failed, true)
  assert_true(report.contains("status: FAIL"))
  // 回归行：allowed=800×1.5=1200，delta=(2000-800)/800=150%，判 REGRESSED。
  assert_true(
    report.contains(
      "ask_round_trip | 800 | 2000 | 50% | 1200 | 150% | REGRESSED",
    ),
  )
  // 持平行：measured=baseline，delta=0%，判 OK。
  assert_true(
    report.contains("router_dispatch | 1500 | 1500 | 50% | 2250 | 0% | OK"),
  )

  // 全部在容差内 → status=PASS、无回归。
  let healthy : Array[GuardSample] = [
    {
      workload: "high_frequency_send",
      baseline_us: 1000.0,
      measured_us: 1000.0,
      tolerance_ratio: 0.50,
    },
    {
      workload: "ask_round_trip",
      baseline_us: 800.0,
      measured_us: 1100.0,
      tolerance_ratio: 0.50,
    },
  ]
  let (ok_failed, ok_report) = render_guard_report(healthy)
  assert_eq(ok_failed, false)
  assert_true(ok_report.contains("status: PASS"))
}

///|
/// 真实回归 guard（R12.3）：采集一次运行的中位数，与记入基线比较，产出可审计报告并
/// `println` 留痕。为避免真实墙钟计时引入 flaky，仅断言报告结构（标题/状态行/五类负载
/// 齐备），**不**对 PASS/FAIL 结论断言（结论随机器而异，由可更新基线声明）。
test "guard: emits auditable report comparing live run to recorded baselines" {
  let medians = collect_actor_bench_medians()
  let samples = actor_bench_guard_samples(medians)
  let (_, report) = render_guard_report(samples)
  assert_true(report.contains("ACTOR-BENCH REGRESSION GUARD"))
  assert_true(report.contains("status: "))
  for entry in actor_bench_baseline_table() {
    let (name, _, _) = entry
    assert_true(report.contains(name))
  }
  println(report)
}
