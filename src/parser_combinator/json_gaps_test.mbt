// json_gaps_test.mbt —— JSON 错误恢复解析边角收口
// （INFRA 第二十五批；第三十三批追加 EOF/同步终止收口）。

///|
test "parse_json_recover：EOF 截断与缺分隔符再同步" {
  // 数组体在元素后 EOF（无 ',' 或 ']'）→ running 以 EOF 终止。
  let (v1, _) = @parser_combinator.parse_json_recover("[1")
  assert_true(v1 is Some(_))
  // 元素后既非分隔符也非终止符 → 再同步跳到 ']'。
  let (v2, _) = @parser_combinator.parse_json_recover("[1 2]")
  assert_true(v2 is Some(_))
  // 同步途中命中 EOF。
  let (v3, _) = @parser_combinator.parse_json_recover("[1 2")
  assert_true(v3 is Some(_))
  // 尾随空白直至 EOF（skip_ws_input 的 EOF 出口）。
  let (v4, _) = @parser_combinator.parse_json_recover("[1] ")
  assert_true(v4 is Some(_))
}

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
