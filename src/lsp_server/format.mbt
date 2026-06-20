// format.mbt —— 格式化（formatting）与代码动作（codeAction）（任务 11.1）。
//
// 设计依据（design.md §3.5「扩展语言能力」，Requirement 5.5 / 5.6）：
// 本文件为**旁路新增**，不改 `analyze` / `dsl.mbt` / `types.mbt` / `rename.mbt`
// 既有行为，全部能力复用既有投影与同包私有 helper：
//
//   * formatting（5.5） —— 规范化 `key = value` 等号周边空白，产出文本编辑列表；
//   * code_actions（5.6） —— 针对某条诊断给出可用的快速修复动作列表。
//
// paper-to-code 追溯：LSP §「Language Features」之 `textDocument/formatting` 与
// `textDocument/codeAction`，结果分别以 `TextEdit` / `WorkspaceEdit` 表达
// （`TextEdit` / `WorkspaceEdit` 见同包 `rename.mbt`）。
//
// ── 列号 / 编码约定 ──────────────────────────────────────────────────
// 复用 `dsl.mbt` 的列号语义：以 `line_chars`（按 Unicode 码位/字符遍历）计量，
// 即**每码位 1 列**；行内单行编辑范围为 `[0, 原行字符数)`。
//
// ── 幂等性（Property 17） ────────────────────────────────────────────
// `formatting` 的规范形式是其不动点：每个赋值行被规范成 `key = value`（等号两侧
// 恰一个空格、值内部空白原样保留），对已规范文本再次 `formatting` 不再产生任何
// 改变文本的编辑。注释行 / 空行 / 非赋值行 / 非法键行一律不动。
//
// 确定性约定（design.md §「三后端一致性」）：遍历顺序由源文本行顺序决定，
// 编辑按行号升序追加，保证 wasm-gc / js / native 三后端逐位一致。

// ───────────────────────────── 键合法性 ───────────────────────────────

///|
/// 是否为合法 DSL 键名：非空且为标识符 `[A-Za-z_][A-Za-z0-9_]*`
/// （与 `dsl.mbt` 的键名校验一致，复用同包 `is_ident_start` / `is_ident_part`）。
fn is_valid_key(key : String) -> Bool {
  let kc = line_chars(key)
  if kc.length() == 0 {
    return false
  }
  if not(is_ident_start(kc[0])) {
    return false
  }
  let mut i = 1
  while i < kc.length() {
    if not(is_ident_part(kc[i])) {
      return false
    }
    i = i + 1
  }
  true
}

// ───────────────────────────── formatting（5.5） ──────────────────────

///|
/// 规范化文档中每个赋值行的等号周边空白，产出文本编辑列表
/// （Requirement 5.5）。
///
/// 逐行处理（`split_lines`）：对每个**赋值行**（含 '='、非注释、非空、键合法）
/// 解析 `key`（'=' 左侧 `trim_ws`）与 `value`（'=' 右侧 `trim_ws`），规范行为
/// `key + " = " + value`：
///   * 若规范行与原行不同 → 生成一条替换整行 `[0, 原行字符数)` 的 `TextEdit`；
///   * 若已是规范形式 → 不生成编辑（不动点，保证幂等）。
///
/// 注释行（首个非空白字符为 `#`）、空行、无 '=' 行、非法键行一律不动。
pub fn formatting(doc : TextDocument) -> Array[TextEdit] {
  let edits : Array[TextEdit] = []
  let lines = split_lines(doc.text)
  for li in 0..<lines.length() {
    let line = lines[li]
    let cs = line_chars(line)
    let n = cs.length()
    // 跳过前导空白，定位首个非空白字符。
    let mut start = 0
    while start < n && is_ws(cs[start]) {
      start = start + 1
    }
    // 空行或注释行：不动。
    if start >= n || cs[start] == '#' {
      continue
    }
    // 定位 '='。无 '=' 视为非赋值行：不动。
    let mut eq = -1
    let mut k = start
    while k < n {
      if cs[k] == '=' {
        eq = k
        break
      }
      k = k + 1
    }
    if eq < 0 {
      continue
    }
    // key = '=' 左侧 trim；非法键行不动。
    let key = trim_ws(chars_slice(cs, 0, eq))
    if not(is_valid_key(key)) {
      continue
    }
    // value = '=' 右侧 trim（内部空白原样保留，仅去首尾）。
    let value = trim_ws(chars_slice(cs, eq + 1, n))
    let normalized = key + " = " + value
    // 仅当规范行与原行不同才生成整行替换编辑。
    if normalized != line {
      edits.push({ range: span(li, 0, n), new_text: normalized })
    }
  }
  edits
}

// ───────────────────────────── 代码动作模型 ───────────────────────────

///|
/// 一个代码动作：展示标题 `title` + 其工作区编辑 `edit`。
///
/// 注：`edit : WorkspaceEdit`（同包 `rename.mbt`）含 `TextEdit` 含 `Range`，
/// 而 `Range` 仅 `derive(Eq)`（无 `Show`），故本结构同样仅 `derive(Eq)`。
pub(all) struct CodeAction {
  title : String
  edit : WorkspaceEdit
} derive(Eq)

// ───────────────────────────── code_actions（5.6） ────────────────────

///|
/// 在运行期构造插入用的等号片段 `" = "`（确定性常量）。
fn insert_eq_text() -> String {
  " = "
}

///|
/// 针对某条诊断 `d` 返回可用的快速修复动作列表（Requirement 5.6）。
///
/// 确定性、按诊断 `message` 分派：
///   * 「缺少 '='」 → 动作「插入 '='」：在该行末尾插入 `" = "`（空范围插入）；
///   * 「重复定义键」 → 动作「删除重复定义」：删除该行整行
///     （范围 `[{li,0}, {li+1,0})`，连同行尾换行）；
///   * 其余诊断暂无确定性修复 → 返回空数组。
///
/// 所有编辑归入单文档项 `(a.uri, edits)`（本方向为单工作区内存多文档）。
pub fn code_actions(a : Analysis, d : Diagnostic) -> Array[CodeAction] {
  let actions : Array[CodeAction] = []
  let msg = d.message
  if msg.contains("缺少 '='") {
    // 在诊断范围末尾插入 " = "（空范围 [end, end) 表示纯插入）。
    let edit : TextEdit = {
      range: { start: d.range.end, end: d.range.end },
      new_text: insert_eq_text(),
    }
    let ws : WorkspaceEdit = { changes: [(a.uri, [edit])] }
    actions.push({ title: "插入 '='", edit: ws })
  } else if msg.contains("重复定义键") {
    // 删除整行：范围覆盖 [{li,0}, {li+1,0})，连同行尾换行一并移除。
    let li = d.range.start.line
    let edit : TextEdit = {
      range: {
        start: { line: li, character: 0 },
        end: { line: li + 1, character: 0 },
      },
      new_text: "",
    }
    let ws : WorkspaceEdit = { changes: [(a.uri, [edit])] }
    actions.push({ title: "删除重复定义", edit: ws })
  }
  actions
}
