// executor.mbt —— 构建动作执行框架（旗舰深化，旁路新增 / bypass）。
//
// 设计依据（design.md §「Build Executor 框架设计」，Requirement 3）：在既有
// `BuildGraph` / `Target` / `schedule`（Kahn 分层）/ `content_hash` / `cache_key`
// 之上，新增「动作（Action）—— 执行器（Executor）—— 并行调度（ParallelSchedule）
// —— 构建日志（BuildLog）」执行框架。对标 Haskell `Shake` 的调度模型：声明式
// 动作 + 依赖分层并行 + 内容寻址增量。
//
// 冻结复用原则（只增不减）：本文件不修改任何既有公开签名，`Action::fingerprint`
// 复用既有 `content_hash` / `cache_key`（cache.mbt）的单射编码；
// `build_parallel_schedule` 复用既有 `schedule` 的 Kahn 分层逻辑（build_tool.mbt），
// 仅在动作 id 与 `Target` 之间做无损映射。
//
// 反模式禁令：动作指纹拼接以 @infra_text.TextBuilder 物化（禁止循环内字符串
// `+`）；无 `abort()` / `todo!()` / `panic` 占位；分隔符等以命名常量表达
// （禁止 magic number）。
//
// 行为映射（Requirement 3 验收准则）：
//   * AC1 —— `Action` 声明 inputs / outputs / command / id；
//   * AC2 —— `DryRunExecutor` 仅记录到 `log`，返回 `Skipped`，无外部副作用；
//   * AC3 —— `CallbackExecutor` 调用回调取其返回 output_hash，产出 `Executed`；
//   * AC4 / AC7 —— `build_parallel_schedule` 按依赖边 Kahn 分层，同一波次内
//     任意两动作无依赖路径，全波次展开为全部动作各一次（不重不漏）；
//   * AC5 —— `BuildLog` 记录每个已执行动作的指纹与结果；
//   * AC6 —— `is_up_to_date` 比对当前指纹与已记录指纹，相同则可跳过（增量）。

// ───────────────────────────── 命名常量 ─────────────────────────────

///|
/// 动作指纹中「长度前缀编码」分隔长度与内容的定界符。
///
/// 与 cache.mbt 的 `lp` 长度前缀编码同源思想：`<len><delim><content>` 使
/// 字段边界由「十进制长度 + 定界符 + 恰 len 个字符」唯一确定，拼接可无歧义
/// 解析，故输出片段序列对指纹的贡献是单射的（避免不同输出集合偶然同指纹）。
let fingerprint_field_delim : Char = '|'

///|
/// 不限并行度的调度并行度参数：复用 `schedule(g, jobs)` 中 `jobs <= 0` 表示
/// 「整层一批」的约定，使每个波次恰为一个「相互无依赖的就绪集合」。
let unlimited_parallelism : Int = 0

// ───────────────────────────── 动作模型 ─────────────────────────────

///|
/// 构建动作（build action）—— 执行框架的最小调度单元（AC1）。
///
///   * `id`      —— 动作唯一标识（用作调度节点名与 `BuildLog` 主键）；
///   * `inputs`  —— 输入资源标识（参与指纹，输入变化即指纹变化）；
///   * `outputs` —— 产物标识（参与指纹）；
///   * `command` —— 执行命令（参与指纹）。
///
/// 以 `pub(all)` 暴露字段，便于宿主与属性测试直接构造动作（与本包既有
/// `ActionCache` / `Recipe` / `Rule` / `Provenance` 等数据结构的可见性一致）。
pub(all) struct Action {
  id : String
  inputs : Array[String]
  outputs : Array[String]
  command : String
} derive(Eq)

///|
/// 以可读形式展示动作（便于诊断与测试失败信息阅读）。
///
/// 手写 `Show`（而非 `derive(Debug)`）以规避 `derive(Debug)` 的弃用告警，
/// 与本包 `Target` 的处理一致；逐字段经 `logger.write_string` 写出，
/// 不做循环字符串拼接（无 `out = out + ...` 反模式）。
pub impl Show for Action with fn output(self : Action, logger : &Logger) -> Unit {
  logger.write_string("Action(id=")
  logger.write_string(self.id)
  logger.write_string(", command=")
  logger.write_string(self.command)
  logger.write_string(", inputs=[")
  logger.write_string(self.inputs.join(","))
  logger.write_string("], outputs=[")
  logger.write_string(self.outputs.join(","))
  logger.write_string("])")
}

