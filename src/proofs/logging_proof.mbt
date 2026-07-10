// logging_proof.mbt —— Logging_Library（R7）方向的契约谓词。
//
// 复用约定：结构化日志往返复用 `round_trip_eq`；本文件补充方向特有的
// 「级别阈值过滤」谓词。生产属性测试把真实 `Event` / `Level` 观测投影为
// 整数序数与发射标志；谓词保持纯、全（total），便于收缩反例。

///|
/// 日志级别阈值过滤。
///
/// 当且仅当：事件被输出（`emitted`）⇔ 其级别不低于阈值（`event_level >= threshold`）
/// 时成立。级别以整数序数表示，数值越大级别越高。实现为 `emitted == (event_level
/// >= threshold)`，双向蕴含。纯、全函数：对任意整数级别与任意布尔输出恒返回
/// `Bool`，可被 ≥100 次随机组合的属性测试驱动而不会 abort。
pub fn level_threshold_filter(
  event_level : Int,
  threshold : Int,
  emitted : Bool,
) -> Bool {
  emitted == (event_level >= threshold)
}
