// dsl.mbt —— 极简 key=value 配置 DSL 的静态分析器（任务 14.2）。
//
// 见 moon.pkg 顶部的文法声明。分析器对整份文档做一次扫描，产出：
//   * symbols    —— 已定义符号（每个 `key = value` 赋值的键）；
//   * references —— 值中出现的 `${key}` 引用；
//   * diagnostics—— 语法/语义诊断（缺 '='、空键、重复定义、未闭合引用、
//                   未定义引用）。
// 分析结果 `Analysis` 同时承载文档 `uri`，供「跳转定义」构造 `Location`。
//
// 该分析是**纯函数**（不依赖 IO / 全局可变状态），保证三后端（wasm-gc / js /
// native）对同一输入产生逐位一致的结果。

// ───────────────────────────── 符号模型 ───────────────────────────────

///|
/// 一个已定义符号：键名 `name`、定义所在范围 `range`（键 token 的范围）、
/// 该键被赋予的原始值文本 `value`。
pub(all) struct Symbol {
  name : String
  range : Range
  value : String
} derive(Eq)

///|
/// 一处引用：被引用键名 `name` + 引用 token（含 `${` 与 `}`）的范围 `range`。
pub(all) struct Reference {
  name : String
  range : Range
} derive(Eq)

///|
/// 一份文档的分析结果：文档 `uri` + 符号表 + 引用表 + 诊断列表。
pub(all) struct Analysis {
  uri : String
  symbols : Array[Symbol]
  references : Array[Reference]
  diagnostics : Array[Diagnostic]
} derive(Eq)

// ───────────────────────────── 字符判定辅助 ───────────────────────────

///|
/// 是否为 DSL 空白（空格 / 制表）。
fn is_ws(c : Char) -> Bool {
  c == ' ' || c == '\t'
}

///|
/// 是否为合法标识符首字符：字母或下划线。
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// 是否为合法标识符后续字符：字母 / 数字 / 下划线。
fn is_ident_part(c : Char) -> Bool {
  is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
/// 将一行文本转为字符数组（按列索引访问）。
fn line_chars(line : String) -> Array[Char] {
  let cs : Array[Char] = []
  for c in line {
    cs.push(c)
  }
  cs
}

///|
/// 构造单行范围 `[start_col, end_col)`（同一行 `li`）。
fn span(li : Int, start_col : Int, end_col : Int) -> Range {
  {
    start: { line: li, character: start_col },
    end: { line: li, character: end_col },
  }
}

// ───────────────────────────── 行拆分 ─────────────────────────────────

///|
/// 将全文按 '\n' 拆分为行（保留空行；不含换行符）。'\r' 被剔除以兼容 CRLF。
fn split_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  let mut cur = StringBuilder::new()
  for c in text {
    if c == '\n' {
      lines.push(cur.to_string())
      cur = StringBuilder::new()
    } else if c == '\r' {
      // 跳过回车（CRLF → LF 归一化）。
      continue
    } else {
      cur.write_char(c)
    }
  }
  lines.push(cur.to_string())
  lines
}

// ───────────────────────────── 引用扫描 ───────────────────────────────

///|
/// 在一行的值区间 `[value_start, end)` 内扫描 `${name}` 引用。
///
/// 返回 (引用列表, 未闭合引用诊断列表)：
///   * 合法 `${name}` → 记入引用列表（范围覆盖 `$` 到 `}`，end 排他）；
///   * `${` 后缺少 `}` 或名字非法 → 记一条未闭合/非法引用诊断（Error）。
fn scan_references(
  cs : Array[Char],
  li : Int,
  value_start : Int,
) -> (Array[Reference], Array[Diagnostic]) {
  let refs : Array[Reference] = []
  let diags : Array[Diagnostic] = []
  let n = cs.length()
  let mut i = value_start
  while i < n {
    if cs[i] == '$' && i + 1 < n && cs[i + 1] == '{' {
      let start = i
      let mut j = i + 2
      // 读取标识符名。
      let name_start = j
      while j < n && is_ident_part(cs[j]) {
        j = j + 1
      }
      let name = chars_slice(cs, name_start, j)
      if j < n && cs[j] == '}' && name.length() > 0 {
        // 合法引用：范围覆盖 `${name}`，end 排他（j 指向 '}'，故 end = j+1）。
        refs.push({ name, range: span(li, start, j + 1) })
        i = j + 1
      } else {
        // 未闭合或名字非法。
        diags.push({
          range: span(li, start, j),
          severity: Error,
          message: "未闭合或非法的引用（期望 ${name}）",
        })
        i = j
      }
    } else {
      i = i + 1
    }
  }
  (refs, diags)
}

///|
/// 取字符数组的 `[from, to)` 子串。
fn chars_slice(cs : Array[Char], from : Int, to : Int) -> String {
  let sb = StringBuilder::new()
  let mut i = from
  while i < to {
    sb.write_char(cs[i])
    i = i + 1
  }
  sb.to_string()
}

