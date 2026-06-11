// prop_roundtrip_test.mbt —— Protobuf 编解码往返属性测试（task 7.3）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 20：「Protobuf 编解码往返」——对生成器产出的任一合法消息对象 `x`，
// 编码再解码应等价于原对象（`decode(encode(x)) ≡ x`）。
//
//   Message（内存消息对象）→ encode（wire format 字节）→ decode（回内存对象）
// 二者在受支持的四类 wire 取值上互为双射（bijection）；本属性即断言该往返对
// 任意合法消息恒等还原，从而验证 wire 编解码的互逆性（R9.3）。
//
// 关键：合法消息的生成空间约束（generation constraints）
// -----------------------------------------------------------------------
// `decode`（见 wire.mbt）对字段号与 wire 类型有契约约束，生成器**刻意只产出
// 可往返的合法形态**，以保证 Property 20 成立：
//   1. 字段号必须为正且不超过 protobuf 上限 2^29 - 1（536870911）。
//      `decode` 对 number <= 0 返回 `InvalidFieldNumber`，故字段号取自
//      闭区间 [1, 536870911]。
//   2. 四类 `FieldValue` 取值均落在 wire 可无损往返的范围内：
//      * `VVarint(UInt64)` —— 任意 64 位无符号整数（最长 10 字节 varint）；
//      * `VI64(UInt64)`    —— 定长 8 字节小端；
//      * `VI32(UInt)`      —— 定长 4 字节小端；
//      * `VBytes(Bytes)`   —— 任意字节序列（含空与内嵌零字节）。
//   3. 字段顺序与同号重复字段均被 `decode` 原样保留，故生成器可自由产出
//      0~N 条字段（含同号重复）而不破坏往返。
//
// 往返断言同时以两种 @infra_pbt 模板表达，二者都校验 Property 20：
//   * `@infra_pbt.round_trip`    —— 经 `Bytes` 编解码桥接的往返模板（≥100 迭代）；
//   * `@infra_pbt.holds_for_all` —— 直接以 `decode(encode(x)) == Ok(x)` 谓词的
//     不变量模板（默认 `iters=100`）。
// 生成器复用 @infra_pbt 的种子驱动随机源 `Rng`，保证三后端逐位一致与可重放。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。
//
// 说明：本文件的生成器 / 桥接辅助统一以 `rt_` / `gen_rt_` 前缀命名，与同包内
// 其它测试文件（wire_test.mbt / serialization_test.mbt）的符号互不冲突。

// ---------------------------------------------------------------------------
// 字段号生成（generator）—— 落在 protobuf 合法区间 [1, 2^29 - 1]
// ---------------------------------------------------------------------------

///|
/// 生成一个合法字段号：闭区间 `[1, 536870911]`（2^29 - 1 为 protobuf 上限）。
///
/// `decode` 拒绝 number <= 0（返回 `InvalidFieldNumber`），故下界取 1；上界取
/// protobuf 允许的最大字段号，覆盖单字节到多字节 tag varint 的全部布局。
fn gen_rt_field_number(rng : @infra_pbt.Rng) -> Int {
  rng.next_range(1, 536870911)
}

// ---------------------------------------------------------------------------
// 原始字节生成（generator）—— 任意长度、含空与内嵌零字节
// ---------------------------------------------------------------------------

///|
/// 随机字节序列生成器：长度 0~7，每字节取自 `[0, 255]`。
///
/// 刻意覆盖空字节序列（长度 0）与内嵌零字节，验证 Len 字段在二进制内容上的
/// 无损往返（长度前缀 + 原始字节）。
fn gen_rt_bytes(rng : @infra_pbt.Rng) -> Bytes {
  let n = rng.next_range(0, 7)
  let arr : Array[Byte] = []
  for _i in 0..<n {
    arr.push(rng.next_below(256).to_byte())
  }
  Bytes::from_array(arr)
}

// ---------------------------------------------------------------------------
// 字段取值生成（generator）—— 四类 wire FieldValue 等概率覆盖
// ---------------------------------------------------------------------------

///|
/// 随机字段取值生成器：等概率产出四类 wire 取值之一。
///
/// `rng.next()` 提供 64 位随机字，直接承载 `VVarint` / `VI64`；`VI32` 取其低
/// 32 位（`to_uint`）；`VBytes` 由 `gen_rt_bytes` 产出。四类取值均落在 wire
/// 可无损往返的范围内。
fn gen_rt_field_value(rng : @infra_pbt.Rng) -> FieldValue {
  match rng.next_below(4) {
    0 => FieldValue::VVarint(rng.next())
    1 => FieldValue::VI64(rng.next())
    2 => FieldValue::VI32(rng.next().to_uint())
    _ => FieldValue::VBytes(gen_rt_bytes(rng))
  }
}

