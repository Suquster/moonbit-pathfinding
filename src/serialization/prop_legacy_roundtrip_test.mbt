// prop_legacy_roundtrip_test.mbt —— Property 1：既有 wire 往返（旗舰深化，任务 1.4）。
//
// Feature: serialization, Property 1: 既有 wire 往返（legacy wire round-trip）
//
// 本属性验证旗舰深化下既有冻结 API（`encode`/`decode`，types.mbt/wire.mbt）的
// 运行时行为**不变**（R10.2）：对任意由生成器产出的字段记录序列消息 `m`，
//   `decode(encode(m), Schema::empty()) == Ok(m)`
// 恒成立（R10.6）。复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`（≥100 迭代）。
//
// **Validates: Requirements 10.2, 10.6**
//
// 说明：本文件与既有 `prop_roundtrip_test.mbt` 的同类往返互为印证（前者锁定
// 旗舰深化期既有 API 的零回归），符号统一以 `leg_` 前缀命名以避免同包冲突。

///|
/// 合法字段号生成：闭区间 `[1, 536870911]`（2^29 - 1 为 protobuf 上限）。
fn leg_field_number(rng : @infra_pbt.Rng) -> Int {
  rng.next_range(1, 536870911)
}

///|
/// 随机字节序列：长度 0~6，每字节取自 `[0, 255]`（含空与内嵌零字节）。
fn leg_bytes(rng : @infra_pbt.Rng) -> Bytes {
  let n = rng.next_range(0, 6)
  let arr : Array[Byte] = []
  for _i in 0..<n {
    arr.push(rng.next_below(256).to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 等概率产出四类 wire 取值之一。
fn leg_field_value(rng : @infra_pbt.Rng) -> FieldValue {
  match rng.next_below(4) {
    0 => FieldValue::VVarint(rng.next())
    1 => FieldValue::VI64(rng.next())
    2 => FieldValue::VI32(rng.next().to_uint())
    _ => FieldValue::VBytes(leg_bytes(rng))
  }
}

///|
/// 合法消息生成器：0~6 条字段（含同号重复、顺序自由）。
fn leg_gen_message() -> @infra_pbt.Gen[Message] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(0, 6)
    let fields : Array[FieldEntry] = []
    for _i in 0..<n {
      fields.push(FieldEntry::new(leg_field_number(rng), leg_field_value(rng)))
    }
    Message::from_fields(fields)
  })
}

///|
/// Feature: serialization, Property 1: 既有 wire 往返（legacy wire round-trip）
///
/// 对任意生成消息 `m`，`decode(encode(m), Schema::empty()) == Ok(m)`。
///
/// **Validates: Requirements 10.2, 10.6**
test "Feature: serialization, Property 1: legacy wire round-trip" {
  let ok = @infra_pbt.holds_for_all(leg_gen_message(), fn(m) {
    decode(encode(m), Schema::empty()) == Ok(m)
  })
  assert_true(ok)
}
