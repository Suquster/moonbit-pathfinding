// serialization_proof.mbt —— Serialization（R9）方向的证明谓词占位。
//
// 复用约定：protobuf 编解码往返复用 `round_trip_eq`；本文件补充方向特有的
// 「解码失败不产生部分对象」错误条件最小占位谓词。谓词均为纯、全（total）。
// 升级路径：任务 7.x 引入真实 wire format 编解码后替换占位。

///|
/// 解码失败不产生部分对象（占位）。
///
/// 当且仅当：解码成功（`decode_ok`），或解码失败时未产生任何部分构造对象
/// （`!produced_object`）时成立。
pub fn decode_failure_no_partial(
  decode_ok : Bool,
  produced_object : Bool,
) -> Bool {
  decode_ok || !produced_object
}
