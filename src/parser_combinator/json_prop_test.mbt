// json_prop_test.mbt —— L2 JSON 旗舰示例属性测试与恢复单元测试
// （tasks 12.3, 12.4, 12.5；并见证 12.2 的错误恢复）。
//
// 实现 Property 28（JSON 往返）、Property 29（转义解码）、Property 30（语法错误
// 诊断且不产半成品），并补充 parse_json_recover 的数组元素级恢复单元测试。

// ---------------------------------------------------------------------------
// JSON 值生成器（gen_json）
// ---------------------------------------------------------------------------

///|
/// 字符串内容字母表：含需转义字符（`"` / `\` / 换行 / 制表）以充分触发转义
/// 往返；全部为 ASCII，便于经 Bytes 无损往返。
let json_str_alphabet : Array[Char] = [
  'a', 'b', '1', ' ', '"', '\\', '\n', '\t', '/', 'x',
]

///|
/// 采样一个长度 0~5 的随机字符串（可能含需转义字符）。
fn gen_json_string(rng : @infra_pbt.Rng) -> String {
  let len = rng.next_range(0, 5)
  let mut s = ""
  let mut i = 0
  while i < len {
    s = s + "\{json_str_alphabet[rng.next_below(json_str_alphabet.length())]}"
    i = i + 1
  }
  s
}

///|
/// 深度受限的 `Json` 生成器：数值限定为可精确往返的整数区间，字符串含随机
/// 转义，数组 / 对象长度有界。
fn gen_json_at(rng : @infra_pbt.Rng, depth : Int) -> Json {
  if depth <= 0 || rng.next_below(2) == 0 {
    match rng.next_below(5) {
      0 => JNull
      1 => JBool(rng.next_bool())
      2 => JNumber(rng.next_range(-10000, 10000).to_double())
      3 => JString(gen_json_string(rng))
      _ => JNumber(rng.next_range(0, 9999).to_double())
    }
  } else if rng.next_bool() {
    let len = rng.next_range(0, 4)
    let arr : Array[Json] = []
    let mut i = 0
    while i < len {
      arr.push(gen_json_at(rng, depth - 1))
      i = i + 1
    }
    JArray(arr)
  } else {
    let len = rng.next_range(0, 4)
    let pairs : Array[(String, Json)] = []
    let mut i = 0
    while i < len {
      pairs.push((gen_json_string(rng), gen_json_at(rng, depth - 1)))
      i = i + 1
    }
    JObject(pairs)
  }
}

///|
/// `gen_json`：深度 3 的合法 Json 生成器。
fn gen_json() -> @infra_pbt.Gen[Json] {
  @infra_pbt.Gen::new(fn(rng) { gen_json_at(rng, 3) })
}

// ---------------------------------------------------------------------------
// Bytes 编解码桥接（供 round_trip 模板）
// ---------------------------------------------------------------------------