///|
/// 动作指纹：对 `command` / `outputs` 复合内容哈希后，与 `id` / `inputs` 一并
/// 经既有 `cache_key`（长度前缀单射编码）合成（AC5 / AC6 的比对依据）。
///
/// 复用既有资产：`content_hash` 做 64 位 FNV-1a 摘要、`cache_key` 做单射编码，
/// 二者三后端逐位一致。输出片段拼接以 `TextBuilder` 物化，避免循环内 `+`。
/// 相同动作恒得相同指纹（确定性）；任一字段不同极大概率得不同指纹。
pub fn Action::fingerprint(self : Action) -> String {
  // 命令维度指纹。
  let cmd_fp = content_hash(self.command)
  // 输出维度指纹：对每个输出做长度前缀编码后整体哈希（TextBuilder 物化）。
  let out_tb = @infra_text.TextBuilder::new()
  for o in self.outputs {
    out_tb.push_str(o.length().to_string())
    out_tb.push_char(fingerprint_field_delim)
    out_tb.push_str(o)
  }
  let out_fp = content_hash(out_tb.build())
  // 复合动作指纹：命令指纹与输出指纹的有界顺序拼接（≤3 次 `+`，非循环，允许）。
  let action_fp = content_hash(cmd_fp + "|" + out_fp)
  // 以既有 cache_key 的单射编码合成：target=id、inputs 直接参与、action_fp 收尾。
  cache_key(self.id, self.inputs, action_fp)
}

///|
/// 动作执行结果（AC2 / AC3）：
///   * `Executed(output_hash~)` —— 实际执行，携带产物内容哈希；
///   * `Skipped` —— 未执行（dry-run 或增量命中，视为 up-to-date）。
pub(all) enum ActionResult {
  Executed(output_hash~ : String)
  Skipped
} derive(Eq, Debug)

///|
/// 以可读形式展示执行结果（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
pub impl Show for ActionResult with fn output(
  self : ActionResult,
  logger : &Logger,
) -> Unit {
  match self {
    Executed(output_hash~) => {
      logger.write_string("Executed(output_hash=")
      logger.write_string(output_hash)
      logger.write_string(")")
    }
    Skipped => logger.write_string("Skipped")
  }
}

// ───────────────────────────── 执行器抽象 ─────────────────────────────

///|
/// 执行器抽象（AC2 / AC3）：把「如何执行一个动作」从「调度顺序」中解耦。
///
/// 以 trait object（`&Executor`）传入 `run_actions`，使 dry-run / 回调委派
/// 等多种执行策略共享同一调度驱动。仓库无真实进程执行能力，故不内建 shell
/// 执行器，保持确定性可测（design.md §「设计决策」4）。
pub trait Executor {
  fn execute(Self, Action) -> ActionResult
}

///|
/// 干跑执行器（dry-run，AC2）：仅把动作记录到 `log`，不产生任何外部副作用，
/// 返回 `Skipped`。用于「预览将执行哪些动作及其顺序」。
pub struct DryRunExecutor {
  // 注：设计稿写作 `mut log`，但 MoonBit 中向 `Array` 追加（push）属容器内部
  // 变更、无需字段可重新赋值，保留 `mut` 会触发 unused_mut 报错；故去除 `mut`，
  // 语义等价（仍可 push 记录），符合「以可编译为准」。
  log : Array[Action]
}

///|
/// 构造空的干跑执行器。
pub fn DryRunExecutor::new() -> DryRunExecutor {
  { log: [] }
}

///|
/// 取干跑期间累计记录的动作序列（按 `execute` 调用顺序，AC2 的可观察证据）。
pub fn DryRunExecutor::recorded(self : DryRunExecutor) -> Array[Action] {
  self.log
}

///|
/// 干跑执行：记录动作到内部日志（无外部副作用），返回 `Skipped`（AC2）。
pub impl Executor for DryRunExecutor with fn execute(
  self : DryRunExecutor,
  action : Action,
) -> ActionResult {
  self.log.push(action)
  Skipped
}

///|
/// 回调执行器（AC3）：把执行委派给回调 `cb`，以其返回值作为产物内容哈希，
/// 产出 `Executed(output_hash=...)`。便于在测试 / 宿主侧注入真实执行语义。
pub struct CallbackExecutor {
  cb : (Action) -> String
}

///|
/// 由回调构造回调执行器。
pub fn CallbackExecutor::new(cb : (Action) -> String) -> CallbackExecutor {
  { cb, }
}

///|
/// 回调执行：调用 `cb(action)` 取产物哈希，产出 `Executed`（AC3）。
pub impl Executor for CallbackExecutor with fn execute(
  self : CallbackExecutor,
  action : Action,
) -> ActionResult {
  let output_hash = (self.cb)(action)
  Executed(output_hash~)
}

