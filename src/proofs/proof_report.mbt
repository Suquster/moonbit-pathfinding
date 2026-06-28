// proof_report.mbt —— 证明报告数据模型 `ProofEntry` / `ProofReport`
// 及其 Markdown + JSON 双格式序列化、JSON 往返解析与失败聚合。
//
// 设计依据（design.md §3.3「Proof_Pipeline（证明报告管线 · R11）」与
// Requirement 11.1 / 11.2 / 11.3）：
//   * R11.1：Proof_Pipeline 生成 Markdown 与 JSON 两种格式且「逐项语义一致」的
//     Proof_Report —— 即两种格式条目数相同、字段一一对应。
//   * R11.2：每条性质列出运行结果（仅取「通过 / 失败」二值）与证据来源
//     （谓词测试用例标识 或 静态验证条目标识）。
//   * R11.3：报告记录所运行的后端（取自 wasm-gc / js / native 子集）、MoonBit
//     版本与 ISO 8601 UTC 格式的生成时间戳，以保证可审计性。
//
// 质量红线（项目 steering）：
//   * Requirement 22.4：所有文本构建统一走 `@infra_text.TextBuilder`，绝不在
//     循环体内做字符串 `+` 累加拼接。
//   * Requirement 22.6：以精确结构体 / 枚举表示结构化数据；JSON 文本仅是
//     「序列化产物」，内部数据模型（`ProofEntry` / `ProofReport`）始终是精确
//     struct。JSON 解析时先还原为包内最小 JSON 值模型 `PJson`（精确枚举），再
//     映射回 struct，不以字符串模拟结构化数据。
//   * Requirement 22.5：所有失败路径返回 `Result` / `Option`，绝不
//     `abort` / `todo!` / `panic` 占位。
//
// 往返保证（任务 13.2 的 Property 16）：`from_json(to_json(x)) == x` 逐字段相等
// （`generated_at` 作为字段保留并参与往返）。本文件字段均为 String / Bool /
// 数组，无需数值解析，故 JSON 解析在包内完全自包含，不引入跨方向依赖。

// ───────────────────────────── 命名常量 ─────────────────────────────

///|
/// 证明报告 JSON 的 schema 标识（避免散落 magic string）。
let proof_schema : String = "moonbit-pathfinding.proof.v1"

// ───────────────────────────── 数据模型 ─────────────────────────────

///|
/// 单条证明记录（Requirement 11.2）。
///
/// 字段语义：
///
/// - `algorithm`：算法名称（如 `"Dijkstra"`）。
/// - `property`：被验证的证明性质描述。
/// - `passed`：运行结果，仅取通过 / 失败二值（R11.2）。
/// - `evidence`：证据来源——谓词测试用例标识 或 静态验证条目标识（R11.2）。
///
/// 派生 `Eq` 以支持往返一致性断言，派生 `Show` 以支持调试输出。
pub(all) struct ProofEntry {
  algorithm : String
  property : String
  passed : Bool
  evidence : String
} derive(Eq, Show)

///|
/// 完整证明报告（Requirement 11.1 / 11.3）。
///
/// 字段语义：
///
/// - `backends`：本次运行的后端列表，取自 `wasm-gc` / `js` / `native` 子集（R11.3）。
/// - `moon_version`：MoonBit 工具链版本（R11.3）。
/// - `generated_at`：ISO 8601 UTC 格式的生成时间戳（R11.3），作为字段保留并参与往返。
/// - `entries`：本报告包含的全部证明记录。
///
/// 派生 `Eq` 以支持往返一致性断言，派生 `Show` 以支持调试输出。
pub(all) struct ProofReport {
  backends : Array[String]
  moon_version : String
  generated_at : String
  entries : Array[ProofEntry]
} derive(Eq, Show)

// ───────────────────────────── 失败聚合 ─────────────────────────────

///|
/// 失败聚合（Requirement 11.4）：当且仅当存在 `passed == false` 的条目时返回真。
/// 空报告（无任何条目）视为未失败，返回假。该方法供 `proof_pipeline` 门禁脚本
/// 决定退出码：任一证明条目失败即聚合为真，脚本据此以非零状态退出。
/// 线性扫描 `entries`，遇首个失败即短路返回。纯查询，不修改报告状态。
/// 复杂度 O(n)，`n` 为证明条目数；可在任意时刻安全地重复调用。
pub fn ProofReport::any_failed(self : ProofReport) -> Bool {
  for e in self.entries {
    if !(e.passed) {
      return true
    }
  }
  false
}

