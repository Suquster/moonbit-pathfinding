// search.mbt —— 高层搜索 API `Pattern`（旗舰深化）。
//
// 对应 design.md §4.10（R8/R11）。本文件为**新增**。`Pattern` 是编译句柄，
// 封装 Pike VM 程序与匹配策略，提供 `find`/`find_all`/`captures`/`replace`/
// `replace_all`/`split` 等高层操作。
//
// 不重叠枚举（R8.1/8.2/8.8）：自 `pos=0` 反复在 `[pos, n]` 上锚定搜索，命中
// `[s,e)` 后令 `pos=e`；空匹配 `s==e` 时令 `pos=e+1`（至少前进一字符）以保证
// 终止（R8.3）。替换引用（R8.6）解析 `$0..$9`、`${name}` 与 `$$`。

///|
/// 编译后的模式句柄。
///
///   * `prog` —— Pike VM 程序；
///   * `kind` —— 匹配策略。
pub struct Pattern {
  prog : Program
  kind : MatchKind
}

///|
/// 编译模式为 `Pattern`（委托 `parse_pattern` + `compile_program`）；非法时
/// 返回含位置的 `ParseError`（R8 / R12.3）。
pub fn Pattern::compile(
  pattern : String,
  flags? : Flags = Flags::default(),
  kind? : MatchKind = LeftmostLongest,
) -> Result[Pattern, ParseError] {
  match parse_pattern(pattern, flags~) {
    Err(e) => Err(e)
    Ok(ast) => Ok({ prog: compile_program(ast, flags~), kind })
  }
}

///|
/// 是否存在匹配。
pub fn Pattern::is_match(self : Pattern, input : String) -> Bool {
  match self.prog.exec(input, kind=self.kind) {
    Some(_) => true
    None => false
  }
}

///|
/// 首个匹配的整体区间。
pub fn Pattern::find(self : Pattern, input : String) -> Match? {
  match self.prog.exec(input, kind=self.kind) {
    Some(caps) => caps.group(0)
    None => None
  }
}

///|
/// 首个匹配的捕获结果（整体区间 + 各捕获组区间，R8.4）。
pub fn Pattern::captures(self : Pattern, input : String) -> Captures? {
  self.prog.exec(input, kind=self.kind)
}

///|
/// 全部互不重叠匹配的整体区间（从左到右扫描，R8.1/8.2/8.8）。空匹配至少前进
/// 一字符以保证终止（R8.3）。
pub fn Pattern::find_all(self : Pattern, input : String) -> Array[Match] {
  let chars = input.iter().to_array()
  let n = chars.length()
  let out : Array[Match] = []
  let mut pos = 0
  while pos <= n {
    match self.prog.exec_chars(chars, n, pos, self.kind) {
      None => break
      Some(caps) =>
        match caps.group(0) {
          None => break
          Some(m) => {
            out.push(m)
            pos = if m.end > m.start { m.end } else { m.end + 1 }
          }
        }
    }
  }
  out
}

///|
/// `find_iter`：`find_all` 的别名形态（R8.1）。
pub fn Pattern::find_iter(self : Pattern, input : String) -> Array[Match] {
  self.find_all(input)
}

///|
/// 全部互不重叠匹配的捕获结果。
pub fn Pattern::captures_all(self : Pattern, input : String) -> Array[Captures] {
  let chars = input.iter().to_array()
  let n = chars.length()
  let out : Array[Captures] = []
  let mut pos = 0
  while pos <= n {
    match self.prog.exec_chars(chars, n, pos, self.kind) {
      None => break
      Some(caps) =>
        match caps.group(0) {
          None => break
          Some(m) => {
            out.push(caps)
            pos = if m.end > m.start { m.end } else { m.end + 1 }
          }
        }
    }
  }
  out
}

///|
/// 替换首个匹配（R8.5）。
pub fn Pattern::replace(
  self : Pattern,
  input : String,
  repl : String,
) -> String {
  let chars = input.iter().to_array()
  let n = chars.length()
  match self.prog.exec_chars(chars, n, 0, self.kind) {
    None => input
    Some(caps) =>
      match caps.group(0) {
        None => input
        Some(m) =>
          slice_chars(chars, 0, m.start) +
          expand_repl(repl, caps, chars) +
          slice_chars(chars, m.end, n)
      }
  }
}

