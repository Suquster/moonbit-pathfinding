// canonical.mbt —— 确定性 / 规范化编码与未知字段保留（旗舰深化，旁路新增，R2）。
//
// 设计依据（design.md §4.5「确定性/规范化编码与未知字段保留」）：对标 protobuf
// deterministic serialization，对同一消息内容产出唯一字节序列，从而幂等。
//
// 规则：① 字段号升序输出（R2.3）；② 数值标量 repeated 一律 packed（R2.4，
// 经 `typed_build_entries(.., force_packed=true)`）；③ 每字段至多一条记录
// （singular 天然一次，repeated 已聚合为单 packed 条目）；④ 未知字段以其原始
// 字段号并入同一升序排序后写回（R2.2）。
//
// 复用既有 `encode` 写出与同包类型化编码构件，不重复实现 wire 写逻辑。

///|
/// 按字段号升序对字段记录做**稳定**排序（同号记录保持原相对顺序）。
fn canonical_sort(entries : Array[FieldEntry]) -> Array[FieldEntry] {
  let out : Array[FieldEntry] = []
  for e in entries {
    out.push(e)
  }
  // 稳定插入排序：等键不交换，保持相对顺序。
  let mut i = 1
  while i < out.length() {
    let key = out[i]
    let mut j = i - 1
    while j >= 0 && out[j].number > key.number {
      out[j + 1] = out[j]
      j = j - 1
    }
    out[j + 1] = key
    i = i + 1
  }
  out
}

///|
/// 类型化消息的确定性编码（R2.2/2.3/2.4/2.5）。
///
/// 字段号升序、数值标量 repeated 一律 packed、每字段至多一次、未知字段按其原始
/// 字段号并入同一升序序列写回。对同一消息内容产出唯一字节序列，从而幂等
/// （`encode_canonical(decode_typed(encode_canonical(m))) == encode_canonical(m)`，
/// R2.6）。
pub fn encode_canonical(
  schema : ProtoSchema,
  msg_name : String,
  msg : TypedMessage,
) -> Result[Bytes, DecodeError] {
  match typed_build_entries(schema, msg_name, msg, true) {
    Ok(entries) => Ok(encode(Message::from_fields(canonical_sort(entries))))
    Err(e) => Err(e)
  }
}

///|
/// wire 级规范化：对任意 `Message` 的字段记录按字段号升序稳定重排后重编，
/// 不依赖 schema（供未知字段排序与既有 `Message` 的确定性比对）。
pub fn canonicalize_wire(msg : Message) -> Bytes {
  encode(Message::from_fields(canonical_sort(msg.fields)))
}
