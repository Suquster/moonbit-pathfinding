// format_test.mbt —— 格式化与代码动作单元测试（任务 11.2）。
//
// 针对 format.mbt 的 `formatting` / `code_actions`，覆盖 Requirement 5.6 的
// **具体见证**：
//   * R5.6 代码动作：某条诊断（缺少 '=' / 重复定义键）产出可用的代码动作列表，
//     且动作标题与其工作区编辑（插入 " = " / 删除整行）符合预期。
//   * 附 R5.5 见证：空白规范化文本编辑（"a=1" → "a = 1"）与已规范行不产生编辑。
//
// 断言策略：
//   * `String` 派生 Show，标题 / 替换文本 / 结果文本直接用 `assert_eq` /
//     `.contains`。
//   * `CodeAction` / `WorkspaceEdit` / `TextEdit` / `Range` 仅派生 Eq（无 Show），
//     故对其内部仅以字段访问取出 String / Int 字段后 `assert_eq`，不对整体用
//     `assert_eq`。
//   * 在 `a.diagnostics` 中按 `message` 子串定位目标诊断（复用 String 的
//     `.contains`，与 format.mbt 中 `msg.contains(...)` 一致）。

// ───────────────────────── 测试辅助（本文件私有） ─────────────────────

///|
/// 在分析结果的诊断列表中，找到第一条 `message` 含 `needle` 子串的诊断。
fn find_diagnostic(a : Analysis, needle : String) -> Diagnostic? {
  for d in a.diagnostics {
    if d.message.contains(needle) {
      return Some(d)
    }
  }
  None
}

// ───────────────────────── R5.5 空白规范化文本编辑 ────────────────────

///|
/// 未规范赋值行 "a=1"（等号无空格）→ `formatting` 返回恰一条整行替换编辑，
/// 替换文本规范为 "a = 1"，范围覆盖第 0 行 `[0, 3)`（原行 3 个字符）。
test "formatting normalizes spacing around '=' into one edit" {
  let doc : TextDocument = { uri: "file:///a.conf", text: "a=1\n" }
  let edits = formatting(doc)
  @test.assert_eq(edits.length(), 1)
  let e = edits[0]
  @test.assert_eq(e.new_text, "a = 1")
  // Range 无 Show：以字段（Int，有 Show）逐项见证整行替换范围 [ (0,0), (0,3) )。
  @test.assert_eq(e.range.start.line, 0)
  @test.assert_eq(e.range.start.character, 0)
  @test.assert_eq(e.range.end.line, 0)
  @test.assert_eq(e.range.end.character, 3)
}

///|
/// 已规范行 "a = 1"（等号两侧恰一个空格）→ `formatting` 不产生任何编辑
/// （规范形式是不动点，保证幂等）。
test "formatting yields no edits for already-normalized line" {
  let doc : TextDocument = { uri: "file:///b.conf", text: "a = 1\n" }
  let edits = formatting(doc)
  @test.assert_eq(edits.length(), 0)
}

// ───────────────────────── R5.6 缺少 '=' → 插入动作 ───────────────────

///|
/// 含「缺少 '='」诊断的文档（无 '=' 的行 "novalue"）：
///   * `analyze` 产出一条「缺少 '='」诊断；
///   * `code_actions` 针对该诊断返回恰一个动作，标题 "插入 '='"；
///   * 其工作区编辑在诊断范围末尾插入 " = "（空范围插入），归入文档 a.uri。
test "code_actions provides insert '=' action for missing '=' diagnostic" {
  let doc : TextDocument = { uri: "file:///c.conf", text: "novalue\n" }
  let a = analyze(doc)
  match find_diagnostic(a, "缺少 '='") {
    Some(d) => {
      let actions = code_actions(a, d)
      @test.assert_eq(actions.length(), 1)
      @test.assert_eq(actions[0].title, "插入 '='")
      // WorkspaceEdit/TextEdit/Range 无 Show：字段访问取出 String 见证。
      let changes = actions[0].edit.changes
      @test.assert_eq(changes.length(), 1)
      @test.assert_eq(changes[0].0, "file:///c.conf")
      let edits = changes[0].1
      @test.assert_eq(edits.length(), 1)
      // 替换文本含 " = "（纯插入：空范围 [end, end)）。
      @test.assert_eq(edits[0].new_text, " = ")
      assert_true(edits[0].new_text.contains(" = "))
      // 插入点为诊断范围末尾：空范围 start == end。
      @test.assert_eq(edits[0].range.start.line, d.range.end.line)
      @test.assert_eq(edits[0].range.start.character, d.range.end.character)
      @test.assert_eq(edits[0].range.end.line, d.range.end.line)
      @test.assert_eq(edits[0].range.end.character, d.range.end.character)
    }
    None => fail("expected a '缺少 =' diagnostic from analyze")
  }
}

// ───────────────────────── R5.6 重复定义 → 删除动作 ───────────────────

///|
/// 含「重复定义键」诊断的文档（"k = 1\nk = 2\n"）：
///   * `analyze` 对第二次定义 k 产出一条 Warning「重复定义键：k」诊断；
///   * `code_actions` 针对该诊断返回恰一个动作，标题 "删除重复定义"；
///   * 其工作区编辑删除整行（范围 [ (li,0), (li+1,0) )，替换为空串）。
test "code_actions provides delete action for duplicate-definition diagnostic" {
  let doc : TextDocument = { uri: "file:///d.conf", text: "k = 1\nk = 2\n" }
  let a = analyze(doc)
  match find_diagnostic(a, "重复定义键") {
    Some(d) => {
      let li = d.range.start.line
      let actions = code_actions(a, d)
      @test.assert_eq(actions.length(), 1)
      @test.assert_eq(actions[0].title, "删除重复定义")
      let changes = actions[0].edit.changes
      @test.assert_eq(changes.length(), 1)
      @test.assert_eq(changes[0].0, "file:///d.conf")
      let edits = changes[0].1
      @test.assert_eq(edits.length(), 1)
      // 删除整行：替换为空串，范围覆盖 [ (li,0), (li+1,0) )。
      @test.assert_eq(edits[0].new_text, "")
      @test.assert_eq(edits[0].range.start.line, li)
      @test.assert_eq(edits[0].range.start.character, 0)
      @test.assert_eq(edits[0].range.end.line, li + 1)
      @test.assert_eq(edits[0].range.end.character, 0)
    }
    None => fail("expected a '重复定义键' diagnostic from analyze")
  }
}

// ───────────────────────── R5.6 其他诊断 → 空动作列表 ─────────────────

///|
/// 无匹配修复规则的诊断（非法键名）：`code_actions` 返回空列表。
/// 行 "1bad = 2" 的键以数字开头，非合法标识符 → 产出「非法的键名」诊断，
/// 该消息既不含「缺少 '='」也不含「重复定义键」，故无可用快速修复。
test "code_actions returns empty list for diagnostics without a fix" {
  let doc : TextDocument = { uri: "file:///e.conf", text: "1bad = 2\n" }
  let a = analyze(doc)
  match find_diagnostic(a, "非法的键名") {
    Some(d) => {
      let actions = code_actions(a, d)
      @test.assert_eq(actions.length(), 0)
    }
    None => fail("expected a '非法的键名' diagnostic from analyze")
  }
}