///|
/// 替换全部不重叠匹配（R8.5）；替换文本可引用捕获组（R8.6）。
pub fn Pattern::replace_all(
  self : Pattern,
  input : String,
  repl : String,
) -> String {
  let chars = input.iter().to_array()
  let n = chars.length()
  // 以 TextBuilder 顺序物化输出，消除循环内字符串 `+`（Requirement 1.5）。
  let out = @infra_text.TextBuilder::new()
  let mut pos = 0
  let mut last = 0
  while pos <= n {
    match self.prog.exec_chars(chars, n, pos, self.kind) {
      None => break
      Some(caps) =>
        match caps.group(0) {
          None => break
          Some(m) => {
            out.push_str(slice_chars(chars, last, m.start))
            out.push_str(expand_repl(repl, caps, chars))
            last = m.end
            pos = if m.end > m.start { m.end } else { m.end + 1 }
          }
        }
    }
  }
  out.push_str(slice_chars(chars, last, n))
  out.build()
}

///|
/// 以全部不重叠匹配为分隔符切分输入为子串数组（R8.7）。子串与分隔符匹配子串
/// 按序交错可逐字符重建原输入（R8.9）。
pub fn Pattern::split(self : Pattern, input : String) -> Array[String] {
  let chars = input.iter().to_array()
  let n = chars.length()
  let matches = self.find_all(input)
  let out : Array[String] = []
  let mut last = 0
  for m in matches {
    out.push(slice_chars(chars, last, m.start))
    last = m.end
  }
  out.push(slice_chars(chars, last, n))
  out
}

///|
/// 取字符数组的 `[a, b)` 切片为字符串。
fn slice_chars(chars : Array[Char], a : Int, b : Int) -> String {
  // 以 TextBuilder 逐字符物化切片，消除循环内字符串 `+`（Requirement 1.5）。
  let tb = @infra_text.TextBuilder::new()
  let lo = if a < 0 { 0 } else { a }
  let hi = if b > chars.length() { chars.length() } else { b }
  for k in lo..<hi {
    tb.push_char(chars[k])
  }
  tb.build()
}

///|
/// 取第 `g` 组（按编号）的匹配子串；未设置返回空串。
fn group_text(caps : Captures, g : Int, chars : Array[Char]) -> String {
  match caps.group(g) {
    Some(m) => slice_chars(chars, m.start, m.end)
    None => ""
  }
}

///|
/// 取命名组的匹配子串；未设置 / 未知名返回空串。
fn group_text_named(
  caps : Captures,
  name : String,
  chars : Array[Char],
) -> String {
  match caps.name(name) {
    Some(m) => slice_chars(chars, m.start, m.end)
    None => ""
  }
}

///|
/// 展开替换文本中的捕获引用：`$0..$9`、`${name}`、`$$`（字面 `$`）。
fn expand_repl(repl : String, caps : Captures, chars : Array[Char]) -> String {
  let r = repl.iter().to_array()
  let len = r.length()
  // 以 TextBuilder 物化展开结果，消除循环内字符串 `+`（Requirement 1.5）。
  let out = @infra_text.TextBuilder::new()
  let mut i = 0
  while i < len {
    let c = r[i]
    if c == '$' && i + 1 < len {
      let nx = r[i + 1]
      if nx == '$' {
        out.push_char('$')
        i = i + 2
      } else if nx == '{' {
        // ${name}
        let mut j = i + 2
        let name = @infra_text.TextBuilder::new()
        while j < len && r[j] != '}' {
          name.push_char(r[j])
          j = j + 1
        }
        if j < len && r[j] == '}' {
          out.push_str(group_text_named(caps, name.build(), chars))
          i = j + 1
        } else {
          // 无闭合 '}'：'$' 当字面处理。
          out.push_char('$')
          i = i + 1
        }
      } else if nx >= '0' && nx <= '9' {
        let g = nx.to_int() - '0'.to_int()
        out.push_str(group_text(caps, g, chars))
        i = i + 2
      } else {
        out.push_char('$')
        i = i + 1
      }
    } else {
      out.push_char(c)
      i = i + 1
    }
  }
  out.build()
}
