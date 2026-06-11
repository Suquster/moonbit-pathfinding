// prop_roundtrip_test.mbt —— LSP_Binding JSON-RPC 消息往返属性测试（任务 14.3）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 11「JSON-RPC 消息往返」：
//
//   *对任意* 合法的 JSON-RPC 2.0 消息，对其编码再解码应得到语义等价消息
//   （`decode_message(encode_message(msg))` 语义等价于 `msg`）。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `round_trip` / `holds_for_all`
// 模板（每条属性 ≥100 次迭代，由模板默认 `iters=100` / `default_iters` 保证）。
//
// 往返断言同时以两种模板表达，二者都校验 Property 11：
//   * `@infra_pbt.round_trip`    —— 经 `Bytes` 编解码桥接的往返模板（≥100 迭代）；
//   * `@infra_pbt.holds_for_all` —— 直接以 `decode(encode(x)) == Ok(x)` 谓词的
//     不变量模板（默认 `iters=100`）。
//
// 生成器约定（保证生成消息是 encode 后可被 decode 还原的「合法形态」）：
//   * Request    —— 随机 Id + 随机 method + 随机 Json params；
//   * Notification —— 随机 method + 随机 Json params（无 id）；
//   * Response   —— 随机 Id，且 `result` 与 `error` 二者**恰含其一**（规范约束，
//     否则 decode_message 视为非法请求，往返必然失败）。
//   * Id 覆盖 IdNum / IdStr / IdNull 三种形态；IdNum 取值限制在安全整数区间，
//     规避 `parse_int_literal` 在极值（如 Int 最小值）处的溢出。
//   * Json 覆盖 null / bool / 数值字面量 / 字符串（含转义字符）/ 嵌套数组 / 嵌套
//     对象；深度受限以保证树规模有界。
//   * 所有字符串 / 键 / 数值字面量均限制为 ASCII（码位 < 128），与包内
//     `Bytes` ⇄ 文本逐字节（ASCII 无损）转换约定一致。

// ---------------------------------------------------------------------------
// 随机生成器（generator）—— 复用 @infra_pbt 种子驱动随机源 Rng
// ---------------------------------------------------------------------------

///|
/// 生成一串数字字符（长度落在 `[min_len, max_len]`），用于拼装合法数值字面量。
fn gen_digits(rng : @infra_pbt.Rng, min_len : Int, max_len : Int) -> String {
  let len = rng.next_range(min_len, max_len)
  let mut s = ""
  let mut i = 0
  while i < len {
    s = s + rng.next_below(10).to_string() // 单个十进制数字 "0".."9"
    i = i + 1
  }
  s
}

///|
/// 生成一个合法的 JSON 数值字面量文本（整数 / 小数 / 指数三种形态之一）。
///
/// `Json::JNum` 保留原始字面量文本，解析器消费一个极大匹配的数值并原样存回，
/// 因此任一语法合法的数值字面量都满足往返无损（不涉及数值算术，无溢出风险）。
fn gen_number_literal(rng : @infra_pbt.Rng) -> String {
  let neg = if rng.next_bool() { "-" } else { "" }
  let int_part = gen_digits(rng, 1, 3)
  match rng.next_below(3) {
    0 => neg + int_part // 整数：[-]ddd
    1 => neg + int_part + "." + gen_digits(rng, 1, 3) // 小数：[-]ddd.ddd
    _ => {
      // 指数：[-]ddd e [±] dd
      let esign = match rng.next_below(3) {
        0 => "+"
        1 => "-"
        _ => ""
      }
      neg + int_part + "e" + esign + gen_digits(rng, 1, 2)
    }
  }
}

///|
/// 生成一个随机 ASCII 字符串（长度落在 `[0, max_len]`）。
///
/// 字符集刻意混入会触发 JSON 转义的字符（`"`、`\`、换行、制表、回车），以充分
/// 覆盖打印器转义与解析器反转义的往返路径；其余为常规可打印 ASCII。
fn gen_ascii_string(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let charset = [
    'a', 'b', 'c', 'Z', '0', '1', '2', ' ', '_', '/', '"', '\\', '\n', '\t', '\r',
  ]
  let len = rng.next_below(max_len + 1)
  let mut s = ""
  let mut i = 0
  while i < len {
    s = s + charset[rng.next_below(charset.length())].to_string()
    i = i + 1
  }
  s
}

///|
/// 生成一个对象键（1..4 个字母/数字字符；键经同样的字符串编解码往返，简化即可）。
fn gen_key(rng : @infra_pbt.Rng) -> String {
  let charset = ['k', 'e', 'y', 'a', 'b', '0', '1', '2', '_', 'X']
  let len = rng.next_range(1, 4)
  let mut s = ""
  let mut i = 0
  while i < len {
    s = s + charset[rng.next_below(charset.length())].to_string()
    i = i + 1
  }
  s
}

