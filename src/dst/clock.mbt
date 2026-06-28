// clock.mbt —— DST_Framework 旗舰深化：逻辑时钟 / 虚拟时间（旁路新增，设计 4.1）。
//
// paper-to-code 追溯：
//   * 虚拟时间（virtual time）与离散事件仿真（discrete-event simulation, DES）——
//     事件按「逻辑时间戳」全序出队、处理后产生未来事件入队。本方向以与真实墙
//     钟无关的离散度量 `LogicalTime` 推进仿真（FoundationDB 确定性仿真亦以虚拟
//     时间驱动可重放执行）。
//
// 设计要点（与既有 sim.mbt 的「步进式」流水线严格隔离、旁路扩展）：
//   * 统一以 `UInt64` 表示逻辑时间戳，保证 wasm-gc / js / native 三后端整数语义
//     逐位一致且无溢出风险（不使用浮点、不依赖平台特定整数行为）。
//   * 全序约定（R1.3，事件队列与 `World::step` 的处理顺序依据）：当同一逻辑时间
//     存在多个待处理事件时，按
//
//         （逻辑时间戳升序，任务 id 升序，确定性次序键升序）
//
//     决定处理顺序；次序键由单调入队序号 / 消息 id 给出，使平局打破完全确定。
//   * 逻辑时间沿事件出队单调不减（R1.2）：DES 引擎为每个「处理动作」分配一个
//     严格递增的逻辑时间戳，故产出事件轨迹天然满足上述全序。

///|
/// 逻辑时间（logical time）/ 虚拟时间——与真实墙钟无关的离散时间度量。
///
/// 以 `UInt64` 表示，保证三后端整数语义一致。透明别名：可直接参与 `UInt64`
/// 的算术与比较，无需装箱 / 拆箱。
pub type LogicalTime = UInt64

///|
/// 对基准逻辑时间 `base` 施加确定性时钟偏移 `offset`（`ClockSkew` 故障使用，R3.5）。
///
///   * `offset >= 0`：结果为 `base + offset`（向未来偏移）；
///   * `offset < 0` ：结果为 `base - |offset|`，并**下钳到 0**（不允许回退到负值，
///     从而虚拟时间不会因偏移而变为非法值）。
///
/// 三后端一致：仅使用 `UInt64` / `Int64` 整数运算与比较，无浮点、无平台差异。
pub fn skewed_time(base : LogicalTime, offset : Int64) -> LogicalTime {
  if offset >= 0L {
    base + offset.reinterpret_as_uint64()
  } else {
    let dec = (-offset).reinterpret_as_uint64()
    if base >= dec {
      base - dec
    } else {
      0UL
    }
  }
}
