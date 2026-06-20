// sync_test.mbt —— 增量文档同步单元测试（任务 7.2）。
//
// 针对 sync.mbt 的 `apply_changes` / `VersionedDocument::apply`，覆盖
// Requirement 3.3 / 3.4 / 3.5 的**具体见证**：
//   * R3.4 多变更顺序：同一通知的多条 `contentChanges` 按出现顺序依次应用，
//     且每条作用于「上一条变更后的文本」（后一条的列号按前一条结果文本计）。
//   * R3.3 版本号更新：成功变更后 `VersionedDocument.version` 更新为通知携带
//     的版本号、文本同步更新。
//   * R3.5 越界不改文本：某条增量变更范围越界时返回携带定位信息的
//     `Err(invalid_params_code)`，且不返回部分应用结果（原文档不变）。
//   * 附：R3.1 Full 全文替换的具体见证（range = None）。
//
// 断言策略：
//   * `String` 派生 Show，结果文本直接用 `assert_eq`。
//   * `@lsp_binding.RpcError` 派生 (Eq, Show)，错误码 `e.code` 为 Int，越界用
//     `match ... { Err(e) => assert_eq(e.code, @lsp_binding.invalid_params_code) }`。
//   * `VersionedDocument` 仅派生 Eq（无 Show），故对成功结果用 `match` 提取
//     `uri`/`text`/`version` 字段（均为 String/Int，有 Show）后用 `assert_eq`。
//
// 列号编码统一取 `Utf16`（LSP 默认）；测试文本均为 ASCII / BMP，三编码列号一致。

// ───────────────────────── 测试辅助（本文件私有） ─────────────────────

///|
/// 构造一条单行 `Incremental` 内容变更：替换 `[ (0,sc) , (0,ec) )` 为 `text`。
fn sync_change(sc : Int, ec : Int, text : String) -> ContentChange {
  {
    range: Some({
      start: { line: 0, character: sc },
      end: { line: 0, character: ec },
    }),
    text,
  }
}

// ───────────────────────── R3.4 多变更按序应用 ────────────────────────

///|
/// 同一通知两条 `contentChanges` 按出现顺序依次应用，第二条作用于第一条结果：
///   text = "abc"
///   变更 1：在 (0,0)-(0,0) 处插入 "X"        → "Xabc"
///   变更 2：把 (0,1)-(0,2)（"Xabc" 中的 'a'）替换为 "A" → "XAbc"
/// 关键见证：变更 2 的列号 [1,2) 是按变更 1 的结果文本 "Xabc" 计量的（指向
/// 'a'），而非原文本 "abc"。若忽略顺序/不基于前一结果，结果将不同。
test "apply_changes applies multiple contentChanges in order" {
  let changes = [sync_change(0, 0, "X"), sync_change(1, 2, "A")]
  match apply_changes("abc", changes, Utf16) {
    Ok(result) => assert_eq(result, "XAbc")
    Err(e) => fail("expected Ok, got error: " + e.message)
  }
}

///|
/// 顺序敏感性的进一步见证：相同两条变更若交换顺序会得到不同结果。
///   text = "hello"
///   变更 1：把 (0,0)-(0,1)（'h'）替换为 "H" → "Hello"
///   变更 2：把 (0,4)-(0,5)（"Hello" 中的 'o'）替换为 "O" → "HellO"
test "apply_changes order: each change builds on the previous result" {
  let changes = [sync_change(0, 1, "H"), sync_change(4, 5, "O")]
  match apply_changes("hello", changes, Utf16) {
    Ok(result) => assert_eq(result, "HellO")
    Err(e) => fail("expected Ok, got error: " + e.message)
  }
}

// ───────────────────────── R3.1 Full 全文替换 ─────────────────────────

///|
/// `range = None`（Full）：以该条 `text` 整体替换文档全文。
test "apply_changes Full replacement replaces entire text" {
  let changes : Array[ContentChange] = [{ range: None, text: "brand new text" }]
  match apply_changes("old contents", changes, Utf16) {
    Ok(result) => assert_eq(result, "brand new text")
    Err(e) => fail("expected Ok, got error: " + e.message)
  }
}

// ───────────────────────── R3.3 变更后版本号更新 ──────────────────────

