// eventually.mbt —— DST_Framework 旗舰深化：最终性（eventually）断言与不变量
// 轨迹检查（旁路新增，设计「DST 可执行任务设计」，Requirement 8.5 / 8.6）。
//
// 背景与动机：
//   * 既有 `eval_invariants(World)` 只对**单个**世界状态求值不变量，无法表达
//     「随仿真推进、在某一步**最终**成立」的活性（liveness）性质。
//   * 任务 9.1 新增的 `run_executable` 产出一条 `Array[SimEvent]` 执行轨迹；本
//     文件以该轨迹为可观测对象，提供两类时序断言，二者签名均直接消费 9.1 的
//     `Array[SimEvent]` 输出，可无缝衔接：
//       1. `eventually`           —— 活性：某断言在有限步内最终成立（AC6）；
//       2. `check_invariant_over` —— 安全性：某不变量在任一可观测状态下成立，
//                                     否则报告违例及发生步（AC5）。
//
// 「前缀即可观测状态」模型：
//   一条轨迹 `trace` 的第 i 个可观测状态，定义为「执行完前 i+1 个事件后」的状态，
//   由前缀 `trace[0..=i]` 表示（i 从 0 计）。逐前缀推进即逐事件推进仿真，与
//   `run_executable` 的逐事件产出语义一致。两个断言均按此模型对每个前缀求值。
//
// 与设计文档的签名取齐说明：设计稿原列 `eventually(DesResult, (World) -> Bool)`，
// 而 9.1 落地后执行轨迹的可观测载体是 `Array[SimEvent]`（非 `World` 序列）。为
// 与 9.1 的实际输出衔接，本文件采用基于轨迹前缀的签名
// `eventually(Array[SimEvent], (Array[SimEvent]) -> Bool)`，语义等价且更贴合
// 既有数据流；既有 `eval_invariants` / `Invariant`（基于 `World`）保持不变。

///|
/// 最终性断言的结果（`EventuallyResult`）：
///   * `EHolds(step~)` —— 断言在第 `step` 个可观测状态（前缀 `trace[0..=step]`）
///                        **首次**成立；`step` 为 0 起的事件下标；
///   * `ENeverHeld`    —— 直至仿真终止（遍历完整轨迹）断言仍从未成立（AC6 失败）。
///
/// 含数据字段，派生 `Eq` 以便断言比较；`Show` 手写（当前 MoonBit 版本
/// `derive(Debug)` 已弃用，手写以保持新文件零警告）。
///
/// 声明为 `pub(all)`（与既有 `TaskResult` / `SimEvent` 等公开枚举一致），使其
/// 构造子在包外可直接构造与模式匹配，便于调用方判定最终性结果与编写断言。
pub(all) enum EventuallyResult {
  EHolds(step~ : Int)
  ENeverHeld
} derive(Eq)

///|
/// 手写 `Show`：以与派生实现一致的形态输出构造子名称与字段，便于测试快照与诊断。
pub impl Show for EventuallyResult with fn output(
  self : EventuallyResult,
  logger : &Logger,
) -> Unit {
  match self {
    EHolds(step~) => {
      logger.write_string("EHolds(step=")
      Show::output(step, logger)
      logger.write_string(")")
    }
    ENeverHeld => logger.write_string("ENeverHeld")
  }
}

///|
/// 最终性（eventually）断言（AC6）：逐前缀检查谓词 `pred`，返回**首个**使其成立
/// 的前缀对应的步号 `EHolds(step)`；若遍历完整轨迹（仿真终止）仍无任何前缀使
/// `pred` 成立，则返回 `ENeverHeld`，刻画「最终性在仿真终止时仍未达成」的失败。
///
/// 语义（逐前缀 / 逐事件）：对 i = 0,1,…,len-1，依次构造前缀 `trace[0..=i]` 并对其
/// 求值 `pred`；命中即返回 `EHolds(step=i)`。空轨迹无任何可观测状态，直接返回
/// `ENeverHeld`。
///
/// 复杂度：前缀以单一缓冲增量增长（每步仅 `push` 一个事件，O(1) 摊还），全程
/// O(len) 次 `push` + O(len) 次 `pred` 调用，不做任何前缀复制，避免 O(n²) 重建。
pub fn eventually(
  trace : Array[SimEvent],
  pred : (Array[SimEvent]) -> Bool,
) -> EventuallyResult {
  // 增量增长的前缀缓冲：第 i 轮迭代后其内容恰为 trace[0..=i]。
  let prefix : Array[SimEvent] = []
  for i in 0..<trace.length() {
    prefix.push(trace[i])
    if pred(prefix) {
      return EHolds(step=i)
    }
  }
  ENeverHeld
}

///|
/// 不变量轨迹检查（AC5）：把不变量 `inv`（对可观测状态的布尔断言）施加到轨迹的
/// **每个前缀**上；若某前缀使其不成立，返回 `Some(<报告>)`，报告标识被违反的
/// 不变量名称与发生的步号；若全程成立则返回 `None`。
///
/// 与 `eventually` 互补：`eventually` 表达活性（最终成立），本函数表达安全性
/// （始终成立）。二者共用「前缀即可观测状态」模型，步号语义一致。
///
/// 报告文本以单次字符串插值构造（非循环内累积拼接），符合高效文本构建约束。
pub fn check_invariant_over(
  trace : Array[SimEvent],
  name~ : String,
  inv : (Array[SimEvent]) -> Bool,
) -> String? {
  // 增量增长的前缀缓冲：第 i 轮迭代后其内容恰为 trace[0..=i]。
  let prefix : Array[SimEvent] = []
  for i in 0..<trace.length() {
    prefix.push(trace[i])
    if !inv(prefix) {
      // 单次插值拼接，报告违例的不变量名称与发生步号（可观测状态）。
      return Some(
        "不变量 \{name} 于步 \{i} 被违反：该可观测状态下断言不成立",
      )
    }
  }
  None
}
