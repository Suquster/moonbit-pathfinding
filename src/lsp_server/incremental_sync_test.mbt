// incremental_sync_test.mbt —— 单条增量变更 O(N) 应用的烟雾测试（任务 11.2）。
//
// 仅作最小见证（完整属性测试见任务 11.3）：
//   * AC4 一致性：`apply_incremental(doc, change, enc)` 与
//     `apply_changes(doc, [change], enc)` 对单条变更逐字符一致。
//   * `range = None` 全量替换。
//   * 插入 / 删除 / 替换三类基于范围的变更行为正确。
//
// 列号编码统一取 `Utf16`（LSP 默认）；测试文本为 ASCII，三编码列号一致。

///|
/// 构造一条单行 `Incremental` 内容变更：替换 `[ (0,sc) , (0,ec) )` 为 `text`。
fn inc_change(sc : Int, ec : Int, text : String) -> ContentChange {
  {
    range: Some({
      start: { line: 0, character: sc },
      end: { line: 0, character: ec },
    }),
    text,
  }
}

///|
/// AC4：单条变更下 `apply_incremental` 与 `apply_changes` 结果一致（插入 / 删除 /
/// 替换三类各一例）。
test "apply_incremental matches apply_changes for a single change" {
  let doc = "hello world"
  let cases = [
    inc_change(0, 0, "X"), // 行首插入
    inc_change(5, 6, ""), // 删除中间空格
    inc_change(6, 11, "moon"), // 替换尾部单词
  ]
  for ch in cases {
    let single = match apply_incremental(doc, ch, Utf16) {
      Ok(s) => s
      Err(e) => fail("apply_incremental error: " + e.message)
    }
    let batch = match apply_changes(doc, [ch], Utf16) {
      Ok(s) => s
      Err(e) => fail("apply_changes error: " + e.message)
    }
    assert_eq(single, batch)
  }
}

///|
/// `range = None` 等价于全量替换：结果即 `change.text`。
test "apply_incremental with range None replaces the whole document" {
  let change : ContentChange = { range: None, text: "brand new content" }
  match apply_incremental("old text here", change, Utf16) {
    Ok(result) => assert_eq(result, "brand new content")
    Err(e) => fail("expected Ok, got error: " + e.message)
  }
}

///|
/// 三类基于范围的变更行为见证：插入、删除、替换。
test "apply_incremental insert/delete/replace behave correctly" {
  // 插入：在 (0,3)-(0,3) 处插入 "-" → "abc-def"
  match apply_incremental("abcdef", inc_change(3, 3, "-"), Utf16) {
    Ok(r) => assert_eq(r, "abc-def")
    Err(e) => fail("insert error: " + e.message)
  }
  // 删除：删除 (0,1)-(0,4)（"bcd"）→ "aef"
  match apply_incremental("abcdef", inc_change(1, 4, ""), Utf16) {
    Ok(r) => assert_eq(r, "aef")
    Err(e) => fail("delete error: " + e.message)
  }
  // 替换：把 (0,0)-(0,3)（"abc"）替换为 "Z" → "Zdef"
  match apply_incremental("abcdef", inc_change(0, 3, "Z"), Utf16) {
    Ok(r) => assert_eq(r, "Zdef")
    Err(e) => fail("replace error: " + e.message)
  }
}

///|
/// 越界范围返回 `Err(invalid_params_code)`，不返回部分结果。
test "apply_incremental out-of-bounds range returns invalid_params error" {
  match apply_incremental("abc", inc_change(0, 99, "X"), Utf16) {
    Ok(_) => fail("expected Err for out-of-bounds range")
    Err(e) => assert_eq(e.code, @lsp_binding.invalid_params_code)
  }
}
