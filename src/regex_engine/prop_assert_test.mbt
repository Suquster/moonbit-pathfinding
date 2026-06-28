// prop_assert_test.mbt —— Property 6：零宽不变量与断言位置判定（任务 6.5）。
//
// Feature: regex-engine, Property 6: 零宽不变量与断言位置判定
//
// 对任意输入与位置 `pos`：词边界 `\b` 的判定等于参考谓词「`pos` 左右词字符性
// 相异」（串首前 / 串尾后视为非词字符），`\B` 在每个位置恰为 `\b` 之逻辑非；
// 将任一满足的零宽断言插入正则任意位置，其对整体匹配消费长度的贡献恒为 0；
// 多行 `^`/`$` 行首尾判定、非多行仅整串首尾判定，复用同一位置判定逻辑。
//
// **Validates: Requirements 5.2, 5.3, 5.7, 6.5, 6.6**
//
// 探测技巧：以 `\A`（文本起始锚）+ 字面前缀强制匹配从 0 起恰好消费 `pos` 个
// 字符，使紧随其后的零宽断言恰在位置 `pos` 求值；`is_match` 成立 ⇔ 该断言在
// `pos` 成立。字母表均为非元字符，字面前缀无需转义。≥100 迭代。

// ---------------------------------------------------------------------------
// 参考谓词与切片辅助
// ---------------------------------------------------------------------------

///|
/// 词字符参考谓词（`\w`：数字 / 字母 / 下划线）。
fn ar_is_word(c : Int) -> Bool {
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  c == '_'.to_int()
}

///|
/// 词边界参考谓词：`pos` 左右词字符性相异（边界外视为非词字符）。
fn ar_wb(chars : Array[Char], n : Int, pos : Int) -> Bool {
  let left = pos > 0 && ar_is_word(chars[pos - 1].to_int())
  let right = pos < n && ar_is_word(chars[pos].to_int())
  left != right
}

///|
/// 字面切片 `[a,b)`（字符均为非元字符，可直接作为模式字面前缀）。
fn ar_lit(chars : Array[Char], a : Int, b : Int) -> String {
  let mut s = ""
  for k in a..<b {
    s = s + chars[k].to_string()
  }
  s
}

///|
/// 编译并判定是否匹配（编译失败视为不匹配，便于暴露生成器问题）。
fn ar_is_match(pat : String, s : String) -> Bool {
  match Pattern::compile(pat) {
    Ok(p) => p.is_match(s)
    Err(_) => false
  }
}

///|
/// 编译并取整体匹配区间。
fn ar_find(pat : String, s : String) -> Match? {
  match Pattern::compile(pat) {
    Ok(p) => p.find(s)
    Err(_) => None
  }
}

///|
/// 锚定探测：`flags_prefix` + `\A` + 前缀字面（消费到 pos）+ `assertStr`，
/// `is_match` 成立 ⇔ 该断言在位置 `pos` 成立。
fn ar_probe(
  flags_prefix : String,
  chars : Array[Char],
  pos : Int,
  assert_str : String,
  s : String,
) -> Bool {
  ar_is_match(flags_prefix + "\\A" + ar_lit(chars, 0, pos) + assert_str, s)
}

// ---------------------------------------------------------------------------
// 生成器
// ---------------------------------------------------------------------------

///|
/// 词 / 非词混合字符串（含下划线、空格、井号），覆盖各类边界过渡。
fn ar_wb_string(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let alphabet : Array[Char] = ['a', 'b', '1', '_', ' ', '#']
  let len = rng.next_below(max_len + 1)
  let mut s = ""
  for _i in 0..<len {
    s = s + alphabet[rng.next_below(alphabet.length())].to_string()
  }
  s
}

///|
/// 含换行的字符串，用于多行 `^`/`$` 行首尾判定。
fn ar_nl_string(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let alphabet : Array[Char] = ['a', 'b', '\n']
  let len = rng.next_below(max_len + 1)
  let mut s = ""
  for _i in 0..<len {
    s = s + alphabet[rng.next_below(alphabet.length())].to_string()
  }
  s
}

///|
/// `(字符串, 位置 pos∈[0,len])` 生成器（词 / 非词字母表）。
fn gen_wb_pos() -> @infra_pbt.Gen[(String, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let s = ar_wb_string(rng, 6)
    let n = s.iter().to_array().length()
    (s, rng.next_below(n + 1))
  })
}

///|
/// `(含换行字符串, 位置 pos∈[0,len])` 生成器。
fn gen_nl_pos() -> @infra_pbt.Gen[(String, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let s = ar_nl_string(rng, 6)
    let n = s.iter().to_array().length()
    (s, rng.next_below(n + 1))
  })
}

