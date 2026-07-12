// gaps84_test.mbt —— 增量同步越界拒绝与编码换算代理项边界（第八十四批）。

///|
/// apply_incremental：range.start 越界 → invalid_params 拒绝。
test "apply_incremental：起点越界拒绝" {
  let ch : ContentChange = {
    range: Some({
      start: { line: 9, character: 0 },
      end: { line: 9, character: 1 },
    }),
    text: "x",
  }
  match apply_incremental("ab", ch, Utf16) {
    Err(e) => assert_eq(e.code, @lsp_binding.invalid_params_code)
    Ok(_) => fail("起点越界应拒绝")
  }
}

///|
/// apply_incremental：range.end 越界（起点合法）→ invalid_params 拒绝。
test "apply_incremental：终点越界拒绝" {
  let ch : ContentChange = {
    range: Some({
      start: { line: 0, character: 0 },
      end: { line: 0, character: 99 },
    }),
    text: "x",
  }
  match apply_incremental("ab", ch, Utf16) {
    Err(e) => assert_eq(e.code, @lsp_binding.invalid_params_code)
    Ok(_) => fail("终点越界应拒绝")
  }
}

///|
/// apply_incremental：range.start 在 range.end 之后 → invalid_params 拒绝。
test "apply_incremental：起点晚于终点拒绝" {
  let ch : ContentChange = {
    range: Some({
      start: { line: 0, character: 2 },
      end: { line: 0, character: 1 },
    }),
    text: "x",
  }
  match apply_incremental("abc", ch, Utf16) {
    Err(e) => assert_eq(e.code, @lsp_binding.invalid_params_code)
    Ok(_) => fail("起点晚于终点应拒绝")
  }
}

///|
/// offset_to_position：offset 落在代理对中间（UTF-16）→ None。
test "offset_to_position：代理对中间拒绝" {
  // "𝄞" 占 2 个 UTF-16 码元；offset=1 落在其中间。
  assert_true(offset_to_position("𝄞a", 1, Utf16) is None)
}

///|
/// convert_position：字符位落在代理对中间 → None。
test "convert_position：代理对中间拒绝" {
  assert_true(
    convert_position("𝄞a", { line: 0, character: 1 }, from=Utf16, to=Utf8)
    is None,
  )
}