///|
/// 成功变更后 `version` 更新为通知携带的版本号、文本同步更新。
///   doc = { uri, text: "hello", version: 1 }，apply 一条 Full 变更 new_version=2
///   → 文本变为 "world"、version == 2、uri 不变。
test "VersionedDocument::apply updates version and text on success" {
  let doc : VersionedDocument = {
    uri: "file:///a.conf",
    text: "hello",
    version: 1,
  }
  let changes : Array[ContentChange] = [{ range: None, text: "world" }]
  match doc.apply(changes, 2, Utf16) {
    Ok(updated) => {
      assert_eq(updated.uri, "file:///a.conf")
      assert_eq(updated.text, "world")
      assert_eq(updated.version, 2)
    }
    Err(e) => fail("expected Ok, got error: " + e.message)
  }
}

///|
/// 增量变更同样更新版本号：text="abc"，把 (0,1)-(0,2)（'b'）替换为 "B"，
/// new_version=7 → 文本 "aBc"、version == 7。
test "VersionedDocument::apply updates version on incremental change" {
  let doc : VersionedDocument = {
    uri: "file:///b.conf",
    text: "abc",
    version: 3,
  }
  match doc.apply([sync_change(1, 2, "B")], 7, Utf16) {
    Ok(updated) => {
      assert_eq(updated.text, "aBc")
      assert_eq(updated.version, 7)
    }
    Err(e) => fail("expected Ok, got error: " + e.message)
  }
}

// ───────────────────────── R3.5 越界变更不改文本 ──────────────────────

///|
/// 增量变更范围越界（行号 100 超出单行文本）：`apply_changes` 返回携带定位
/// 信息的 `Err(invalid_params_code)`，不返回部分应用结果。
test "apply_changes out-of-bounds range yields invalid_params error" {
  let oob : ContentChange = {
    range: Some({
      start: { line: 100, character: 0 },
      end: { line: 100, character: 1 },
    }),
    text: "X",
  }
  match apply_changes("hello", [oob], Utf16) {
    Err(e) => assert_eq(e.code, @lsp_binding.invalid_params_code)
    Ok(_) => fail("expected an invalid_params error for out-of-bounds range")
  }
}

///|
/// 列号越界（单行文本，character 越过行尾）：同样返回 `invalid_params_code`。
test "apply_changes out-of-bounds character yields invalid_params error" {
  match apply_changes("hi", [sync_change(0, 99, "X")], Utf16) {
    Err(e) => assert_eq(e.code, @lsp_binding.invalid_params_code)
    Ok(_) =>
      fail("expected an invalid_params error for out-of-bounds character")
  }
}

///|
/// 越界变更经 `VersionedDocument::apply` 返回 `Err`，文档不被部分修改：
/// 由于返回 `Err` 而非 `Ok`，调用方不会得到任何（部分应用的）新文档，原 `doc`
/// 值不变。断言返回 `Err(invalid_params_code)`，并见证原 doc 文本/版本保持原值。
test "VersionedDocument::apply out-of-bounds leaves document unchanged" {
  let doc : VersionedDocument = {
    uri: "file:///c.conf",
    text: "hello",
    version: 5,
  }
  let oob : ContentChange = {
    range: Some({
      start: { line: 0, character: 50 },
      end: { line: 0, character: 60 },
    }),
    text: "ZZ",
  }
  match doc.apply([oob], 6, Utf16) {
    Err(e) => assert_eq(e.code, @lsp_binding.invalid_params_code)
    Ok(_) => fail("expected an invalid_params error; document must not change")
  }
  // 原 doc 是不可变值，未被任何部分应用结果替换：文本与版本保持原值。
  assert_eq(doc.text, "hello")
  assert_eq(doc.version, 5)
}

///|
/// 多条变更中后一条越界：整体返回 `Err`，不返回前一条已应用的「部分结果」
/// （Requirement 3.5「不改变文档文本」/ 不产生部分应用文本）。
test "apply_changes returns Err without partial result when a later change is out of bounds" {
  let changes = [
    sync_change(0, 1, "H"), // 合法：会把 "hello" → "Hello"
    sync_change(0, 99, "X"), // 越界：列号越过行尾
  ]
  match apply_changes("hello", changes, Utf16) {
    Err(e) => assert_eq(e.code, @lsp_binding.invalid_params_code)
    Ok(_) => fail("expected Err; no partial result should be returned")
  }
}