// ---------------------------------------------------------------------------
// Property 6
// ---------------------------------------------------------------------------

///|
/// Feature: regex-engine, Property 6: 词边界判定等于参考谓词，`\B` 为其逻辑非
///
/// **Validates: Requirements 5.2, 5.3, 5.7**
test "Feature: regex-engine, Property 6: word boundary equals reference predicate" {
  let ok = @infra_pbt.holds_for_all(gen_wb_pos(), fn(pair) {
    let (s, pos) = pair
    let chars = s.iter().to_array()
    let n = chars.length()
    let expected = ar_wb(chars, n, pos)
    let holds_b = ar_probe("", chars, pos, "\\b", s)
    let holds_nb = ar_probe("", chars, pos, "\\B", s)
    holds_b == expected && holds_nb == !expected && holds_b != holds_nb
  })
  assert_true(ok)
}

///|
/// Feature: regex-engine, Property 6: 零宽断言对消费长度的贡献恒为 0
///
/// 在位置 `k` 插入一个在该位置满足的零宽断言（`\b` / `\B` 取其一），整体匹配
/// 区间与不插入时逐字段相等（消费长度不变）。
///
/// **Validates: Requirements 5.7**
test "Feature: regex-engine, Property 6: satisfied zero-width assertion consumes nothing" {
  let ok = @infra_pbt.holds_for_all(gen_wb_pos(), fn(pair) {
    let (s, k) = pair
    let chars = s.iter().to_array()
    let n = chars.length()
    // 在位置 k 必满足的零宽断言（\b 与 \B 互补，恒有其一成立）。
    let satisfied = if ar_wb(chars, n, k) { "\\b" } else { "\\B" }
    let base = "\\A" + ar_lit(chars, 0, k) + ar_lit(chars, k, n)
    let with_assert = "\\A" +
      ar_lit(chars, 0, k) +
      satisfied +
      ar_lit(chars, k, n)
    let m0 = ar_find(base, s)
    let m1 = ar_find(with_assert, s)
    // 不插入时匹配整串 [0,n)；插入满足的零宽断言后区间不变。
    m0 == Some({ start: 0, end: n }) && m1 == m0
  })
  assert_true(ok)
}

///|
/// Feature: regex-engine, Property 6: 多行 / 非多行 `^`/`$` 位置判定逻辑
///
/// **Validates: Requirements 6.5, 6.6**
test "Feature: regex-engine, Property 6: line vs text anchors position logic" {
  let ok = @infra_pbt.holds_for_all(gen_nl_pos(), fn(pair) {
    let (s, pos) = pair
    let chars = s.iter().to_array()
    let n = chars.length()
    // 参考：多行行首 / 行尾、非多行整串首 / 尾。
    let ref_line_start = pos == 0 || (pos > 0 && chars[pos - 1] == '\n')
    let ref_text_start = pos == 0
    let ref_line_end = pos == n || (pos < n && chars[pos] == '\n')
    let ref_text_end = pos == n
    let line_start = ar_probe("(?m)", chars, pos, "^", s)
    let text_start = ar_probe("", chars, pos, "^", s)
    let line_end = ar_probe("(?m)", chars, pos, "$", s)
    let text_end = ar_probe("", chars, pos, "$", s)
    line_start == ref_line_start &&
    text_start == ref_text_start &&
    line_end == ref_line_end &&
    text_end == ref_text_end
  })
  assert_true(ok)
}

///|
/// 代表性见证：`\b`、多行 `^`、非多行 `^`。
test "zero-width assertion representative witnesses" {
  // 串首前视为非词，'a' 为词 → \b 在 0 成立。
  assert_true(ar_is_match("\\ba", "abc"))
  // 'b' 左侧 'a' 为词、'b' 为词 → \b 在 1 不成立；\B 成立。
  assert_true(ar_probe("", "ab".iter().to_array(), 1, "\\B", "ab"))
  assert_false(ar_probe("", "ab".iter().to_array(), 1, "\\b", "ab"))
  // 多行 `^` 在换行后行首匹配。
  match Pattern::compile("(?m)^b") {
    Ok(p) => assert_true(p.find("a\nb") == Some({ start: 2, end: 3 }))
    Err(_) => fail("compile failed for (?m)^b")
  }
  // 非多行 `^b` 仅整串首匹配 → "a\nb" 无匹配。
  match Pattern::compile("^b") {
    Ok(p) => assert_false(p.is_match("a\nb"))
    Err(_) => fail("compile failed for ^b")
  }
}
