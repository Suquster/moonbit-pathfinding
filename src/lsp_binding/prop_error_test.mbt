// prop_error_test.mbt —— LSP_Binding 非法消息错误条件属性测试（任务 14.4）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 12「LSP_Server 非法消息错误条件」：
//
//   *对任意* 不符合 JSON-RPC 2.0 规范的输入消息，`decode_message` 应返回符合
//   规范的错误响应（含错误码与消息），且服务进程不终止——即返回结构化的
//   `Result::Err`（标准错误码 + 消息），而非 panic/abort。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 不变量模板
// （默认迭代 100 次，满足 Requirement 11.3「每条属性 ≥100 次迭代」基线）。
//
// 「非法 JSON-RPC 字节序列」生成器覆盖以下不合规范的形态（每类均经 design.md
// §「方向五」与 binding.mbt 的失败契约核对，确保 decode_message 必返回 Err）：
//   * 非法 JSON（无法解析为合法 JSON 值）            → parse_error_code；
//   * 合法 JSON 但顶层非对象（数值 / 字符串 / 布尔 / null / 数组）→ invalid_request；
//   * 缺失或非法 `jsonrpc` 字段（非 "2.0"）          → invalid_request；
//   * `method` 字段非字符串                          → invalid_request；
//   * `id` 字段非法（小数 / 指数 / 数组 / 对象 / 布尔）→ invalid_request；
//   * 响应同时含 result 与 error，或二者皆缺          → invalid_request；
//   * 响应 `error` 对象结构非法（缺 code/message 或非对象）→ invalid_request；
//   * 既无 `method` 又无 `id`                         → invalid_request。
//
// 性质（predicate）：对每个生成的非法字节序列，`decode_message` 返回 `Err`，
// 且其错误码为 JSON-RPC 2.0 规范定义的标准错误码之一（即不 panic/abort、且
// 给出结构化错误）。

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

///|
/// 文本 → 字节（逐字符低 8 位，ASCII 无损），等价于包内 `text_to_bytes`。
fn err_text_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 判定错误码是否为 JSON-RPC 2.0 规范定义的标准错误码之一。
///
/// `decode_message` 仅会产出 parse_error / invalid_request 两类；此处涵盖规范
/// 全部预定义标准码，使性质表述与「规范标准码之一」一致而不过度收窄。
fn is_standard_error_code(code : Int) -> Bool {
  code == parse_error_code ||
  code == invalid_request_code ||
  code == method_not_found_code ||
  code == invalid_params_code ||
  code == internal_error_code
}

// ---------------------------------------------------------------------------
// 随机生成器（generator）—— 复用 @infra_pbt 种子驱动随机源 Rng
// ---------------------------------------------------------------------------

///|
/// 生成一个简单的 ASCII 标识符（1..max_len 个字母/数字/下划线），用于充当随机
/// method 名、对象键或字符串 id，为各非法类别注入跨迭代的多样性。
fn gen_err_ident(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let charset = [
    'a', 'b', 'c', 'd', 'm', 'n', 'x', 'y', 'Z', 'Q', '0', '1', '2', '_',
  ]
  let len = rng.next_range(1, max_len)
  let mut s = ""
  let mut i = 0
  while i < len {
    s = s + charset[rng.next_below(charset.length())].to_string()
    i = i + 1
  }
  s
}

///|
/// 类别 0：非法 JSON 文本（无法解析为合法 JSON 值）→ parse_error_code。
fn gen_malformed_json(rng : @infra_pbt.Rng) -> String {
  let samples = [
    "", // 空输入
     "{", // 未闭合对象
     "}", // 孤立闭括号
     "[", // 未闭合数组
     "[1,2", // 数组缺闭括号
     "{\"a\":}", // 缺值
     "{\"a\" 1}", // 缺冒号
     "{\"a\":1,}", // 尾随逗号后缺键
     "nul", // 残缺关键字
     "tru", // 残缺关键字
     "12.", // 小数点后缺数字
     "1e", // 指数后缺数字
     "garbage", // 非 JSON 词法
     "{\"a\":1} trailing", // 尾随多余字符
  ]
  samples[rng.next_below(samples.length())]
}

///|
/// 类别 1：合法 JSON 但顶层非对象 → invalid_request。
fn gen_non_object_toplevel(rng : @infra_pbt.Rng) -> String {
  let samples = [
    "123", "-4.5", "2e3", "\"hello\"", "true", "false", "null", "[1,2,3]", "[]",
  ]
  samples[rng.next_below(samples.length())]
}

///|
/// 类别 2：对象缺失 `jsonrpc` 字段 → invalid_request。
fn gen_missing_jsonrpc(rng : @infra_pbt.Rng) -> String {
  let method_name = gen_err_ident(rng, 6)
  match rng.next_below(2) {
    0 => "{\"method\":\"" + method_name + "\",\"params\":[]}"
    _ => "{\"id\":1,\"method\":\"" + method_name + "\"}"
  }
}

///|
/// 类别 3：`jsonrpc` 字段缺省值非 "2.0"（错误版本 / 非字符串）→ invalid_request。
fn gen_bad_jsonrpc(rng : @infra_pbt.Rng) -> String {
  let method_name = gen_err_ident(rng, 6)
  let tail = "\",\"method\":\"" + method_name + "\"}"
  match rng.next_below(4) {
    0 => "{\"jsonrpc\":\"1.0" + tail
    1 => "{\"jsonrpc\":\"2.1" + tail
    2 => "{\"jsonrpc\":2,\"method\":\"" + method_name + "\"}" // 数值版本
    _ => "{\"jsonrpc\":true,\"method\":\"" + method_name + "\"}" // 布尔版本
  }
}