// ───────────────────────────── Markdown 序列化 ─────────────────────────

///|
/// 将报告渲染为人类可读的 Markdown 文本（Requirement 11.1）。
///
/// 输出包含三部分：
///
/// 1. 元信息列表：moon 版本 / 后端列表 / 生成时间戳（R11.3）。
/// 2. 条目统计表：表头为「算法 / 性质 / 结果 / 证据」，**为每条记录产出恰好一行**，
///    使其与 JSON 的 `entries` 数组「逐项语义一致」（R11.1）。
/// 3. 汇总行：是否存在失败条目（`any_failed`）。
///
/// 全程以 `@infra_text.TextBuilder` 追加构建，循环体内只调用 `push_*`，绝不使用
/// 字符串 `+` 累加（Requirement 22.4）。复杂度对条目数呈 O(n) 线性。
pub fn ProofReport::to_markdown(self : ProofReport) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("# Proof Report\n\n")
  pr_md_push_meta(tb, "moon_version", self.moon_version)
  pr_md_push_meta(tb, "generated_at", self.generated_at)
  // 后端列表以逗号分隔（单次顺序拼装，循环体内仅 push_*）。
  tb.push_str("- backends: ")
  let mut first = true
  for b in self.backends {
    if first {
      first = false
    } else {
      tb.push_str(", ")
    }
    tb.push_str(b)
  }
  tb.push_str("\n\n")
  // 条目统计表。
  tb.push_str("| 算法 | 性质 | 结果 | 证据 |\n")
  tb.push_str("| --- | --- | --- | --- |\n")
  for e in self.entries {
    tb.push_str("| ")
    tb.push_str(e.algorithm)
    tb.push_str(" | ")
    tb.push_str(e.property)
    tb.push_str(" | ")
    tb.push_str(if e.passed { "通过" } else { "失败" })
    tb.push_str(" | ")
    tb.push_str(e.evidence)
    tb.push_str(" |\n")
  }
  // 汇总行。
  tb.push_str("\n- any_failed: ")
  tb.push_str(self.any_failed().to_string())
  tb.push_char('\n')
  tb.build()
}

///|
/// 追加一行「- key: value」元信息（单次顺序 push，非循环拼接）。
fn pr_md_push_meta(
  tb : @infra_text.TextBuilder,
  key : String,
  value : String,
) -> Unit {
  tb.push_str("- ")
  tb.push_str(key)
  tb.push_str(": ")
  tb.push_str(value)
  tb.push_char('\n')
}

// ───────────────────────────── JSON 序列化 ─────────────────────────────

///|
/// 将报告序列化为紧凑 JSON 文本（Requirement 11.1 / 11.3）。
///
/// JSON 结构（键顺序确定，利于确定性输出与审计）：
/// `schema` / `backends[...]` / `moon_version` / `generated_at` / `entries[...]`。
/// 每个 entry 含 `algorithm` / `property` / `passed` / `evidence`，与 Markdown
/// 表格逐项对应（R11.1）。
///
/// 全程以 `@infra_text.TextBuilder` 追加构建，循环体内只调用 `push_*`，绝不使用
/// 字符串 `+` 累加（Requirement 22.4）。`from_json` 必可将本输出还原为逐字段
/// 相等的结构（含 `generated_at`），满足往返一致（Property 16，任务 13.2）。
pub fn ProofReport::to_json(self : ProofReport) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_char('{')
  pr_json_push_field_str(tb, "schema", proof_schema, true)
  // backends 字符串数组。
  tb.push_str(",\"backends\":[")
  let mut first_b = true
  for b in self.backends {
    if first_b {
      first_b = false
    } else {
      tb.push_char(',')
    }
    pr_json_push_string(tb, b)
  }
  tb.push_char(']')
  pr_json_push_field_str(tb, "moon_version", self.moon_version, false)
  pr_json_push_field_str(tb, "generated_at", self.generated_at, false)
  // entries 数组。
  tb.push_str(",\"entries\":[")
  let mut first_e = true
  for e in self.entries {
    if first_e {
      first_e = false
    } else {
      tb.push_char(',')
    }
    pr_json_push_entry(tb, e)
  }
  tb.push_str("]}")
  tb.build()
}

