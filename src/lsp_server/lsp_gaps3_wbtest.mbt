// 白盒测试：覆盖率审计收口（INFRA 第六十四批）——
// 格式化非法键行、整数解析余支、补全去重、重命名缺符号与
// 工作区编辑越界/乱序、位置编码越界拒绝。

///|
test "format：is_valid_key 空串/数字开头/非法字符拒绝" {
  assert_false(is_valid_key(""))
  assert_false(is_valid_key("1a"))
  assert_false(is_valid_key("a-b"))
}

///|
test "format：无等号行与非法键行不动" {
  let doc : TextDocument = { uri: "u", text: "noequals\n1bad = 2\nok=1" }
  let edits = formatting(doc)
  assert_eq(edits.length(), 1)
  assert_eq(edits[0].new_text, "ok = 1")
}

///|
test "server：parse_int 空串/正号/尾随垃圾余支" {
  assert_true(parse_int("") is None)
  assert_true(parse_int("+5") is Some(5))
  assert_true(parse_int("+") is None)
  assert_true(parse_int("1x") is None)
}

///|
test "server：on_completion 重名符号去重" {
  let r : Range = {
    start: { line: 0, character: 0 },
    end: { line: 0, character: 1 },
  }
  let a : Analysis = {
    uri: "u",
    symbols: [
      { name: "k", range: r, value: "1" },
      { name: "k", range: r, value: "2" },
    ],
    references: [],
    diagnostics: [],
  }
  assert_eq(on_completion(a, { line: 0, character: 0 }).length(), 1)
}

///|
test "rename：缺失符号仅重写引用侧" {
  let a = analyze({ uri: "u", text: "k = 1" })
  let we = rename(a, "missing", "m2")
  assert_eq(we.changes[0].1.length(), 0)
}

///|
test "apply_workspace_edit：越界编辑忽略且乱序编辑重排" {
  let far : Position = { line: 9, character: 0 }
  let bad : TextEdit = { range: { start: far, end: far }, new_text: "X" }
  let bad2 : TextEdit = {
    range: { start: { line: 0, character: 0 }, end: far },
    new_text: "Y",
  }
  assert_eq(apply_workspace_edit("ab", [bad, bad2]), "ab")
  let e1 : TextEdit = {
    range: { start: { line: 0, character: 1 }, end: { line: 0, character: 2 } },
    new_text: "Z",
  }
  let e0 : TextEdit = {
    range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
    new_text: "W",
  }
  assert_eq(apply_workspace_edit("ab", [e1, e0]), "WZ")
}

///|
test "position_encoding：行越界与非法下标拒绝" {
  assert_true(
    convert_position("a", { line: 5, character: 0 }, from=Utf16, to=Utf8)
    is None,
  )
  assert_true(index_to_char([97], Utf16, -1) is None)
  assert_true(index_to_char([97], Utf16, 2) is None)
}
