// 白盒测试：覆盖率审计收口（INFRA 第七十批）——
// 原子解析器兜底臂：空输入、裸 ')' / '|'、字符类内 EOF。

///|
test "parse_atom：空输入与裸元字符兜底报错" {
  assert_true(parse_atom(@pc.Input::from_string("")) is Err(_))
  assert_true(parse_atom(@pc.Input::from_string(")")) is Err(_))
  assert_true(parse_atom(@pc.Input::from_string("|")) is Err(_))
}

///|
test "read_class_char：字符类内 EOF 报未闭合" {
  assert_true(read_class_char(@pc.Input::from_string("")) is Err(_))
}

///|
test "p_atom：空输入与裸元字符兜底报错" {
  let st : PState = { next_group: 1, names: Map([]), flags: Flags::default() }
  assert_true(p_atom(st, @pc.Input::from_string("")) is Err(_))
  assert_true(p_atom(st, @pc.Input::from_string(")")) is Err(_))
  assert_true(p_atom(st, @pc.Input::from_string("|")) is Err(_))
}

///|
test "read_class_token：字符类内 EOF 报未闭合" {
  assert_true(read_class_token(@pc.Input::from_string(""), 0) is Err(_))
}