///|
/// 追加单个 `ProofEntry` 的 JSON 对象。
fn pr_json_push_entry(tb : @infra_text.TextBuilder, e : ProofEntry) -> Unit {
  tb.push_char('{')
  pr_json_push_field_str(tb, "algorithm", e.algorithm, true)
  pr_json_push_field_str(tb, "property", e.property, false)
  // passed 为布尔字段。
  tb.push_str(",\"passed\":")
  tb.push_str(if e.passed { "true" } else { "false" })
  pr_json_push_field_str(tb, "evidence", e.evidence, false)
  tb.push_char('}')
}

///|
/// 追加一个字符串字段 `"key":"value"`。`leading` 为真表示是对象内首个字段
/// （不加前导逗号），否则补一个分隔逗号。
fn pr_json_push_field_str(
  tb : @infra_text.TextBuilder,
  key : String,
  value : String,
  leading : Bool,
) -> Unit {
  if !(leading) {
    tb.push_char(',')
  }
  pr_json_push_string(tb, key)
  tb.push_char(':')
  pr_json_push_string(tb, value)
}

///|
/// 将一个带引号、按 JSON 规则转义的字符串追加到 `TextBuilder`（摊还 O(1)）。
/// 循环体内仅 `push_*`，无字符串 `+` 累加（Requirement 22.4）。
fn pr_json_push_string(tb : @infra_text.TextBuilder, s : String) -> Unit {
  tb.push_char('"')
  for c in s {
    let code = c.to_int()
    if c == '"' {
      tb.push_str("\\\"")
    } else if c == '\\' {
      tb.push_str("\\\\")
    } else if c == '\n' {
      tb.push_str("\\n")
    } else if c == '\t' {
      tb.push_str("\\t")
    } else if c == '\r' {
      tb.push_str("\\r")
    } else if code == 0x08 {
      tb.push_str("\\b")
    } else if code == 0x0C {
      tb.push_str("\\f")
    } else if code < 0x20 {
      tb.push_str("\\u")
      pr_json_push_hex4(tb, code)
    } else {
      tb.push_char(c)
    }
  }
  tb.push_char('"')
}

///|
/// 将一个码位写为 4 位小写十六进制（\uXXXX 转义）。
fn pr_json_push_hex4(tb : @infra_text.TextBuilder, code : Int) -> Unit {
  tb.push_char(pr_hex_digit_char(code / 4096 % 16))
  tb.push_char(pr_hex_digit_char(code / 256 % 16))
  tb.push_char(pr_hex_digit_char(code / 16 % 16))
  tb.push_char(pr_hex_digit_char(code % 16))
}

///|
/// 单个十六进制位（0..15）→ 小写字符。
fn pr_hex_digit_char(d : Int) -> Char {
  if d < 10 {
    ('0'.to_int() + d).unsafe_to_char()
  } else {
    ('a'.to_int() + (d - 10)).unsafe_to_char()
  }
}

// ───────────────────────── 包内最小 JSON 值模型 ─────────────────────────
//
// 为「JSON 文本 → 结构化 struct」的还原提供中间表示（精确枚举，不以字符串模拟
// 结构 · Requirement 22.6）。本文件字段为 String / Bool / 数组，无需数值转换，
// 故数值仅保留原始字面量文本 `PNum(String)` 用于完整性（容错），不参与字段映射。

///|
/// 包内最小 JSON 值模型。`PObj` 以「有序键值对数组」保留键顺序，便于确定性与往返。
///
/// `PNull` / `PNum` 由解析器在遇到 `null` / 数值字面量时构造，以保证对合法
/// JSON 输入的完整接受；本文件的字段提取器不读取这两类取值（数值仅保留文本、
/// 不做映射），故抑制 `unused_constructor`（移除会破坏解析鲁棒性）。
#warnings("-unused_constructor")
priv enum PJson {
  PNull
  PBool(Bool)
  PNum(String)
  PStr(String)
  PArr(Array[PJson])
  PObj(Array[(String, PJson)])
}

///|
/// 递归下降 JSON 解析游标：不可变字符序列 + 可变偏移。
priv struct PJParser {
  chars : Array[Char]
  mut pos : Int
}