// ---------------------------------------------------------------------------
// 合法消息生成（generator）—— 0~5 条字段，含同号重复，顺序自由
// ---------------------------------------------------------------------------

///|
/// 合法消息生成器：0~5 条字段，每条由随机合法字段号 + 随机四类取值构成。
///
/// 不去重字段号（同号重复字段亦应原样往返），亦不约束字段顺序（`decode` 保留
/// wire 顺序），从而最大化对 `encode`/`decode` 往返的输入覆盖。
fn gen_roundtrip_message() -> @infra_pbt.Gen[Message] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(0, 5)
    let fields : Array[FieldEntry] = []
    for _i in 0..<n {
      fields.push(
        FieldEntry::new(gen_rt_field_number(rng), gen_rt_field_value(rng)),
      )
    }
    Message::from_fields(fields)
  })
}

// ---------------------------------------------------------------------------
// Bytes 编解码桥接（供 round_trip 模板使用）
// ---------------------------------------------------------------------------

///|
/// 解码桥接：`Bytes` -> `Message?`。
///
/// 复用本包 `decode`（以空模式做 wire 粒度解码）；解码失败时返回 `None`
/// （往返失败）。与 `encode` 互逆，供 @infra_pbt.round_trip 模板桥接使用。
fn rt_decode_message(b : Bytes) -> Message? {
  match decode(b, Schema::empty()) {
    Ok(m) => Some(m)
    Err(_) => None
  }
}

// ---------------------------------------------------------------------------
// 单元测试（具体见证）—— 锁定代表性消息的往返
// ---------------------------------------------------------------------------

///|
/// 对一组代表性合法消息，`decode(encode(x))` 应得到等价消息（Property 20 的
/// 具体见证；属性形式见下方 round_trip / holds_for_all 测试）。
test "round-trip holds on representative messages" {
  let samples : Array[Message] = [
    // 空消息。
    Message::empty(),
    // 四类 wire 取值各一。
    Message::from_fields([
      FieldEntry::new(1, FieldValue::varint(150UL)),
      FieldEntry::new(2, FieldValue::i64(0x0102030405060708UL)),
      FieldEntry::new(3, FieldValue::i32(0x01020304U)),
      FieldEntry::new(4, FieldValue::bytes(b"hello")),
    ]),
    // 边界取值：varint 最大、定长零、空字节序列、含内嵌零字节。
    Message::from_fields([
      FieldEntry::new(536870911, FieldValue::varint(0xFFFFFFFFFFFFFFFFUL)),
      FieldEntry::new(5, FieldValue::i64(0UL)),
      FieldEntry::new(6, FieldValue::bytes(b"")),
      FieldEntry::new(7, FieldValue::bytes(b"\x00\xff\x00")),
    ]),
    // 同号重复字段保持顺序。
    Message::from_fields([
      FieldEntry::new(8, FieldValue::varint(1UL)),
      FieldEntry::new(8, FieldValue::varint(2UL)),
      FieldEntry::new(8, FieldValue::varint(3UL)),
    ]),
  ]
  for msg in samples {
    match decode(encode(msg), Schema::empty()) {
      Ok(out) => assert_true(out == msg)
      Err(e) => fail("代表性消息往返不应失败：\{e}")
    }
  }
}

// ---------------------------------------------------------------------------
// Property 20：Protobuf 编解码往返
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 20: Protobuf 编解码往返（round_trip 模板）
///
/// 对任意由生成器产出的合法消息对象 `x`，经"编码 → Bytes → 解码"的往返应
/// 还原为等价消息（`decode(encode(x)) ≡ x`）。复用 @infra_pbt 的 `round_trip`
/// 往返断言模板，默认迭代 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 9.3**
test "Feature: moonbit-infra-suite, Property 20: decode(encode(x)) round-trips (round_trip template)" {
  let ok = @infra_pbt.round_trip(
    gen_roundtrip_message(),
    encode,
    rt_decode_message,
  )
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 20: Protobuf 编解码往返（holds_for_all 模板）
///
/// 同一往返性质的直接谓词形式：对任意生成的消息 `x`，`decode(encode(x))`
/// 应恰好等于 `Ok(x)`。复用 @infra_pbt 的 `holds_for_all` 不变量模板，
/// 默认迭代 100 次。
///
/// **Validates: Requirements 9.3**
test "Feature: moonbit-infra-suite, Property 20: decode(encode(x)) equals x (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(gen_roundtrip_message(), fn(msg) {
    match decode(encode(msg), Schema::empty()) {
      Ok(out) => out == msg
      Err(_) => false
    }
  })
  assert_true(ok)
}
