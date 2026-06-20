// references.mbt —— 在既有 `analyze` 投影之上的符号 / 引用 / 高亮能力（任务 9.1）。
//
// 设计依据（design.md §3.5「扩展语言能力」，Requirement 5.1/5.2/5.3/5.7/5.8）：
// 本文件为**旁路新增**，不改 `analyze`/`dsl.mbt`/`types.mbt` 既有行为，全部能力
// 复用既有 `Analysis` 的 `symbols`/`references` 投影：
//
//   * documentSymbol（5.1） —— 当前文档全部键定义；
//   * workspace/symbol（5.2） —— 内存多文档按查询子串匹配符号名；
//   * textDocument/references（5.3/5.8） —— 某符号的全部出现（定义 + 全部引用）；
//   * documentHighlight（5.7） —— 当前文档内与光标处符号相关的全部出现高亮。
//
// paper-to-code 追溯：LSP §「Language Features」之 documentSymbol /
// workspace/symbol / references / documentHighlight。
//
// 确定性约定（design.md §「三后端一致性」）：全部输出顺序由**源文本出现顺序**
// 决定（即 `Analysis.symbols`/`Analysis.references` 的既有顺序），不依赖任何
// 哈希遍历顺序，保证 wasm-gc / js / native 三后端逐位一致。
//
// 同包可见性：`range_contains`/`symbol_at`/`reference_at`/`lookup_symbol` 是
// `dsl.mbt` 内的私有 `fn`，但在同一 package（src/lsp_server）内可直接调用，本
// 文件据此复用而不重复实现等价逻辑。

// ───────────────────────────── 文档符号模型 ───────────────────────────

///|
/// 一个文档符号：名称 `name` + 定义范围 `range`。
///
/// 注：`Range` 仅 `derive(Eq)`（无 `Show`），故本结构同样仅 `derive(Eq)`。
pub(all) struct DocumentSymbol {
  name : String
  range : Range
} derive(Eq)

// ───────────────────────────── 子串匹配辅助 ───────────────────────────

///|
/// 朴素子串包含判定：`haystack` 是否包含 `needle`（按 Unicode 码位/字符滑窗）。
///
/// 空 `needle` 视为被任何字符串包含（与「空查询匹配全部符号」一致）。
/// MoonBit 标准库的 `String` 子串能力此处不依赖，改以字符数组滑窗自实现，
/// 保证三后端行为一致且无外部假设。
fn contains_substring(haystack : String, needle : String) -> Bool {
  let hs : Array[Char] = []
  for c in haystack {
    hs.push(c)
  }
  let ns : Array[Char] = []
  for c in needle {
    ns.push(c)
  }
  let hn = hs.length()
  let nn = ns.length()
  if nn == 0 {
    return true
  }
  if nn > hn {
    return false
  }
  let mut i = 0
  while i + nn <= hn {
    let mut j = 0
    let mut matched = true
    while j < nn {
      if hs[i + j] != ns[j] {
        matched = false
        break
      }
      j = j + 1
    }
    if matched {
      return true
    }
    i = i + 1
  }
  false
}

// ───────────────────────────── documentSymbol（5.1） ──────────────────

///|
/// 返回当前文档内全部键定义符号（Requirement 5.1）。
///
/// 直接将 `Analysis.symbols` 逐项投影为 `DocumentSymbol`，保持源文本出现顺序。
pub fn document_symbols(a : Analysis) -> Array[DocumentSymbol] {
  let result : Array[DocumentSymbol] = []
  for s in a.symbols {
    result.push({ name: s.name, range: s.range })
  }
  result
}

// ───────────────────────────── workspace/symbol（5.2） ────────────────

///|
/// 在内存多文档工作区内，按查询子串匹配符号名，返回其所属文档定位
/// （Requirement 5.2）。
///
/// 遍历顺序：先按 `docs` 给定的文档顺序，再按各文档 `symbols` 的出现顺序；
/// 凡符号名包含 `query` 子串者收集为 `Location { uri: doc.uri, range }`。
/// 空 `query` 视为匹配全部符号（子串包含空串）。
pub fn workspace_symbols(
  docs : Array[Analysis],
  query : String,
) -> Array[Location] {
  let result : Array[Location] = []
  for doc in docs {
    for s in doc.symbols {
      if contains_substring(s.name, query) {
        result.push({ uri: doc.uri, range: s.range })
      }
    }
  }
  result
}

// ───────────────────────────── references（5.3/5.8） ──────────────────

///|
/// 返回某符号 `name` 的全部出现位置（定义 + 全部引用）（Requirement 5.3/5.8）。
///
/// 顺序：若存在该名的定义，则定义在前；随后按 `references` 的源文本出现顺序
/// 追加全部同名引用。全部包装为 `Location { uri: a.uri, range }`。
///
/// 该顺序保证 Property 8（引用—定义自洽）：定义位置 ∈ `references(a, name)`，
/// 且结果中每个位置都落在该键的某次出现（定义或引用）上。
pub fn references(a : Analysis, name : String) -> Array[Location] {
  let result : Array[Location] = []
  // 定义位置（若存在）在前。
  match lookup_symbol(a, name) {
    Some(s) => result.push({ uri: a.uri, range: s.range })
    None => ()
  }
  // 按出现顺序追加全部同名引用。
  for r in a.references {
    if r.name == name {
      result.push({ uri: a.uri, range: r.range })
    }
  }
  result
}

// ───────────────────────────── documentHighlight（5.7） ───────────────

///|
/// 返回当前文档内与位置 `pos` 处符号相关的全部出现高亮范围（Requirement 5.7）。
///
/// 先判定 `pos` 落在哪个符号定义或引用上以确定目标名：优先匹配符号定义，
/// 其次匹配引用；若 `pos` 不在任何符号/引用上则返回空数组。确定目标名后，
/// 返回该名的全部出现范围（定义范围 + 全部同名引用范围），顺序为定义在前、
/// 引用按源文本出现顺序追加。
pub fn document_highlights(a : Analysis, pos : Position) -> Array[Range] {
  // 确定 pos 处的目标符号名。
  let name = match symbol_at(a, pos) {
    Some(s) => Some(s.name)
    None =>
      match reference_at(a, pos) {
        Some(r) => Some(r.name)
        None => None
      }
  }
  let result : Array[Range] = []
  match name {
    None => result
    Some(n) => {
      // 定义范围（若存在）在前。
      match lookup_symbol(a, n) {
        Some(s) => result.push(s.range)
        None => ()
      }
      // 全部同名引用范围，按出现顺序。
      for r in a.references {
        if r.name == n {
          result.push(r.range)
        }
      }
      result
    }
  }
}