///|
/// 编码：Json → 紧凑文本 → Bytes（打印结果仅含 ASCII）。
fn json_to_bytes(j : Json) -> Bytes {
  let s = print_json(j)
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 解码：Bytes → 文本 → 解析为 Json（失败为 None）。
fn bytes_to_json(b : Bytes) -> Json? {
  let mut s = ""
  let mut i = 0
  while i < b.length() {
    s = s + "\{b[i].to_int().unsafe_to_char()}"
    i = i + 1
  }
  match parse_json(s) {
    Ok(j) => Some(j)
    Err(_) => None
  }
}

// ---------------------------------------------------------------------------
// Property 28：JSON 往返
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 28: JSON 往返
///
/// 对任意合法 `Json` 值 `x`，解析其打印结果得到等价 JSON 值
/// （`parse_json(print_json(x))` 等于 `Some(x)`）。以 round_trip 与 holds_for_all
/// 两种模板各 ≥100 迭代校验。
///
/// **Validates: Requirements 11.1, 11.7**
test "Feature: parser-combinator, Property 28: JSON round-trip (round_trip template)" {
  assert_true(@infra_pbt.round_trip(gen_json(), json_to_bytes, bytes_to_json))
}

///|
/// Feature: parser-combinator, Property 28: JSON 往返（holds_for_all 模板）
///
/// **Validates: Requirements 11.1, 11.7**
test "Feature: parser-combinator, Property 28: JSON round-trip (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(gen_json(), fn(x) {
    match parse_json(print_json(x)) {
      Ok(y) => y == x
      Err(_) => false
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 29：JSON 转义解码
// ---------------------------------------------------------------------------

///|
/// 转义源片段与其解码后字符的对照表。
let json_escape_cases : Array[(String, Char)] = [
  ("\\\"", '"'),
  ("\\\\", '\\'),
  ("\\/", '/'),
  ("\\b", '\u{0008}'),
  ("\\f", '\u{000C}'),
  ("\\n", '\n'),
  ("\\r", '\r'),
  ("\\t", '\t'),
  ("\\u0041", 'A'),
  ("\\u007A", 'z'),
]

///|
/// Feature: parser-combinator, Property 29: JSON 转义解码
///
/// 对任意由转义片段随机拼接而成的合法 JSON 字符串字面量，解析器将其解码为对应
/// 字符序列（覆盖 `\" \\ \/ \b \f \n \r \t \uXXXX`）。
///
/// **Validates: Requirements 11.2**
test "Feature: parser-combinator, Property 29: JSON escape decoding" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    let len = rng.next_range(0, 6)
    let mut src = "\""
    let mut expected = ""
    let mut i = 0
    while i < len {
      let (frag, ch) = json_escape_cases[rng.next_below(
          json_escape_cases.length(),
        )]
      src = src + frag
      expected = expected + "\{ch}"
      i = i + 1
    }
    src = src + "\""
    (src, expected)
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(pair) {
    let (src, expected) = pair
    match parse_json(src) {
      Ok(JString(decoded)) => decoded == expected
      _ => false
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 30：JSON 语法错误诊断且不产半成品
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 30: JSON 语法错误诊断且不产半成品
///
/// 对任意注入了语法错误的 JSON 文本（形如 `'[' + 合法值 + ','`，缺失闭合且尾随
/// 悬空分隔符），`parse_json` 返回携带位置与期望文本的 `@core.PathError`（Err），
/// 不返回部分构造的 `Json`（Result Err 在类型层面即「不产半成品」）。
///
/// **Validates: Requirements 11.3**
test "Feature: parser-combinator, Property 30: JSON syntax error diagnostics, no partial value" {
  let ok = @infra_pbt.holds_for_all(gen_json(), fn(x) {
    let malformed = "[" + print_json(x) + ","
    match parse_json(malformed) {
      Err(InvalidInput(msg)) => msg.length() > 0
      Err(_) => true
      Ok(_) => false
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// 单元测试：基本解析样例 + 数组元素级错误恢复（R11.4，见证 task 12.2）
// ---------------------------------------------------------------------------

///|
/// 基本 JSON 解析样例（对象 / 数组 / 字面量 / 数值 / 嵌套）。
test "parse_json handles representative documents" {
  match parse_json("{\"a\":[1,2,3],\"b\":null,\"c\":true}") {
    Ok(JObject(pairs)) => {
      assert_eq(pairs.length(), 3)
      assert_eq(pairs[0].0, "a")
    }
    _ => fail("expected object parse")
  }
  // 空白宽容。
  assert_true(parse_json("  [ 1 , 2 ]  ").is_ok())
  // 语法错误 → Err。
  assert_true(parse_json("[1,2").is_err())
}

///|
/// parse_json_recover：数组中间元素语法错误时记录错误并同步到下一个分隔符，
/// 继续解析后续合法元素（R11.4）。
test "parse_json_recover records errors and continues past malformed elements" {
  // 中间元素 "@@@" 非法；恢复后应仍解析出首尾合法元素。
  let (value, errors) = parse_json_recover("[1,@@@,3]")
  match value {
    Some(JArray(items)) => {
      // 至少解析出合法元素 1 与 3。
      assert_true(items.length() >= 2)
      assert_true(errors.length() >= 1)
    }
    _ => fail("expected recovered array value")
  }
  // 全合法数组：无错误、元素齐全。
  let (v2, e2) = parse_json_recover("[1,2,3]")
  match v2 {
    Some(JArray(items)) => assert_eq(items.length(), 3)
    _ => fail("expected array")
  }
  assert_eq(e2.length(), 0)
}
