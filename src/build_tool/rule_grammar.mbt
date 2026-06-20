// rule_grammar.mbt —— 完整规则文法解析与富规则模型（旗舰深化，旁路新增）。
//
// paper-to-code（design.md §4.1 / §「算法说明」）：
//   * 规则文法层对应 Mokhov, Mitchell, Peyton Jones《Build Systems à la Carte》
//     中「描述构建任务」的前端——本文件把 Make 风格的规则文本（目标 / 依赖 /
//     recipe / 变量 / 模式规则 % / phony / include / 注释）解析为富模型
//     `RuleSet`，并向下投影为既有 `BuildGraph`（`to_graph`）以复用冻结的
//     `parse_rules` / `schedule` / `detect_cycle` 流水线。
//
// 严格向后兼容（R13）：本文件**不改**既有 `parse_rules` 的最小文法语义，也
// **不扩容** `ParseError`。列号级诊断（R2.3）由新增旁路类型 `GrammarError`
// 承载（携带 `@parser_combinator.Pos` = 行 / 列 / 偏移），并经
// `GrammarError::to_legacy()` 投影回既有 `ParseError`（`line` 取 `pos.line`，
// 列号内嵌 `message`）。
//
// 解析构建于 `@parser_combinator` 原语（`Input` / `Pos` / `Parser` /
// `satisfy` / `many` / `many1` / `map` / `seq` / `not_followed_by` /
// `any_char`）：名字 token 由组合子解析与校验，错误位置由对全文 `Input` 的
// 字符推进求得真实 `Pos`（行 / 列 / 偏移）。变量 / 模式 / phony / include /
// 注释由确定性的行级分类驱动，三后端逐位一致（纯整型 / 字符串运算）。

// ───────────────────────────── 富规则模型 ─────────────────────────────

///|
/// 构建命令（recipe）：不透明命令文本行，保留原始文本以算动作指纹（R1.2）。
pub(all) struct Recipe {
  lines : Array[String]
} derive(Eq, Show)

///|
/// 已展开变量 / 模式后的具体规则（目标 + 依赖 + 可选 recipe）。
pub(all) struct Rule {
  target : String
  deps : Array[String]
  recipe : Recipe
} derive(Eq, Show)

///|
/// 模式规则（pattern rule），如 `%.o: %.c`；'%' 捕获词干 stem 并在实例化时
/// 回填（R1.4）。
pub(all) struct PatternRule {
  target_pattern : String
  dep_patterns : Array[String]
  recipe : Recipe
} derive(Eq, Show)

///|
/// 完整规则文法的解析结果（富模型）。
///
///   * `rules`         —— 具体规则（变量已展开），按首次出现稳定排序；
///   * `pattern_rules` —— 保留的模式规则（供具体目标匹配实例化）；
///   * `variables`     —— `name = value` 变量表；
///   * `phony`         —— phony 目标名（R1.5）。
pub(all) struct RuleSet {
  rules : Array[Rule]
  pattern_rules : Array[PatternRule]
  variables : Map[String, String]
  phony : Array[String]
} derive(Eq, Show)

///|
/// 旗舰列号级解析诊断（旁路新增，不改既有 `ParseError`）。
///
/// 携带 `@parser_combinator.Pos`（行 / 列 / 偏移）、期望描述 `expected` 与
/// 人类可读 `message`。需要既有形态的调用方经 `to_legacy()` 投影回 `ParseError`。
pub(all) struct GrammarError {
  pos : @parser_combinator.Pos
  expected : Array[String]
  message : String
} derive(Eq, Show)

///|
/// 投影回既有 `ParseError`（`line` 取 `pos.line`，列号内嵌 `message`），保后向
/// 兼容（R2.3）。**不修改** `ParseError` 结构。
pub fn GrammarError::to_legacy(self : GrammarError) -> ParseError {
  ParseError::new(
    self.message + "（列 " + self.pos.col.to_string() + "）",
    self.pos.line,
  )
}

// ───────────────────────── 组合子原语（@parser_combinator） ─────────────────────────