///|
/// 查看当前字符（不前进）；越界返回 `None`。
fn PJParser::peek(self : PJParser) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
/// 跳过零个或多个 JSON 空白（空格 / 制表 / 换行 / 回车）。
fn PJParser::skip_ws(self : PJParser) -> Unit {
  let mut go = true
  while go {
    match self.peek() {
      Some(' ') | Some('\t') | Some('\n') | Some('\r') =>
        self.pos = self.pos + 1
      _ => go = false
    }
  }
}

///|
/// 当前字符是否为十进制数字。
fn pj_is_digit(c : Char?) -> Bool {
  match c {
    Some(d) => d >= '0' && d <= '9'
    None => false
  }
}

///|
/// 解析整串为一个 JSON 值；要求恰为一个 JSON 值（尾随多余字符视为失败）。
fn pj_parse(text : String) -> PJson? {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let p = { chars, pos: 0 }
  p.skip_ws()
  match p.parse_value() {
    None => None
    Some(j) => {
      p.skip_ws()
      if p.pos == p.chars.length() {
        Some(j)
      } else {
        None
      }
    }
  }
}

///|
/// 解析单个 JSON 值（对象 / 数组 / 字符串 / 数值 / true / false / null）。
fn PJParser::parse_value(self : PJParser) -> PJson? {
  self.skip_ws()
  match self.peek() {
    None => None
    Some('{') => self.parse_object()
    Some('[') => self.parse_array()
    Some('"') =>
      match self.parse_string_lit() {
        Some(s) => Some(PStr(s))
        None => None
      }
    Some('t') => self.parse_keyword("true", PBool(true))
    Some('f') => self.parse_keyword("false", PBool(false))
    Some('n') => self.parse_keyword("null", PNull)
    Some(c) =>
      if c == '-' || (c >= '0' && c <= '9') {
        self.parse_number()
      } else {
        None
      }
  }
}

///|
/// 匹配字面关键字（true / false / null）；不匹配返回 `None`。
fn PJParser::parse_keyword(
  self : PJParser,
  word : String,
  value : PJson,
) -> PJson? {
  for c in word {
    match self.peek() {
      Some(x) => if x == c { self.pos = self.pos + 1 } else { return None }
      None => return None
    }
  }
  Some(value)
}

///|
/// 解析 JSON 数值并保留原始字面量文本为 `PNum`（容错完整性，本文件不做数值映射）。
fn PJParser::parse_number(self : PJParser) -> PJson? {
  let start = self.pos
  if self.peek() == Some('-') {
    self.pos = self.pos + 1
  }
  let int_start = self.pos
  while pj_is_digit(self.peek()) {
    self.pos = self.pos + 1
  }
  if self.pos == int_start {
    return None
  }
  if self.peek() == Some('.') {
    self.pos = self.pos + 1
    let frac_start = self.pos
    while pj_is_digit(self.peek()) {
      self.pos = self.pos + 1
    }
    if self.pos == frac_start {
      return None
    }
  }
  match self.peek() {
    Some('e') | Some('E') => {
      self.pos = self.pos + 1
      match self.peek() {
        Some('+') | Some('-') => self.pos = self.pos + 1
        _ => ()
      }
      let exp_start = self.pos
      while pj_is_digit(self.peek()) {
        self.pos = self.pos + 1
      }
      if self.pos == exp_start {
        return None
      }
    }
    _ => ()
  }
  let tb = @infra_text.TextBuilder::new()
  let mut i = start
  while i < self.pos {
    tb.push_char(self.chars[i])
    i = i + 1
  }
  Some(PNum(tb.build()))
}

