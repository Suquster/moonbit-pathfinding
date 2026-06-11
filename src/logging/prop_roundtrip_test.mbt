// prop_roundtrip_test.mbt —— 结构化日志往返属性测试（task 10.4）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 18：「结构化日志往返」——对任意结构化日志事件 `e`，序列化再解析
// 应得到等价事件（`parse_json_log(format_json(e)) ≡ e`）。
//
//   Event（内存事件对象）→ format_json（JSON 文本）→ parse_json_log（回内存对象）
// 二者在受支持的字段取值域上互为双射（bijection）；本属性即断言该往返对任意
// 合法事件恒等还原，从而验证结构化输出与解析的互逆性（R7.7）。
//
// 关键：事件的生成空间约束（generation constraints）
// -----------------------------------------------------------------------
// `format_json` / `parse_json_log` 对取值有可往返约束，生成器**刻意只产出可
// 无损往返的合法形态**，以保证 Property 18 成立：
//   1. 字段取值覆盖全部四类 `Value`：`VStr` / `VInt` / `VBool` / `VFloat`。
//   2. `VStr` 字符串刻意包含需转义的字符——双引号 `"`、反斜杠 `\`、换行 `\n`、
//      回车 `\r`、制表符 `\t`、退格 `\b`(0x08)、换页 `\f`(0x0C) 及通用控制字符
//      (0x01 / 0x1F，走 `\u00XX` 转义路径)——以验证转义与反转义的往返闭环。
//      字符集刻意限制在 ASCII 范围内：经 `json_escape` 后输出恒为纯 ASCII，
//      使下方 `Bytes` 桥接（逐字符取低 8 位）无损。
//   3. `VFloat` 浮点取值约束为「奇数 / 8」形态（`(2k+1) / 8.0`）：
//      * 分母为 2 的幂 ⇒ 该值可被 `Double` **精确表示**，`to_string` 再
//        `parse_double` 逐位还原，规避浮点往返精度问题；
//      * 分子为奇数 ⇒ 该值**恒含小数部分**，`to_string` 必产生小数点，从而被
//        `parse_json_log` 的 `num_is_float` 判定为浮点（而非误判为整数），
//        保证 `VFloat` 不会在往返中退化为 `VInt`。
//   4. 字段键取唯一形态 `k0`/`k1`/…，避免同名字段在 `Map` 中去重而影响等价
//      比较；转义往返已由字段取值（`VStr`）充分覆盖。
//
// 往返断言同时以两种 @infra_pbt 模板表达，二者都校验 Property 18：
//   * `@infra_pbt.round_trip`    —— 经 `Bytes` 编解码桥接的往返模板（≥100 迭代）；
//   * `@infra_pbt.holds_for_all` —— 直接以 `parse_json_log(format_json(e)) == Some(e)`
//     谓词的不变量模板（默认 `iters=100`）。
// 生成器复用 @infra_pbt 的种子驱动随机源 `Rng`，保证三后端逐位一致与可重放。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。

// ---------------------------------------------------------------------------
// 字符串生成（generator）—— 含需转义字符，限定 ASCII 以保证 Bytes 桥接无损
// ---------------------------------------------------------------------------

///|
/// 随机字符串字符集：普通可打印 ASCII + 全部需转义/控制字符。
///
/// 覆盖 `json_escape` 的每条分支：命名转义（`"` `\` `\n` `\r` `\t` `\b` `\f`）
/// 与通用 `\u00XX` 转义（0x01 / 0x1F）；其余为常规可打印字符。全部落在 ASCII
/// 范围内，故 `format_json` 输出恒为纯 ASCII，`Bytes` 桥接（低 8 位）无损。
fn rt_string_alphabet() -> Array[Char] {
  [
    'a',
    'b',
    'c',
    'z',
    'A',
    'M',
    'Z',
    '0',
    '5',
    '9',
    ' ',
    '/',
    ':',
    '{',
    '}',
    '"',
    '\\',
    '\n',
    '\r',
    '\t',
    (0x08).unsafe_to_char(),
    (0x0C).unsafe_to_char(),
    (0x01).unsafe_to_char(),
    (0x1F).unsafe_to_char(),
  ]
}

///|
/// 随机字符串生成器：长度 0~6，逐字符取自 `rt_string_alphabet`。
///
/// 长度可为 0（空串），刻意覆盖转义字符的密集组合以压力测试往返闭环。
fn gen_rt_string(rng : @infra_pbt.Rng) -> String {
  let alphabet = rt_string_alphabet()
  let n = rng.next_range(0, 6)
  let mut s = ""
  for _i in 0..<n {
    s = s + alphabet[rng.next_below(alphabet.length())].to_string()
  }
  s
}

// ---------------------------------------------------------------------------
// 浮点生成（generator）—— 限定可精确往返的「奇数 / 8」形态
// ---------------------------------------------------------------------------

///|
/// 可精确往返的浮点生成器：`(2k+1) / 8.0`，k ∈ [-1000, 1000]。
///
/// 分母 8 为 2 的幂 ⇒ 取值可被 `Double` 精确表示，`to_string`/`parse_double`
/// 逐位还原；分子为奇数 ⇒ 取值恒非整数，`to_string` 必含小数点，确保
/// `parse_json_log` 将其判为浮点而非整数。两者共同规避浮点往返精度陷阱。
fn gen_rt_float(rng : @infra_pbt.Rng) -> Double {
  let k = rng.next_range(-1000, 1000)
  let numerator = 2 * k + 1
  numerator.to_double() / 8.0
}

// ---------------------------------------------------------------------------
// 字段取值与级别生成（generator）—— 四类 Value 等概率覆盖
// ---------------------------------------------------------------------------

