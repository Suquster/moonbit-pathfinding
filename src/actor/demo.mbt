// demo.mbt —— 受监督工作池端到端示例（任务 14.1，Requirement 11）。
//
// 本文件把前序各能力（路由器、监督策略、生命周期重启、死亡监视、请求-响应 ask、
// 种子驱动确定性调度）串成一个**贯穿文档与基准的工作池场景**，对外仅暴露一个
// 入口 `worker_pool_demo` 与两个可观测数据类型 `Task` / `WorkerPoolReport`：
//
//   ① coordinator 以路由策略派生并监督 `worker_count` 个 worker（R11.1）；
//   ② router（RoundRobin）把 `tasks` 分发给各 worker 处理（R11.2）；
//   ③ 某 worker 处理被注入错误的任务而 `Errored`，在 `OneForOne` 策略下**仅该
//      worker 重启**，其它 worker 不受影响继续处理（R11.3）；
//   ④ coordinator `watch` 各 worker，worker 终止时收到 `Terminated` 通知（R11.4）；
//   ⑤ client 以 `ask` 取回各 worker 的完成计数，得到匹配响应或确定性 `Timeout`（R11.5）。
//
// 全部能力复用既有平行类型（`ActorSystem` / `Router` / `AskBroker` / `WatchRegistry`
// 等），不修改任何冻结的既有 `pub(all)` 类型；失败一律以显式枚举信号表达、调度由
// 种子 `Rng` 驱动，保证三后端逐位一致、同种子可重放。

// ───────────────────────────── 可调参数（命名常量） ─────────────────────

///|
/// 工作池监督的最大重启强度上界（窗口内至多重启次数）—— 取足够宽松值，使单点
/// 注入失败能在 `OneForOne` 下重启而不被强度上限提前升级/停止。
let demo_max_restarts : Int = 1000

///|
/// 重启强度的逻辑时钟窗口长度（step 计数）—— 取足够大值覆盖整个示例运行。
let demo_restart_window : Int = 1000000

///|
/// 单次 `ask` 的步数预算 —— 每个 worker 至多一条 ask 请求待处理，少量步即可命中。
let demo_ask_budget : Int = 16

// ───────────────────────────── 可观测数据类型 ───────────────────────────

///|
/// 任务（task）—— 工作池分发的工作单元。
///
///   * `id`      —— 任务标识（便于追踪）；
///   * `payload` —— 任务负载（worker 处理时消费）。
pub(all) struct Task {
  id : Int
  payload : Int
} derive(Eq, Show)

///|
/// 工作池运行报告（worker pool report）—— 端到端场景的可观测结果（R11）：
///
///   * `completed`       —— 成功完成的（可完成）任务总数；
///   * `restarts`        —— 全部 worker 累计被重启的次数（OneForOne 下注入失败触发）；
///   * `terminated_seen` —— coordinator 作为监视者收到的 `Terminated` 来源 id（R11.4）；
///   * `ask_results`     —— 对各 worker 以 `ask` 取回完成计数的结果（R11.5）。
pub(all) struct WorkerPoolReport {
  completed : Int
  restarts : Int
  terminated_seen : Array[ActorId]
  ask_results : Array[AskResult[Int]]
} derive(Eq, Show)

// ───────────────────────────── 工作池消息协议 ───────────────────────────

///|
/// 工作池消息（pool message）—— coordinator 与 worker 共享的消息类型 `M`。
///
/// 变体名刻意避开包内既有构造子（如 `ContextEffect::Watch`）以消除歧义：
///
///   * `RunTask(Task)`    —— 普通任务，worker 成功处理并计入完成计数；
///   * `FaultTask(Task)`  —— 注入失败的任务，worker 处理时 `Errored`；
///   * `AskCount(CorrelationId)` —— ask 请求，worker 回填其完成计数；
///   * `WatchWorker(ActorId)`    —— 指示 coordinator 监视某 worker；
///   * `WorkerDown(ActorId, TerminationReason)` —— 监视者收到的终止通知（经适配器映射）。
pub(all) enum PoolMsg {
  RunTask(Task)
  FaultTask(Task)
  AskCount(CorrelationId)
  WatchWorker(ActorId)
  WorkerDown(ActorId, TerminationReason)
} derive(Eq, Show)

// ───────────────────────────── 行为构造 ─────────────────────────────────

///|
/// worker 行为：处理任务并维护「自启动以来完成的任务数」作为其状态。
///
///   * `RunTask`   —— 完成计数 +1（共享累加器 `completed_ref` 持久于重启，确保未失败
///                    结果不丢失）、状态 +1；
///   * `FaultTask` —— 返回 `Errored` 触发监督（当前消息被丢弃、不重放，R3.4）；
///   * `AskCount`  —— 经 `broker` 回填当前完成计数（ask 响应，R4.3）；
///   * 其余消息（WatchWorker / WorkerDown）—— worker 不关心，原样保持状态。
///
/// `completed_ref` 为单元素数组，作为跨重启持久的共享完成计数器：worker 自身状态在
/// 重启时被重置为初始值（R3.5），而已完成的任务数不应因某 worker 重启而回退。
fn worker_behavior(
  broker : AskBroker[Int],
  completed_ref : Array[Int],
) -> Behavior[Int, PoolMsg] {
  Behavior::new(fn(_ctx, s, msg) {
    match msg {
      RunTask(_) => {
        completed_ref[0] = completed_ref[0] + 1
        Updated(s + 1)
      }
      FaultTask(_) => Errored("injected fault")
      AskCount(corr) => {
        broker.fulfill(corr, s)
        Updated(s)
      }
      WatchWorker(_) => Updated(s)
      WorkerDown(_, _) => Updated(s)
    }
  })
}