// ───────────────────────────── 并行调度 ─────────────────────────────

///|
/// 并行调度（AC4 / AC7）：按依赖关系分层的动作波次。同一波次内的动作相互
/// 无依赖路径，可并行执行；波次间严格满足「依赖先于被依赖」的拓扑序。
pub(all) struct ParallelSchedule {
  waves : Array[Array[Action]]
}

///|
/// 由动作集合与依赖边构造并行调度（AC4 / AC7，Kahn 分层）。
///
/// 依赖边语义：`(from_id, to_id)` 表示 `from_id` 必须在 `to_id` 之前执行
/// （即 `to_id` 依赖 `from_id`），与既有 `schedule` 的边语义一致。
///
/// 实现复用既有 `schedule`：把动作 id 映射为 `Target` 节点、依赖边映射为
/// `(Target, Target)` 边，调用 `schedule(g, 0)`（不限并行度，整层一波）得到
/// `Array[Array[Target]]` 波次，再按 id 无损映射回 `Action`。对无环输入，
/// 全波次展开恰为全部动作各一次（不重不漏）。
pub fn build_parallel_schedule(
  actions : Array[Action],
  edges : Array[(String, String)],
) -> ParallelSchedule {
  // 建立 id -> Action 映射与调度节点集。
  let by_id : Map[String, Action] = Map([])
  let nodes : Array[Target] = []
  for a in actions {
    by_id[a.id] = a
    nodes.push(Target::new(a.id))
  }
  // 依赖边映射：from_id 在前、to_id 在后（to_id 依赖 from_id）。
  let graph_edges : Array[(Target, Target)] = []
  for e in edges {
    let (from_id, to_id) = e
    graph_edges.push((Target::new(from_id), Target::new(to_id)))
  }
  let graph = BuildGraph::new(nodes, graph_edges)
  // 复用既有 Kahn 分层：jobs<=0 → 每个波次为一个完整就绪集合。
  let target_waves = schedule(graph, unlimited_parallelism)
  let waves : Array[Array[Action]] = []
  for tw in target_waves {
    let wave : Array[Action] = []
    for t in tw {
      match by_id.get(t.name) {
        Some(a) => wave.push(a)
        None => () // 边引用的未登记节点：schedule 已忽略，这里同样跳过。
      }
    }
    waves.push(wave)
  }
  { waves, }
}

// ───────────────────────────── 构建日志 ─────────────────────────────

///|
/// 构建日志（AC5 / AC6）：动作 id → (该动作执行时的指纹, 执行结果)。
///
/// 作为增量构建的持久记录：再次构建时若动作指纹与记录一致，则该动作 up-to-date
/// 可跳过（`is_up_to_date`）。
pub struct BuildLog {
  entries : Map[String, (String, ActionResult)]
}

///|
/// 构造空构建日志。
pub fn BuildLog::new() -> BuildLog {
  { entries: Map([]) }
}

///|
/// 记录一个动作的执行：登记其当前指纹与执行结果（AC5）。
pub fn BuildLog::record(
  self : BuildLog,
  action : Action,
  result : ActionResult,
) -> Unit {
  self.entries[action.id] = (action.fingerprint(), result)
}

///|
/// 判定动作是否 up-to-date（AC6）：存在同 id 记录且记录指纹 == 当前指纹则为
/// `true`（可跳过）；否则 `false`（需执行）。
pub fn BuildLog::is_up_to_date(self : BuildLog, action : Action) -> Bool {
  match self.entries.get(action.id) {
    Some((recorded_fp, _)) => recorded_fp == action.fingerprint()
    None => false
  }
}

// ───────────────────────────── 调度驱动 ─────────────────────────────

///|
/// 按并行调度逐波次驱动执行（AC4 / AC5 / AC6）。
///
/// 对每个波次内的每个动作：若 `log.is_up_to_date(action)` 则跳过（增量，
/// 保留既有记录）；否则交由 `exec` 执行并把结果记入 `log`。返回（被原地更新的）
/// `log`，便于链式与断言。
pub fn run_actions(
  sched : ParallelSchedule,
  exec : &Executor,
  log : BuildLog,
) -> BuildLog {
  for wave in sched.waves {
    for action in wave {
      if log.is_up_to_date(action) {
        continue // 指纹未变：增量跳过，保留既有记录。
      }
      let result = exec.execute(action)
      log.record(action, result)
    }
  }
  log
}