///|
/// 类别 4：`method` 字段非字符串 → invalid_request。
fn gen_non_string_method(rng : @infra_pbt.Rng) -> String {
  let head = "{\"jsonrpc\":\"2.0\",\"method\":"
  match rng.next_below(4) {
    0 => head + "123}"
    1 => head + "true}"
    2 => head + "[]}"
    _ => head + "{}}"
  }
}

///|
/// 类别 5：请求 `id` 字段非法（小数 / 指数 / 数组 / 对象 / 布尔）→ invalid_request。
fn gen_bad_id(rng : @infra_pbt.Rng) -> String {
  let method_name = gen_err_ident(rng, 6)
  let head = "{\"jsonrpc\":\"2.0\",\"method\":\"" + method_name + "\",\"id\":"
  match rng.next_below(5) {
    0 => head + "1.5}" // 小数 id
    1 => head + "2e3}" // 指数 id
    2 => head + "[]}" // 数组 id
    3 => head + "{}}" // 对象 id
    _ => head + "true}" // 布尔 id
  }
}

///|
/// 类别 6：响应同时含 result 与 error，或二者皆缺 → invalid_request。
fn gen_bad_response_payload(rng : @infra_pbt.Rng) -> String {
  let head = "{\"jsonrpc\":\"2.0\",\"id\":1"
  match rng.next_below(3) {
    0 => head + ",\"result\":1,\"error\":{\"code\":-1,\"message\":\"m\"}}" // 二者皆含
    1 => head + "}" // 二者皆缺
    _ => "{\"jsonrpc\":\"2.0\",\"id\":\"" + gen_err_ident(rng, 4) + "\"}" // 二者皆缺（字符串 id）
  }
}

///|
/// 类别 7：响应 `error` 对象结构非法（缺 code / message，或非对象）→ invalid_request。
fn gen_malformed_error_object(rng : @infra_pbt.Rng) -> String {
  let head = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":"
  match rng.next_below(4) {
    0 => head + "{\"code\":\"x\",\"message\":\"m\"}}" // code 非数值
    1 => head + "{\"message\":\"m\"}}" // 缺 code
    2 => head + "{\"code\":1}}" // 缺 message
    _ => head + "5}" // error 非对象
  }
}

///|
/// 类别 8：既无 `method` 又无 `id` → invalid_request。
fn gen_no_method_no_id(rng : @infra_pbt.Rng) -> String {
  match rng.next_below(2) {
    0 => "{\"jsonrpc\":\"2.0\"}"
    _ => "{\"jsonrpc\":\"2.0\",\"params\":[]}"
  }
}

///|
/// 综合「非法 JSON-RPC 字节序列」采样：在 9 个非法类别间均匀选择，再转为字节。
fn gen_illegal_message(rng : @infra_pbt.Rng) -> Bytes {
  let text = match rng.next_below(9) {
    0 => gen_malformed_json(rng)
    1 => gen_non_object_toplevel(rng)
    2 => gen_missing_jsonrpc(rng)
    3 => gen_bad_jsonrpc(rng)
    4 => gen_non_string_method(rng)
    5 => gen_bad_id(rng)
    6 => gen_bad_response_payload(rng)
    7 => gen_malformed_error_object(rng)
    _ => gen_no_method_no_id(rng)
  }
  err_text_to_bytes(text)
}

///|
/// 非法 JSON-RPC 字节序列生成器（封装为 @infra_pbt.Gen，供断言模板驱动）。
fn gen_illegal_message_bytes() -> @infra_pbt.Gen[Bytes] {
  @infra_pbt.Gen::new(fn(rng) { gen_illegal_message(rng) })
}

// ---------------------------------------------------------------------------
// 性质谓词
// ---------------------------------------------------------------------------

///|
/// 性质谓词：对一段非法字节序列，`decode_message` 应返回 `Err`，且错误码为
/// JSON-RPC 2.0 规范标准码之一（结构化错误，不 panic/abort）。
fn decode_yields_standard_error(bytes : Bytes) -> Bool {
  match decode_message(bytes) {
    Err(e) => is_standard_error_code(e.code)
    Ok(_) => false // 非法消息不应被成功解码。
  }
}

// ---------------------------------------------------------------------------
// 属性测试（Property 12）
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 12: LSP_Server 非法消息错误条件
///
/// 对任意由生成器产出的不符合 JSON-RPC 2.0 规范的字节序列，`decode_message`
/// 应返回结构化错误（标准错误码 + 消息），即以 `Result::Err` 承载而**不**通过
/// panic/abort 终止进程。复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认
/// 迭代 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 5.3**
test "Feature: moonbit-infra-suite, Property 12: illegal messages yield standard rpc errors (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(
    gen_illegal_message_bytes(),
    decode_yields_standard_error,
  )
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 12（聚焦不变量）：非法消息必返回 Err。
///
/// 直接断言「非法消息绝不被成功解码为合法 `JsonRpcMessage`」，与上面的标准错误码
/// 断言互补，共同覆盖 R5.3「返回符合规范的错误响应且不终止服务进程」。
///
/// **Validates: Requirements 5.3**
test "Feature: moonbit-infra-suite, Property 12: illegal messages never decode to Ok" {
  let ok = @infra_pbt.holds_for_all(gen_illegal_message_bytes(), fn(bytes) {
    match decode_message(bytes) {
      Err(_) => true
      Ok(_) => false
    }
  })
  assert_true(ok)
}