///|
/// 解析一个 JSON 字符串字面量（含转义）。当前字符须为开引号 `"`。未闭合 / 非法
/// 转义返回 `None`。
fn PJParser::parse_string_lit(self : PJParser) -> String? {
  if self.peek() != Some('"') {
    return None
  }
  self.pos = self.pos + 1
  let tb = @infra_text.TextBuilder::new()
  while true {
    match self.peek() {
      None => return None
      Some('"') => {
        self.pos = self.pos + 1
        return Some(tb.build())
      }
      Some('\\') => {
        self.pos = self.pos + 1
        match self.peek() {
          None => return None
          Some(e) => {
            self.pos = self.pos + 1
            match e {
              '"' => tb.push_char('"')
              '\\' => tb.push_char('\\')
              '/' => tb.push_char('/')
              'n' => tb.push_char('\n')
              't' => tb.push_char('\t')
              'r' => tb.push_char('\r')
              'b' => tb.push_char((0x08).unsafe_to_char())
              'f' => tb.push_char((0x0C).unsafe_to_char())
              'u' =>
                match self.parse_hex4() {
                  Some(code) => tb.push_char(code.unsafe_to_char())
                  None => return None
                }
              _ => return None
            }
          }
        }
      }
      Some(c) => {
        self.pos = self.pos + 1
        tb.push_char(c)
      }
    }
  }
  None
}

///|
/// 解析 4 位十六进制（\uXXXX 的码位）；非法返回 `None`。
fn PJParser::parse_hex4(self : PJParser) -> Int? {
  let mut code = 0
  let mut i = 0
  while i < 4 {
    match self.peek() {
      None => return None
      Some(c) => {
        let d = pj_hex_value(c)
        if d < 0 {
          return None
        }
        code = code * 16 + d
        self.pos = self.pos + 1
        i = i + 1
      }
    }
  }
  Some(code)
}