///|
/// 去除字符串两端的 DSL 空白（空格 / 制表）。
fn trim_ws(s : String) -> String {
  let cs = line_chars(s)
  let n = cs.length()
  let mut a = 0
  let mut b = n
  while a < b && is_ws(cs[a]) {
    a = a + 1
  }
  while b > a && is_ws(cs[b - 1]) {
    b = b - 1
  }
  chars_slice(cs, a, b)
}

// ───────────────────────────── 主分析入口 ─────────────────────────────

///|
/// 分析一份 DSL 文档，产出符号表、引用表与诊断列表（纯函数）。
///
/// 诊断规则：
///   * 非空、非注释行缺少 '=' → Error「缺少 '='」；
///   * '=' 左侧键为空或非合法标识符 → Error「非法的键名」；
///   * 同名键重复定义 → Warning「重复定义键」（首次定义为权威定义）；
///   * 值中 `${name}` 未闭合/非法 → Error；
///   * 值中 `${name}` 引用了未定义的键 → Warning「引用了未定义的键」。
pub fn analyze(doc : TextDocument) -> Analysis {
  let symbols : Array[Symbol] = []
  let references : Array[Reference] = []
  let diagnostics : Array[Diagnostic] = []
  let lines = split_lines(doc.text)
  let defined : Map[String, Bool] = Map([])
  // 第一遍：逐行解析定义与引用，收集除「未定义引用」之外的全部诊断。
  for li in 0..<lines.length() {
    let cs = line_chars(lines[li])
    let n = cs.length()
    // 跳过前导空白，定位首个非空白字符。
    let mut start = 0
    while start < n && is_ws(cs[start]) {
      start = start + 1
    }
    // 空行或注释行：忽略。
    if start >= n || cs[start] == '#' {
      continue
    }
    // 定位 '='。
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
      diagnostics.push({
        range: span(li, start, n),
        severity: Error,
        message: "缺少 '='：期望形如 key = value 的赋值",
      })
      continue
    }
    // 键 token：'=' 左侧去除两端空白后的区间。
    let mut key_start = start
    let mut key_end = eq
    while key_start < key_end && is_ws(cs[key_start]) {
      key_start = key_start + 1
    }
    while key_end > key_start && is_ws(cs[key_end - 1]) {
      key_end = key_end - 1
    }
    let key = chars_slice(cs, key_start, key_end)
    // 校验键名合法性（非空且为合法标识符）。
    let valid_key = key.length() > 0 &&
      ({
        let kc = line_chars(key)
        let mut ok = is_ident_start(kc[0])
        let mut idx = 1
        while idx < kc.length() {
          if !is_ident_part(kc[idx]) {
            ok = false
          }
          idx = idx + 1
        }
        ok
      })
    if !valid_key {
      diagnostics.push({
        range: span(li, start, eq),
        severity: Error,
        message: "非法的键名（须为标识符 [A-Za-z_][A-Za-z0-9_]*）",
      })
      continue
    }
    // 值 token：'=' 右侧文本，去除两端空白后作为规范化的值。
    let value = trim_ws(chars_slice(cs, eq + 1, n))
    let key_range = span(li, key_start, key_end)
    // 重复定义检测：首次定义为权威，后续重复记 Warning。
    match defined.get(key) {
      Some(_) =>
        diagnostics.push({
          range: key_range,
          severity: Warning,
          message: "重复定义键：" + key,
        })
      None => {
        defined[key] = true
        symbols.push({ name: key, range: key_range, value })
      }
    }
    // 扫描值中的引用（含未闭合/非法引用诊断）。
    let (refs, ref_diags) = scan_references(cs, li, eq + 1)
    for r in refs {
      references.push(r)
    }
    for d in ref_diags {
      diagnostics.push(d)
    }
  }
  // 第二遍：校验引用是否指向已定义的键。
  for r in references {
    match defined.get(r.name) {
      None =>
        diagnostics.push({
          range: r.range,
          severity: Warning,
          message: "引用了未定义的键：" + r.name,
        })
      Some(_) => ()
    }
  }
  { uri: doc.uri, symbols, references, diagnostics }
}

// ───────────────────────────── 位置查询辅助 ───────────────────────────

///|
/// 判断位置 `pos` 是否落在单行范围 `range` 内（`[start, end)`，end 排他）。
fn range_contains(range : Range, pos : Position) -> Bool {
  pos.line == range.start.line &&
  pos.character >= range.start.character &&
  pos.character < range.end.character
}

///|
/// 在符号表中查找其定义范围覆盖 `pos` 的符号。
fn symbol_at(analysis : Analysis, pos : Position) -> Symbol? {
  for s in analysis.symbols {
    if range_contains(s.range, pos) {
      return Some(s)
    }
  }
  None
}

///|
/// 在引用表中查找其范围覆盖 `pos` 的引用。
fn reference_at(analysis : Analysis, pos : Position) -> Reference? {
  for r in analysis.references {
    if range_contains(r.range, pos) {
      return Some(r)
    }
  }
  None
}

///|
/// 按名查找符号定义。
fn lookup_symbol(analysis : Analysis, name : String) -> Symbol? {
  for s in analysis.symbols {
    if s.name == name {
      return Some(s)
    }
  }
  None
}