///|
/// coordinator 行为：登记对 worker 的监视，并在收到 `Terminated` 时记录来源。
///
///   * `WatchWorker(target)` —— 经 `ctx.watch` 登记监视，附 Akka `watchWith` 风格
///                              适配器把终止通知映射为 `WorkerDown`（R7.1）；
///   * `WorkerDown(id, _)`   —— 记录终止来源 id，状态计数 +1（R11.4）；
///   * 其余消息 —— coordinator 不参与任务处理，原样保持状态。
///
/// `terminated_ref` 为共享数组，收集 coordinator 收到的全部终止来源 id。
fn coordinator_behavior(
  terminated_ref : Array[ActorId],
) -> Behavior[Int, PoolMsg] {
  Behavior::new(fn(ctx, s, msg) {
    match msg {
      WatchWorker(target) => {
        ctx.watch(target, fn(id, reason) { WorkerDown(id, reason) })
        Updated(s)
      }
      WorkerDown(id, _) => {
        terminated_ref.push(id)
        Updated(s + 1)
      }
      _ => Updated(s)
    }
  })
}

// ───────────────────────────── 端到端入口 ───────────────────────────────

///|
/// 受监督工作池端到端示例（R11.1~R11.5）。
///
/// 串联路由分发、监督重启、死亡监视与 ask 四项能力：
///
///   1. 以种子 `seed` 构造确定性 `ActorSystem`，派生 1 个 coordinator 与
///      `worker_count` 个 worker，并以 `OneForOne` 策略将 worker 置于 coordinator
///      监督之下（R11.1）；
///   2. coordinator 监视全部 worker（R11.4 的前置登记）；
///   3. 以 `RoundRobin` 路由器把 `tasks` 分发给各 worker；`fault_at` 指定的任务被
///      注入为失败任务，触发该 worker 在 `OneForOne` 下重启、其它 worker 不受影响
///      （R11.2 / R11.3）；
///   4. 以 `ask` 取回各 worker 的完成计数（R11.5）；
///   5. 停止全部 worker，coordinator 收到各自的 `Terminated` 通知（R11.4）；
///   6. 汇总为 `WorkerPoolReport`。
///
/// 同一 `seed` 的两次运行产生逐事件一致的处理序列（确定性可重放，R10）。
pub fn worker_pool_demo(
  worker_count : Int,
  tasks : Array[Task],
  fault_at : Int?,
  seed : UInt64,
) -> WorkerPoolReport {
  let broker : AskBroker[Int] = AskBroker::new()
  let completed_ref : Array[Int] = [0]
  let terminated_ref : Array[ActorId] = []
  let sys : ActorSystem[Int, PoolMsg] = ActorSystem::with_seed(seed)

  // ① coordinator 派生并监督一组 worker（OneForOne）。
  let coordinator = sys.spawn(0, coordinator_behavior(terminated_ref))
  let workers : Array[ActorRef[PoolMsg]] = []
  for _i in 0..<worker_count {
    workers.push(sys.spawn(0, worker_behavior(broker, completed_ref)))
  }
  sys.supervise(
    coordinator,
    SupervisorSpec::new(
      OneForOne,
      RestartIntensity::new(demo_max_restarts, demo_restart_window),
      Restart,
    ),
    workers,
  )

  // ② coordinator watch 每个 worker（先注册监视，停止阶段收 Terminated）。
  for w in workers {
    coordinator.send(WatchWorker(w.id))
  }
  sys.run_until_idle()

  // ③ router 按 RoundRobin 分发任务；fault_at 处注入失败触发 OneForOne 重启。
  let router = Router::new(RoundRobin, workers)
  for i in 0..<tasks.length() {
    let faulty = match fault_at {
      Some(k) => k == i
      None => false
    }
    if faulty {
      router.route(FaultTask(tasks[i]))
    } else {
      router.route(RunTask(tasks[i]))
    }
  }
  sys.run_until_idle()

  // ④ client 以 ask 取回各 worker 的完成计数（Replied 或确定性 Timeout）。
  let ask_results : Array[AskResult[Int]] = []
  for w in workers {
    ask_results.push(
      ask(sys, broker, w, fn(id) { AskCount(id) }, demo_ask_budget),
    )
  }

  // ⑤ 停止全部 worker，coordinator 收到 Terminated 通知。
  for w in workers {
    w.stop()
  }
  sys.run_until_idle()

  // ⑥ 汇总报告：完成总数、重启次数、收到的终止来源、ask 结果。
  let mut restarts = 0
  for w in workers {
    restarts = restarts + sys.restart_count(w)
  }
  {
    completed: completed_ref[0],
    restarts,
    terminated_seen: terminated_ref,
    ask_results,
  }
}
