// samplers.mbt —— T7.3 OTel 采样器对标（纲领方向七）。
//
// 对标 OpenTelemetry SDK 规范的四种内置采样器（Built-in samplers）：
//
//   * `AlwaysOn`  —— 恒采（对应 OTel AlwaysOnSampler）；
//   * `AlwaysOff` —— 恒弃（对应 OTel AlwaysOffSampler）；
//   * `TraceIdRatio(rate)` —— 按 trace 标识比例采样（对应 OTel
//     TraceIdRatioBased）：决策仅由 trace 标识与配置决定（复用 sampling.mbt
//     的 `sample_trace` 纯整型混合），同一 trace 恒定（trace-coherent）、
//     三后端逐位一致；
//   * `ParentBased(root)` —— 父级采样（对应 OTel ParentBased 组合器）：有父
//     决策时**尊重父决策**（父采则采、父弃则弃），根 span（无父）时委托给
//     `root` 采样器。OTel 规范默认 root = AlwaysOn；本实现允许任意根采样器
//     （含嵌套 ParentBased，语义为一路下钻到非 ParentBased 的根采样器）。
//
// 与 OTel 规范的取舍：不实现 remote-parent 四分支细化（本包 trace 上下文
// 无 remote 位），本地/远端父统一按「父决策」处理——这是规范允许的
// ParentBased(root, remoteParentSampled=RecordAndSample,
// remoteParentNotSampled=Drop, ...) 默认参数的语义投影。

///|
/// OTel 内置采样器（Built-in samplers）。
pub(all) enum Sampler {
  AlwaysOn
  AlwaysOff
  TraceIdRatio(Double)
  ParentBased(Sampler)
} derive(Eq, Debug)

///|
/// 采样决策（对应 OTel SamplingDecision 的 Drop / RecordAndSample 两态投影）。
///
/// `parent_sampled`：父 span 的采样决策；`None` 表示根 span（无父）。
/// 决策纯函数：仅由采样器配置、父决策与 trace 标识决定，确定性、可重放、
/// 三后端逐位一致。
pub fn Sampler::should_sample(
  self : Sampler,
  parent_sampled : Bool?,
  trace : TraceId,
  seed : UInt64,
) -> Bool {
  match self {
    AlwaysOn => true
    AlwaysOff => false
    TraceIdRatio(rate) => sample_trace(rate, trace, seed)
    ParentBased(root) =>
      match parent_sampled {
        Some(decision) => decision
        None => root.should_sample(None, trace, seed)
      }
  }
}
