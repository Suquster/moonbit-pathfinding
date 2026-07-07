// unicode_class_syntax_test.mbt —— `\p{...}` / `\P{...}` 记法接入端到端测试。
//
// 覆盖顶层转义、字符类内元素、`Pattern::compile` 全链路匹配、以及畸形记法
// （缺花括号 / 未闭合 / 未知类别名）的显式拒绝（返回 Err / None，不 panic）。

///|
/// 顶层 `\p{L}` 解析为字符集合并可全链路匹配字母（含非 ASCII）。
test "pattern \\p{L} matches letters end to end" {
  match Pattern::compile("\\p{L}+") {
    Ok(p) => {
      match p.find_at("  héllo  ", 0) {
        Some(m) => assert_true(m.start == 2 && m.end == 7)
        None => assert_true(false)
      }
      assert_true(p.find_at("12345", 0) is None)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// `\p{Nd}` 匹配十进制数字；`\P{Nd}` 匹配其补集。
test "pattern \\p{Nd} and \\P{Nd} complement pair" {
  match Pattern::compile("\\p{Nd}+") {
    Ok(p) =>
      match p.find_at("ab123cd", 0) {
        Some(m) => assert_true(m.start == 2 && m.end == 5)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
  match Pattern::compile("\\P{Nd}+") {
    Ok(p) =>
      match p.find_at("123abc", 0) {
        Some(m) => assert_true(m.start == 3 && m.end == 6)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// 字符类内 `[\p{Nd}_]`：Unicode 类与字面元素可混排。
test "class element \\p{Nd} mixes with literals" {
  match Pattern::compile("[\\p{Nd}_]+") {
    Ok(p) =>
      match p.find_at("a1_2b", 0) {
        Some(m) => assert_true(m.start == 1 && m.end == 4)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// 否定类中的 `\p`：`[^\p{Nd}]` 匹配非数字。
test "negated class with \\p{Nd}" {
  match Pattern::compile("[^\\p{Nd}]+") {
    Ok(p) =>
      match p.find_at("12ab34", 0) {
        Some(m) => assert_true(m.start == 2 && m.end == 4)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// 畸形记法显式拒绝：缺花括号、未闭合、未知类别名（顶层与类内）。
test "malformed \\p notations are rejected" {
  assert_true(parse_pattern("\\pL") is Err(_))
  assert_true(parse_pattern("\\p{L") is Err(_))
  assert_true(parse_pattern("\\p{Xy}") is Err(_))
  assert_true(parse_pattern("\\p{}") is Err(_))
  assert_true(parse_pattern("[\\p{L]") is Err(_))
  assert_true(parse_pattern("[\\p{Zz}]") is Err(_))
}

///|
/// 大类聚合语义：`\p{N}` ⊇ `\p{Nd}`（对同一数字输入两者都命中）。
test "\\p{N} superset of \\p{Nd} on digits" {
  match (Pattern::compile("\\p{N}"), Pattern::compile("\\p{Nd}")) {
    (Ok(pn), Ok(pnd)) => {
      assert_true(pn.find_at("7", 0) is Some(_))
      assert_true(pnd.find_at("7", 0) is Some(_))
    }
    _ => assert_true(false)
  }
}