///|
/// 在给定剩余深度下采样一个随机 `Json` 值。
///
/// 深度耗尽时只产生标量（null / bool / 数值 / 字符串）；否则以一定概率递归生成
/// 嵌套数组或对象（元素数 0..3），保证树规模有界，避免拖慢 100 次迭代。
fn gen_json(rng : @infra_pbt.Rng, depth : Int) -> Json {
  if depth <= 0 {
    match rng.next_below(4) {
      0 => JNull
      1 => JBool(rng.next_bool())
      2 => JNum(gen_number_literal(rng))
      _ => JStr(gen_ascii_string(rng, 5))
    }
  } else {
    match rng.next_below(6) {
      0 => JNull
      1 => JBool(rng.next_bool())
      2 => JNum(gen_number_literal(rng))
      3 => JStr(gen_ascii_string(rng, 5))
      4 => {
        let n = rng.next_below(4)
        let items : Array[Json] = []
        let mut i = 0
        while i < n {
          items.push(gen_json(rng, depth - 1))
          i = i + 1
        }
        JArr(items)
      }
      _ => {
        let n = rng.next_below(4)
        let fields : Array[(String, Json)] = []
        let mut i = 0
        while i < n {
          fields.push((gen_key(rng), gen_json(rng, depth - 1)))
          i = i + 1
        }
        JObj(fields)
      }
    }
  }
}

///|
/// 生成一个随机消息标识 `Id`，覆盖 IdNum / IdStr / IdNull 三种形态。
///
/// IdNum 取值限制在 `[-100000, 100000]`：足以覆盖正负与零，又避开 `Int` 极值
/// （如最小值）在 `parse_int_literal` 累加构造时的溢出。
fn gen_id(rng : @infra_pbt.Rng) -> Id {
  match rng.next_below(3) {
    0 => IdNum(rng.next_range(-100000, 100000))
    1 => IdStr(gen_ascii_string(rng, 5))
    _ => IdNull
  }
}

///|
/// 生成一个随机错误对象 `RpcError`：随机错误码 + 随机消息 + 可选附加数据。
fn gen_rpc_error(rng : @infra_pbt.Rng, depth : Int) -> RpcError {
  let code = rng.next_range(-100000, 100000)
  let message = gen_ascii_string(rng, 8)
  if rng.next_bool() {
    RpcError::with_data(code, message, gen_json(rng, depth))
  } else {
    RpcError::new(code, message)
  }
}

///|
/// 生成一个随机的合法 `JsonRpcMessage`（Request / Notification / Response）。
///
/// 关键合法性约束：Response 的 `result` 与 `error` **恰含其一**，与
/// `decode_message` 的响应校验一致，保证编码后可被无损解码还原。
fn gen_message(rng : @infra_pbt.Rng) -> JsonRpcMessage {
  match rng.next_below(3) {
    0 =>
      JsonRpcMessage::Request(
        id=gen_id(rng),
        method=gen_ascii_string(rng, 6),
        params=gen_json(rng, 2),
      )
    1 =>
      JsonRpcMessage::Notification(
        method=gen_ascii_string(rng, 6),
        params=gen_json(rng, 2),
      )
    _ =>
      if rng.next_bool() {
        // 恰含 result。
        JsonRpcMessage::Response(
          id=gen_id(rng),
          result=Some(gen_json(rng, 2)),
          error=None,
        )
      } else {
        // 恰含 error。
        JsonRpcMessage::Response(
          id=gen_id(rng),
          result=None,
          error=Some(gen_rpc_error(rng, 1)),
        )
      }
  }
}

///|
/// 合法 JSON-RPC 消息生成器（封装为 @infra_pbt.Gen，供断言模板驱动）。
fn gen_json_rpc_message() -> @infra_pbt.Gen[JsonRpcMessage] {
  @infra_pbt.Gen::new(fn(rng) { gen_message(rng) })
}

// ---------------------------------------------------------------------------
// Bytes 解码桥接（供 round_trip 模板使用）
// ---------------------------------------------------------------------------

///|
/// 解码适配：将 `decode_message` 的 `Result[JsonRpcMessage, RpcError]` 适配为
/// `round_trip` 模板所需的 `(Bytes) -> JsonRpcMessage?`；解码失败映射为 `None`
/// （往返失败）。
fn decode_message_opt(bytes : Bytes) -> JsonRpcMessage? {
  match decode_message(bytes) {
    Ok(msg) => Some(msg)
    Err(_) => None
  }
}

// ---------------------------------------------------------------------------
// 属性测试（Property 11）
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 11: JSON-RPC 消息往返（round_trip 模板）
///
/// 对任意由生成器产出的合法 JSON-RPC 2.0 消息 `msg`，经「编码 → Bytes → 解码」
/// 的往返应还原为语义等价消息（`decode_message(encode_message(msg)) ≡ msg`）。
/// 复用 @infra_pbt 的 `round_trip` 往返断言模板，默认迭代 100 次（满足 ≥100
/// 迭代基线）。
///
/// **Validates: Requirements 5.9**
test "Feature: moonbit-infra-suite, Property 11: decode(encode(msg)) round-trips (round_trip template)" {
  let ok = @infra_pbt.round_trip(
    gen_json_rpc_message(),
    encode_message,
    decode_message_opt,
  )
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 11: JSON-RPC 消息往返（holds_for_all 模板）
///
/// 同一往返性质的直接谓词形式：对任意生成的消息 `msg`，
/// `decode_message(encode_message(msg))` 应恰好为 `Ok(msg)`。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 5.9**
test "Feature: moonbit-infra-suite, Property 11: decode(encode(msg)) equals msg (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(gen_json_rpc_message(), fn(msg) {
    decode_message(encode_message(msg)) == Ok(msg)
  })
  assert_true(ok)
}