///|
/// 行内空白：空格 / 制表符 / 回车（不含换行）。
fn is_inline_ws(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
/// 名字 token 的合法字符：排除空白、换行、`:`、`#`、`=`（结构性分隔符），
/// 允许 `%`（模式）、`$` / `(` / `)`（变量引用）、`.` / `/` / `-` 等路径字符。
fn is_grammar_name_char(c : Char) -> Bool {
  !(c == ' ' ||
  c == '\t' ||
  c == '\r' ||
  c == '\n' ||
  c == ':' ||
  c == '#' ||
  c == '=')
}

///|
/// 名字 token 解析器：`many1(satisfy(is_grammar_name_char))`，组合子原语。
fn name_str_parser() -> @parser_combinator.Parser[String] {
  @parser_combinator.map(
    @parser_combinator.many1(
      @parser_combinator.satisfy(is_grammar_name_char, label="name character"),
    ),
    fn(cs) { chars_to_string(cs) },
  )
}

///|
/// 行内空白解析器（可空）。
fn inline_ws_parser() -> @parser_combinator.Parser[Array[Char]] {
  @parser_combinator.many(
    @parser_combinator.satisfy(is_inline_ws, label="inline whitespace"),
  )
}

///|
/// 名字序列解析器：`spaces0 (name spaces0)*` 且消费至 EOF。
///
/// 每个 name token 自带尾随空白消费，`many` 在遇到非名字字符（`:` / EOF）时
/// 停止；末尾以 `not_followed_by(any_char())` 强制 EOF，确保整串被消费（否则
/// 退回字面分词以保稳健）。
fn names_parser() -> @parser_combinator.Parser[Array[String]] {
  let name_tok = @parser_combinator.map(
    @parser_combinator.seq(name_str_parser(), inline_ws_parser()),
    fn(pair) { pair.0 },
  )
  let body = @parser_combinator.many(name_tok)
  let leading = @parser_combinator.map(
    @parser_combinator.seq(inline_ws_parser(), body),
    fn(pair) { pair.1 },
  )
  @parser_combinator.map(
    @parser_combinator.seq(
      leading,
      @parser_combinator.not_followed_by(@parser_combinator.any_char()),
    ),
    fn(pair) { pair.0 },
  )
}

///|
/// 以组合子解析名字序列；解析失败时退回字面空白分词（稳健性兜底）。
fn parse_names(s : String) -> Array[String] {
  match names_parser().parse_string(s).value() {
    Some(arr) => arr
    None => tokenize_ws(s.iter().to_array())
  }
}

// ───────────────────────────── 字符 / 位置辅助 ─────────────────────────────

///|
/// 行内首个匹配字符的下标；无则返回 -1。
fn first_index_char(line : Array[Char], target : Char) -> Int {
  for k in 0..<line.length() {
    if line[k] == target {
      return k
    }
  }
  -1
}

///|
/// 字符串是否含某字符。
fn contains_char(s : String, target : Char) -> Bool {
  for c in s.iter().to_array() {
    if c == target {
      return true
    }
  }
  false
}

///|
/// 数组（字符串）是否含某元素。
fn list_contains(arr : Array[String], x : String) -> Bool {
  for s in arr {
    if s == x {
      return true
    }
  }
  false
}

///|
/// 行首行内空白数（用于错误列定位）。
fn leading_ws_count(line : Array[Char]) -> Int {
  let mut k = 0
  while k < line.length() && is_inline_ws(line[k]) {
    k = k + 1
  }
  k
}

///|
/// 对全文 `Input` 推进 `offset` 个字符，求真实 `Pos`（行 / 列 / 偏移）。
///
/// `@parser_combinator.Pos` 不可在包外直接构造，故经 `Input::advance` 推进
/// 求得——这也确保诊断位置与组合子内部的位置语义完全一致。
fn make_pos(
  input : @parser_combinator.Input,
  offset : Int,
) -> @parser_combinator.Pos {
  let mut cur = input
  let mut i = 0
  while i < offset && !cur.is_eof() {
    cur = cur.advance()
    i = i + 1
  }
  cur.pos
}

///|
/// 变量展开：把 `s` 中的 `$(name)` 替换为变量值；未定义展开为空串（R1.3）。
/// 无匹配右括号的 `$` 按字面保留。
fn expand_vars(s : String, vars : Map[String, String]) -> String {
  let cs = s.iter().to_array()
  let n = cs.length()
  // 输出与变量名累积均经 `TextBuilder`，消除 `out = out + ...` /
  // `name = name + ...` 的 O(n²) 拼接（Requirement 1.5 / 1.6），输出不变。
  let out = @infra_text.TextBuilder::new()
  let mut i = 0
  while i < n {
    if cs[i] == '$' && i + 1 < n && cs[i + 1] == '(' {
      let mut j = i + 2
      let name = @infra_text.TextBuilder::new()
      while j < n && cs[j] != ')' {
        name.push_char(cs[j])
        j = j + 1
      }
      if j < n {
        out.push_str(vars.get(name.build()).unwrap_or(""))
        i = j + 1
      } else {
        out.push_str("$")
        i = i + 1
      }
    } else {
      out.push_char(cs[i])
      i = i + 1
    }
  }
  out.build()
}

// ───────────────────────────── 模式规则实例化（R1.4） ─────────────────────────────

///|
/// 将模式（含单个 `%`）与具体目标匹配，提取词干 stem；不匹配返回 `None`。
fn pattern_stem(pattern : String, target : String) -> String? {
  let p = pattern.iter().to_array()
  let t = target.iter().to_array()
  let pi = first_index_char(p, '%')
  if pi < 0 {
    return if pattern == target { Some("") } else { None }
  }
  let prefix = slice_chars(p, 0, pi)
  let suffix = slice_chars(p, pi + 1, p.length())
  if t.length() < prefix.length() + suffix.length() {
    return None
  }
  for k in 0..<prefix.length() {
    if t[k] != prefix[k] {
      return None
    }
  }
  for k in 0..<suffix.length() {
    if t[t.length() - suffix.length() + k] != suffix[k] {
      return None
    }
  }
  Some(
    chars_to_string(
      slice_chars(t, prefix.length(), t.length() - suffix.length()),
    ),
  )
}

///|
/// 将 `%` 回填为 stem。
fn subst_percent(s : String, stem : String) -> String {
  // 经 `TextBuilder` 物化，消除循环内 `out = out + ...` 的 O(n²) 拼接
  // （Requirement 1.5 / 1.6）；逐片段累积与原 `+` 拼接逐字符相等。
  let out = @infra_text.TextBuilder::new()
  for c in s.iter().to_array() {
    if c == '%' {
      out.push_str(stem)
    } else {
      out.push_char(c)
    }
  }
  out.build()
}

///|
/// 将 recipe 中的自动变量 `$*`（stem）回填为 stem。
fn subst_stem_var(s : String, stem : String) -> String {
  let cs = s.iter().to_array()
  let n = cs.length()
  // 经 `TextBuilder` 物化，消除循环内 `out = out + ...` 的 O(n²) 拼接
  // （Requirement 1.5 / 1.6）；逐片段累积与原 `+` 拼接逐字符相等。
  let out = @infra_text.TextBuilder::new()
  let mut i = 0
  while i < n {
    if cs[i] == '$' && i + 1 < n && cs[i + 1] == '*' {
      out.push_str(stem)
      i = i + 2
    } else {
      out.push_char(cs[i])
      i = i + 1
    }
  }
  out.build()
}

///|
/// 以词干 stem 实例化模式规则为具体规则（`%` 回填目标 / 依赖，`$*` 回填命令）。
pub fn PatternRule::instantiate(self : PatternRule, stem : String) -> Rule {
  let t = subst_percent(self.target_pattern, stem)
  let ds = self.dep_patterns.map(fn(d) { subst_percent(d, stem) })
  let rl = self.recipe.lines.map(fn(l) { subst_stem_var(l, stem) })
  { target: t, deps: ds, recipe: { lines: rl } }
}

///|
/// 为具体目标匹配首条适用模式规则并实例化（R1.4）；无匹配返回 `None`。
pub fn RuleSet::match_pattern(self : RuleSet, target : String) -> Rule? {
  for pr in self.pattern_rules {
    match pattern_stem(pr.target_pattern, target) {
      Some(stem) => return Some(pr.instantiate(stem))
      None => ()
    }
  }
  None
}

// ───────────────────────────── 查询投影 ─────────────────────────────

///|
/// 取目标的 recipe（动作指纹来源，R1.2）；无显式规则返回 `None`。
pub fn RuleSet::recipe_of(self : RuleSet, target : String) -> Recipe? {
  for r in self.rules {
    if r.target == target {
      return Some(r.recipe)
    }
  }
  None
}

///|
/// 目标是否为 phony（脏检查恒判需重建，R1.5）。
pub fn RuleSet::is_phony(self : RuleSet, target : String) -> Bool {
  list_contains(self.phony, target)
}

///|
/// 投影到既有 `BuildGraph`（节点首次出现去重 + 全部 `(dep, target)` 边）。
///
/// 与冻结的 `parse_rules` 逐字段一致：对每条具体规则先登记目标节点、再登记
/// 各依赖并追加边 `(dep, target)`（R2.4 / R2.5）。模式规则不贡献具体节点。
pub fn RuleSet::to_graph(self : RuleSet) -> BuildGraph {
  let nodes : Array[Target] = []
  let seen : Map[String, Bool] = Map([])
  let edges : Array[(Target, Target)] = []
  fn ensure(name : String) -> Unit {
    if !seen.contains(name) {
      seen[name] = true
      nodes.push(Target::new(name))
    }
  }

  for r in self.rules {
    ensure(r.target)
    let tgt = Target::new(r.target)
    for d in r.deps {
      ensure(d)
      edges.push((Target::new(d), tgt))
    }
  }
  BuildGraph::new(nodes, edges)
}

///|
/// 规范化打印（确定性排序），供解析 round-trip 与调试（R1，正确性属性 1）。
///
/// 输出顺序固定：变量（按名升序）→ `.PHONY` 行 → 模式规则 → 具体规则；每条
/// 规则后紧随其 TAB 缩进 recipe 行。由此 `parse_rules_full(print_rules(rs))`
/// 与 `rs` 等价。
pub fn print_rules(rs : RuleSet) -> String {
  // 变量 / .PHONY / 模式规则 / 具体规则的规范化打印经 `TextBuilder` 物化，
  // 消除多个循环内 `out = out + ...` 的 O(n²) 拼接（Requirement 1.5 /
  // 1.6）；逐片段 `push_str` 与原顺序 `+` 拼接逐字符相等，输出与排序不变。
  let out = @infra_text.TextBuilder::new()
  let names = rs.variables.keys().to_array()
  names.sort()
  for name in names {
    out.push_str(name)
    out.push_str(" = ")
    out.push_str(rs.variables.get(name).unwrap_or(""))
    out.push_str("\n")
  }
  if rs.phony.length() > 0 {
    out.push_str(".PHONY:")
    for p in rs.phony {
      out.push_str(" ")
      out.push_str(p)
    }
    out.push_str("\n")
  }
  for pr in rs.pattern_rules {
    out.push_str(pr.target_pattern)
    out.push_str(":")
    for d in pr.dep_patterns {
      out.push_str(" ")
      out.push_str(d)
    }
    out.push_str("\n")
    for line in pr.recipe.lines {
      out.push_str("\t")
      out.push_str(line)
      out.push_str("\n")
    }
  }
  for r in rs.rules {
    out.push_str(r.target)
    out.push_str(":")
    for d in r.deps {
      out.push_str(" ")
      out.push_str(d)
    }
    out.push_str("\n")
    for line in r.recipe.lines {
      out.push_str("\t")
      out.push_str(line)
      out.push_str("\n")
    }
  }
  out.build()
}

// ───────────────────────────── 完整文法解析 ─────────────────────────────

///|
/// 行是否为 `.PHONY:` 声明（`:` 左侧 trimmed 恰为 `.PHONY`）。
fn is_phony_line(line : Array[Char]) -> Bool {
  let colon = first_index_char(line, ':')
  if colon < 0 {
    return false
  }
  chars_to_string(trim_chars(slice_chars(line, 0, colon))) == ".PHONY"
}

///|
/// 完整规则文法解析（无 include 解析能力，遇 include 视作不可解析 →
/// `GrammarError`）。覆盖：目标 + 依赖去重登记、缩进 recipe 原文保留、
/// `name = value` 变量定义与 `$(name)` 展开、模式规则 `%` 词干回填、`.PHONY`
/// 标记、`#` 注释与空行忽略、位置诊断（R1 / R2）。
pub fn parse_rules_full(src : String) -> Result[RuleSet, GrammarError] {
  parse_rules_full_with_includes(src, fn(_path) { None })
}

///|
/// 带 include 源注入的完整解析（模型层无真实 FS，include 名 → 源文本由调用方
/// 经 `resolve` 提供，R1.6）。合并后去重与单文件一致（节点去重在 `to_graph`）。
///
/// 「先完整收集后构造」：任何语法错误返回 `Err(GrammarError)` 且不产出部分
/// 构造的 `RuleSet`。
pub fn parse_rules_full_with_includes(
  src : String,
  resolve : (String) -> String?,
) -> Result[RuleSet, GrammarError] {
  let full_input = @parser_combinator.Input::from_string(src)
  let lines = split_lines(src.iter().to_array())
  let variables : Map[String, String] = Map([])
  // ── 预扫描：收集变量定义（文件内顺序无关；跳过 recipe / 注释 / 空行）──
  for line in lines {
    if line.length() > 0 && line[0] == '\t' {
      continue
    }
    let trimmed = trim_chars(line)
    if trimmed.length() == 0 || trimmed[0] == '#' {
      continue
    }
    let colon = first_index_char(line, ':')
    let eq = first_index_char(line, '=')
    if eq >= 0 && (colon < 0 || eq < colon) {
      let name = chars_to_string(trim_chars(slice_chars(line, 0, eq)))
      let value = chars_to_string(
        trim_chars(slice_chars(line, eq + 1, line.length())),
      )
      if name != "" {
        variables[name] = value
      }
    }
  }
  // ── 主扫描：构造规则 / 模式规则 / phony / include 合并 ──
  let rules : Array[Rule] = []
  let pattern_rules : Array[PatternRule] = []
  let phony : Array[String] = []
  let mut idx = 0
  let mut offset = 0
  while idx < lines.length() {
    let line = lines[idx]
    let line_len = line.length()
    let line_start = offset
    // 游离 recipe 行（TAB 起始，无所属规则）：忽略。
    if line_len > 0 && line[0] == '\t' {
      offset = offset + line_len + 1
      idx = idx + 1
      continue
    }
    let trimmed = trim_chars(line)
    if trimmed.length() == 0 || trimmed[0] == '#' {
      offset = offset + line_len + 1
      idx = idx + 1
      continue
    }
    let colon = first_index_char(line, ':')
    let eq = first_index_char(line, '=')
    // 变量定义（已在预扫描登记），仅校验名非空。
    if eq >= 0 && (colon < 0 || eq < colon) {
      let name = chars_to_string(trim_chars(slice_chars(line, 0, eq)))
      if name == "" {
        return Err({
          pos: make_pos(full_input, line_start),
          expected: ["variable name"],
          message: "变量定义名为空",
        })
      }
      offset = offset + line_len + 1
      idx = idx + 1
      continue
    }
    // .PHONY 声明。
    if is_phony_line(line) {
      let c = first_index_char(line, ':')
      let names = parse_names(
        expand_vars(
          chars_to_string(slice_chars(line, c + 1, line_len)),
          variables,
        ),
      )
      for nm in names {
        if !list_contains(phony, nm) {
          phony.push(nm)
        }
      }
      offset = offset + line_len + 1
      idx = idx + 1
      continue
    }
    // include 指令（无 `:`，首 token 为 include）。
    let toks = tokenize_ws(trimmed)
    if colon < 0 && toks.length() >= 1 && toks[0] == "include" {
      let path = if toks.length() >= 2 { toks[1] } else { "" }
      match resolve(path) {
        Some(text) =>
          match parse_rules_full_with_includes(text, resolve) {
            Ok(sub) => {
              for r in sub.rules {
                rules.push(r)
              }
              for pr in sub.pattern_rules {
                pattern_rules.push(pr)
              }
              for p in sub.phony {
                if !list_contains(phony, p) {
                  phony.push(p)
                }
              }
              for k, v in sub.variables {
                if !variables.contains(k) {
                  variables[k] = v
                }
              }
            }
            Err(e) => return Err(e)
          }
        None =>
          return Err({
            pos: make_pos(full_input, line_start),
            expected: ["resolvable include path"],
            message: "无法解析 include '" + path + "'",
          })
      }
      offset = offset + line_len + 1
      idx = idx + 1
      continue
    }
    // 规则行：缺 `:` 即错。
    if colon < 0 {
      return Err({
        pos: make_pos(full_input, line_start + leading_ws_count(line)),
        expected: [":"],
        message: "规则缺少 ':' 依赖分隔符",
      })
    }
    let left = expand_vars(
      chars_to_string(slice_chars(line, 0, colon)),
      variables,
    )
    let right = expand_vars(
      chars_to_string(slice_chars(line, colon + 1, line_len)),
      variables,
    )
    let targets = parse_names(left)
    let deps = parse_names(right)
    if targets.length() == 0 {
      return Err({
        pos: make_pos(full_input, line_start + leading_ws_count(line)),
        expected: ["target name"],
        message: "规则目标名为空",
      })
    }
    // 收集紧随的 TAB 缩进 recipe 行（原文保留，变量展开）。
    let recipe_lines : Array[String] = []
    let mut k = idx + 1
    let mut off2 = offset + line_len + 1
    while k < lines.length() && lines[k].length() > 0 && lines[k][0] == '\t' {
      let rline = lines[k]
      let raw = chars_to_string(slice_chars(rline, 1, rline.length()))
      recipe_lines.push(expand_vars(raw, variables))
      off2 = off2 + rline.length() + 1
      k = k + 1
    }
    let recipe : Recipe = { lines: recipe_lines }
    for t in targets {
      if contains_char(t, '%') {
        pattern_rules.push({ target_pattern: t, dep_patterns: deps, recipe })
      } else {
        rules.push({ target: t, deps, recipe })
      }
    }
    idx = k
    offset = off2
  }
  Ok({ rules, pattern_rules, variables, phony })
}
