// serialization_proof.mbt —— Serialization（R9）方向的契约谓词。
//
// 复用约定：protobuf 编解码往返复用 `round_trip_eq`；本文件补充方向特有的
// 「解码失败不产生部分对象」错误条件谓词。真实 wire format 解码测试投影
// 成功状态与对象产出状态；谓词保持纯、全（total）。

///|
/// 解码失败不产生部分对象。
///
/// 当且仅当：解码成功（`decode_ok`），或解码失败时未产生任何部分构造对象
/// （`!produced_object`）时成立。实现为 `decode_ok || !produced_object`，即
/// 蕴含「解码失败 ⇒ 不产出半成品对象」，保证失败的原子性（R9 错误契约）。
/// 纯、全函数，对任意两布尔输入恒返回 `Bool`。
pub fn decode_failure_no_partial(
  decode_ok : Bool,
  produced_object : Bool,
) -> Bool {
  decode_ok || !produced_object
}