///|
/// 单个十六进制字符的数值（0..15）；非十六进制返回 -1。
fn pj_hex_value(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
/// 解析 JSON 对象。当前字符须为 `{`。键非字符串 / 缺冒号 / 缺逗号或闭括号均返回
/// `None`。保留键的出现顺序。
fn PJParser::parse_object(self : PJParser) -> PJson? {
  self.pos = self.pos + 1
  let fields : Array[(String, PJson)] = []
  self.skip_ws()
  if self.peek() == Some('}') {
    self.pos = self.pos + 1
    return Some(PObj(fields))
  }
  while true {
    self.skip_ws()
    let key = match self.parse_string_lit() {
      Some(k) => k
      None => return None
    }
    self.skip_ws()
    if self.peek() != Some(':') {
      return None
    }
    self.pos = self.pos + 1
    let value = match self.parse_value() {
      Some(v) => v
      None => return None
    }
    fields.push((key, value))
    self.skip_ws()
    match self.peek() {
      Some(',') => self.pos = self.pos + 1
      Some('}') => {
        self.pos = self.pos + 1
        return Some(PObj(fields))
      }
      _ => return None
    }
  }
  None
}

///|
/// 解析 JSON 数组。当前字符须为 `[`。缺逗号或闭括号返回 `None`。
fn PJParser::parse_array(self : PJParser) -> PJson? {
  self.pos = self.pos + 1
  let items : Array[PJson] = []
  self.skip_ws()
  if self.peek() == Some(']') {
    self.pos = self.pos + 1
    return Some(PArr(items))
  }
  while true {
    let value = match self.parse_value() {
      Some(v) => v
      None => return None
    }
    items.push(value)
    self.skip_ws()
    match self.peek() {
      Some(',') => self.pos = self.pos + 1
      Some(']') => {
        self.pos = self.pos + 1
        return Some(PArr(items))
      }
      _ => return None
    }
  }
  None
}

// ───────────────────────── JSON → struct 字段映射 ───────────────────────

///|
/// 在有序键值对中按 key 查找首个匹配项；不存在返回 `None`。
fn pj_obj_get(fields : Array[(String, PJson)], key : String) -> PJson? {
  for kv in fields {
    let (k, v) = kv
    if k == key {
      return Some(v)
    }
  }
  None
}

///|
/// 取字符串字段；非字符串返回 `None`。
fn pj_as_string(j : PJson) -> String? {
  match j {
    PStr(s) => Some(s)
    _ => None
  }
}

///|
/// 取布尔字段；非布尔返回 `None`。
fn pj_as_bool(j : PJson) -> Bool? {
  match j {
    PBool(b) => Some(b)
    _ => None
  }
}

///|
/// 取对象字段（有序键值对）；非对象返回 `None`。
fn pj_as_obj(j : PJson) -> Array[(String, PJson)]? {
  match j {
    PObj(fields) => Some(fields)
    _ => None
  }
}

///|
/// 取数组字段；非数组返回 `None`。
fn pj_as_array(j : PJson) -> Array[PJson]? {
  match j {
    PArr(items) => Some(items)
    _ => None
  }
}

// ───────────────────────────── JSON 反序列化 ───────────────────────────

///|
/// 从 JSON 文本还原 `ProofReport`（Requirement 11.1，往返 Property 16）。
///
/// 行为保证：
///
/// - 结构 / 字段缺失 / 类型不符时返回携带定位诊断的 `Err(String)`，绝不 panic。
/// - `to_json` 产出的文本必可被本函数解析回与原报告逐字段相等的结构（含
///   `generated_at`），满足往返一致。
/// - 解析过程不修改任何外部状态。
pub fn ProofReport::from_json(json : String) -> Result[ProofReport, String] {
  let root = match pj_parse(json) {
    Some(v) => v
    None =>
      return Err("ProofReport::from_json: JSON 语法非法或非单一值")
  }
  let fields = match pj_as_obj(root) {
    Some(f) => f
    None => return Err("ProofReport::from_json: 顶层不是 JSON 对象")
  }
  // backends 字符串数组。
  let backends_json = match pj_obj_get(fields, "backends") {
    Some(b) =>
      match pj_as_array(b) {
        Some(items) => items
        None => return Err("ProofReport::from_json: backends 不是数组")
      }
    None => return Err("ProofReport::from_json: 缺少 backends 字段")
  }
  let backends : Array[String] = []
  for b in backends_json {
    match pj_as_string(b) {
      Some(s) => backends.push(s)
      None =>
        return Err("ProofReport::from_json: backends 含非字符串元素")
    }
  }
  let moon_version = match pj_lookup_string(fields, "moon_version") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let generated_at = match pj_lookup_string(fields, "generated_at") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  // entries 数组。
  let entries_json = match pj_obj_get(fields, "entries") {
    Some(c) =>
      match pj_as_array(c) {
        Some(items) => items
        None => return Err("ProofReport::from_json: entries 不是数组")
      }
    None => return Err("ProofReport::from_json: 缺少 entries 字段")
  }
  let entries : Array[ProofEntry] = []
  for ej in entries_json {
    match pj_parse_entry(ej) {
      Ok(e) => entries.push(e)
      Err(e) => return Err(e)
    }
  }
  Ok({ backends, moon_version, generated_at, entries })
}

///|
/// `parse_proof_report` —— `from_json` 的 `Option` 版入口（解析失败返回 `None`）。
/// 便于调用方以 `Option` 语义处理；行为与 `from_json` 的成功 / 失败判定一致。
/// 入参 `json` 为 `ProofReport::to_json` 产出的报告文本；成功时还原出逐字段
/// 等值的报告（往返一致，见 Property 16），失败时返回 `None` 而非抛异常。
/// 适用于不关心具体错误原因、只需「成功/失败」二分的调用场景。
pub fn parse_proof_report(json : String) -> ProofReport? {
  match ProofReport::from_json(json) {
    Ok(r) => Some(r)
    Err(_) => None
  }
}

///|
/// 解析单个 `ProofEntry` 对象。
fn pj_parse_entry(j : PJson) -> Result[ProofEntry, String] {
  let fields = match pj_as_obj(j) {
    Some(f) => f
    None => return Err("ProofReport::from_json: entry 不是对象")
  }
  let algorithm = match pj_lookup_string(fields, "algorithm") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let property = match pj_lookup_string(fields, "property") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let passed = match pj_obj_get(fields, "passed") {
    Some(v) =>
      match pj_as_bool(v) {
        Some(b) => b
        None => return Err("ProofReport::from_json: passed 不是布尔值")
      }
    None => return Err("ProofReport::from_json: 缺少 passed 字段")
  }
  let evidence = match pj_lookup_string(fields, "evidence") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  Ok({ algorithm, property, passed, evidence })
}

///|
/// 查找并取字符串字段；缺失或类型不符返回携带定位的 `Err`。
fn pj_lookup_string(
  fields : Array[(String, PJson)],
  key : String,
) -> Result[String, String] {
  match pj_obj_get(fields, key) {
    Some(v) =>
      match pj_as_string(v) {
        Some(s) => Ok(s)
        None => Err("ProofReport::from_json: " + key + " 不是字符串")
      }
    None => Err("ProofReport::from_json: 缺少 " + key + " 字段")
  }
}
