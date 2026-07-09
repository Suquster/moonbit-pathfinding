// json_gaps_test.mbt —— JSON 错误恢复解析边角收口
// （INFRA 第二十五批）。

///|
test "parse_json_recover：非数组退化为严格解析" {
  let (v1, e1) = parse_json_recover("  42")
  assert_true(v1 is Some(JNumber(_)))
  assert_eq(e1.length(), 0)
  let (v2, e2) = parse_json_recover("  @bad")
  assert_true(v2 is None)
  assert_eq(e2.length(), 1)
}

///|
test "parse_json_recover：前导空白后的空数组" {
  let (v, e) = parse_json_recover("  [  ]")
  assert_true(v is Some(JArray(_)))
  assert_eq(e.length(), 0)
}

///|
test "parse_json_recover：畸形元素记录错误并同步继续" {
  let (v, e) = parse_json_recover("[1, @x, 3]")
  match v {
    Some(JArray(items)) => assert_eq(items.length(), 2)
    _ => assert_true(false)
  }
  assert_true(e.length() >= 1)
}
