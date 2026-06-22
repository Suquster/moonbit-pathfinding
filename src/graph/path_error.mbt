// path_error.mbt —— 结构化寻路错误类型 `PathError`（5 互斥变体）。
//
// 设计依据（design.md §「方向 4 · 4.1 PathError」/ Requirement 13）：
//   寻路算法的失败可归为五种互斥原因，每种原因对应唯一枚举变体。本类型
//   以新增方式提供（bypass），与既有 `@core.PathError`（4 变体）命名空间
//   隔离、互不影响（Requirement 13.8）：既有返回 `Option` 的算法签名保持
//   冻结，新增的「结构化失败」入口返回 `Result[_, @graph.PathError]`。
//
// 关键不变量：
//   * Requirement 13.1：五变体互斥且穷尽，每种失败原因唯一对应一个变体。
//   * Requirement 13.7：`message()` 返回非空、且能唯一标识所属失败原因的
//     人类可读诊断串；其构建过程使用 `@infra_text.TextBuilder`，不在循环内
//     做字符串 `+` 累加拼接。
//   * Requirement 22.6：以精确枚举表示结构化数据，不用字符串模拟。

///|
/// 结构化寻路错误：以枚举区分且仅区分五种互斥的失败原因。
///
/// 五种变体各对应一种唯一的失败语义（Requirement 13.1）：
///
/// - `SourceNotFound`：源节点不在图中，算法无法从一个不存在的起点出发
///   （Requirement 13.2）。
/// - `TargetNotFound`：目标节点不在图中，查询的终点无从定位
///   （Requirement 13.3）。
/// - `Unreachable`：源与目标均在图中，但在当前图结构下目标从源不可达
///   （Requirement 13.4）。
/// - `NegativeCycle`：源到目标的某条可达路径上存在负权环，导致无法给出
///   有限最短路（Requirement 13.5）。
/// - `InvalidArgument(String)`：算法接收到非法的输入参数；附带的字符串
///   用于携带具体的诊断细节（Requirement 13.6）。
///
/// 派生 `Eq` 以支持等值比较（变体判定与测试断言），派生 `Show` 以支持
/// 调试输出。注意 `Show` 的派生形式是面向调试的结构化表示，而面向人类的
/// 诊断文案由 `message()` 提供。
pub(all) enum PathError {
  /// 源节点不存在（Requirement 13.2）。
  SourceNotFound
  /// 目标节点不存在（Requirement 13.3）。
  TargetNotFound
  /// 目标不可达（Requirement 13.4）。
  Unreachable
  /// 检测到负权环（Requirement 13.5）。
  NegativeCycle
  /// 输入参数非法，附带诊断细节（Requirement 13.6）。
  InvalidArgument(String)
} derive(Eq, Show)

///|
/// 返回该错误变体对应的、人类可读的诊断消息字符串。
///
/// 行为保证（Requirement 13.7）：
///
/// - **非空**：每个变体均返回长度大于 0 的字符串。
/// - **变体唯一可辨**：不同变体的消息文案两两互异，因此可由消息内容唯一
///   反推其所属失败原因。对 `InvalidArgument`，其消息以固定前缀打头并附上
///   具体细节，即使细节为空也仍与其余四个变体的消息互异。
/// - **无 O(n²) 拼接**：消息通过 `@infra_text.TextBuilder` 顺序追加片段、
///   一次性物化，绝不在循环体内使用字符串 `+` 累加（Requirement 13.7 /
///   22.4）。本方法不含任何循环，单次追加亦合规。
///
/// 诊断文案采用「英文标识 + 中文说明」的稳定形式，便于日志检索与人工阅读。
pub fn PathError::message(self : PathError) -> String {
  let tb = @infra_text.TextBuilder::new()
  match self {
    SourceNotFound => tb.push_str("SourceNotFound: 源节点不存在于图中")
    TargetNotFound =>
      tb.push_str("TargetNotFound: 目标节点不存在于图中")
    Unreachable =>
      tb.push_str("Unreachable: 目标在当前图结构下从源不可达")
    NegativeCycle =>
      tb.push_str(
        "NegativeCycle: 源到目标的可达路径上存在负权环，无法给出有限最短路",
      )
    InvalidArgument(detail) => {
      // 固定前缀保证与其余变体互异；附带细节提供具体诊断。
      // 仅两次顺序 push（非循环），符合无 O(n²) 拼接约束。
      tb.push_str("InvalidArgument: 输入参数非法；")
      tb.push_str(detail)
    }
  }
  tb.build()
}