///|
/// 随机字段取值生成器：等概率产出 `VStr` / `VInt` / `VBool` / `VFloat` 之一。
///
/// `VInt` 取值覆盖正负整数（含 0）；`VFloat` 限定为可精确往返形态；`VStr`
/// 含需转义字符；`VBool` 取真/假。四类取值均落在可无损往返的范围内。
fn gen_rt_value(rng : @infra_pbt.Rng) -> Value {
  match rng.next_below(4) {
    0 => VStr(gen_rt_string(rng))
    1 => VInt(rng.next_range(-1_000_000, 1_000_000).to_int64())
    2 => VBool(rng.next_bool())
    _ => VFloat(gen_rt_float(rng))
  }
}

///|
/// 随机日志级别生成器：等概率产出 Trace / Debug / Info / Warn / Error 之一。
fn gen_rt_level(rng : @infra_pbt.Rng) -> Level {
  match rng.next_below(5) {
    0 => Trace
    1 => Debug
    2 => Info
    3 => Warn
    _ => Error
  }
}

// ---------------------------------------------------------------------------
// 事件生成（generator）—— 随机时间戳 / 级别 / 0~5 条字段
// ---------------------------------------------------------------------------

///|
/// 合法事件生成器：随机时间戳（含负值）、随机级别、0~5 条唯一键字段。
///
/// 时间戳取自 `[-1e9, 1e9]` 并转 `Int64`（覆盖正负与 0）；字段键取唯一形态
/// `k0`/`k1`/… 以规避 `Map` 去重；字段取值覆盖四类 `Value`。
fn gen_rt_event() -> @infra_pbt.Gen[Event] {
  @infra_pbt.Gen::new(fn(rng) {
    let ts = rng.next_range(-1_000_000_000, 1_000_000_000).to_int64()
    let level = gen_rt_level(rng)
    let nfields = rng.next_range(0, 5)
    let fields : Map[String, Value] = {}
    for i in 0..<nfields {
      fields["k\{i}"] = gen_rt_value(rng)
    }
    Event::new(ts, level, fields)
  })
}

// ---------------------------------------------------------------------------
// Bytes 编解码桥接（供 round_trip 模板使用）
// ---------------------------------------------------------------------------

///|
/// 编码桥接：`Event` -> JSON 文本（`format_json`）-> `Bytes`（逐字符取低 8 位）。
///
/// 生成器约束保证 `format_json` 输出恒为纯 ASCII（码位 < 128），故 `to_byte`
/// 无损；与 `rt_decode_event` 互逆。
fn rt_encode_event(e : Event) -> Bytes {
  let s = format_json(e)
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 解码桥接：`Bytes` -> JSON 文本（逐字节还原 ASCII 字符）-> `parse_json_log`。
///
/// 与 `rt_encode_event` 互逆；解析失败时返回 `None`（往返失败）。
fn rt_decode_event(b : Bytes) -> Event? {
  let mut s = ""
  let mut i = 0
  while i < b.length() {
    s = s + b[i].to_int().unsafe_to_char().to_string()
    i = i + 1
  }
  parse_json_log(s)
}

// ---------------------------------------------------------------------------
// 单元测试（具体见证）—— 锁定代表性事件的往返
// ---------------------------------------------------------------------------

///|
/// 对一组代表性合法事件，`parse_json_log(format_json(e))` 应得到等价事件
/// （Property 18 的具体见证；属性形式见下方 round_trip / holds_for_all 测试）。
test "round-trip holds on representative events" {
  let samples : Array[Event] = [
    // 空字段事件。
    Event::new(0L, Level::Info, {}),
    // 四类字段取值各一。
    Event::new(123L, Level::Warn, {
      "msg": VStr("hello world"),
      "count": VInt(42L),
      "ok": VBool(true),
      "ratio": VFloat(0.125),
    }),
    // 含全部命名转义与 \u00XX 通用转义的字符串。
    Event::new(-7L, Level::Error, {
      "raw": VStr("a\"b\\c\nd\te\rf\u{08}g\u{0C}h\u{01}i\u{1F}j"),
    }),
    // 负时间戳、负整数、负浮点（精确往返形态）。
    Event::new(-1_000_000_000L, Level::Trace, {
      "neg_int": VInt(-999_999L),
      "neg_float": VFloat(-0.125),
    }),
  ]
  for e in samples {
    match parse_json_log(format_json(e)) {
      Some(out) => assert_true(out == e)
      None => fail("代表性事件往返不应失败")
    }
  }
}

// ---------------------------------------------------------------------------
// Property 18：结构化日志往返
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 18: 结构化日志往返（round_trip 模板）
///
/// 对任意由生成器产出的合法日志事件 `e`，经「序列化 → Bytes → 解析」的往返
/// 应还原为等价事件（`parse_json_log(format_json(e)) ≡ e`）。复用 @infra_pbt
/// 的 `round_trip` 往返断言模板，默认迭代 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 7.7**
test "Feature: moonbit-infra-suite, Property 18: parse_json_log(format_json(e)) round-trips (round_trip template)" {
  let ok = @infra_pbt.round_trip(
    gen_rt_event(),
    rt_encode_event,
    rt_decode_event,
  )
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 18: 结构化日志往返（holds_for_all 模板）
///
/// 同一往返性质的直接谓词形式：对任意生成的事件 `e`，
/// `parse_json_log(format_json(e))` 应恰好等于 `Some(e)`。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 7.7**
test "Feature: moonbit-infra-suite, Property 18: parse_json_log(format_json(e)) equals e (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(gen_rt_event(), fn(e) {
    parse_json_log(format_json(e)) == Some(e)
  })
  assert_true(ok)
}
