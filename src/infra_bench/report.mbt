// report.mbt —— 基准用例 `BenchCase` / 基准报告 `BenchReport` 及其 MD+JSON 序列化。
//
// 设计依据（design.md §「方向 2 · 2.1/2.2 Benchmark_Framework / Report Schema」
// 与 Requirement 5.1 / 5.2）：
//   基准框架的「样本 → 统计量」由 `stats.mbt` 的 `compute_stats` 承担；本文件
//   承担「统计量 + 元数据 → 可审计报告」这一步，产出 **Markdown + JSON 双格式**
//   工件（Requirement 5.1），并提供 JSON 的 **往返解析**（任务 6.4 的 Property 6
//   将验证 `from_json(to_json(x))` 与原报告逐字段相等）。
//
// 关键约定（项目 steering 质量红线）：
//   * Requirement 5.2：报告记录 moon 版本 / 后端 / 机器(os/cpu) / 生成器 / 种子 /
//     规模 / 原始计时 / 统计量。
//   * Requirement 22.4：所有文本构建统一走 `@infra_text.TextBuilder`，绝不在
//     循环体内做字符串 `+` 累加拼接。
//   * Requirement 22.6：以精确结构体表示结构化数据；JSON 文本仅是「序列化产物」，
//     内部数据模型（`BenchCase` / `BenchReport` / `BenchStats`）始终是精确 struct。
//     JSON 解析时先还原为包内最小 JSON 值模型 `BJson`（精确枚举），再映射回 struct，
//     不以字符串模拟结构化数据。
//   * 数值的「序列化再解析」往返：浮点 / 整型 / 无符号 64 位整型的解析复用
//     `moonbitlang/core/strconv`（标准库，`wasm-gc` / `js` / `native` 三后端行为
//     一致；与本仓库 @logging 解析 JSON 日志数值字段的做法一致），保证
//     `parse(to_string(x)) == x` 的逐位往返无损。JSON 的**结构**解析则在包内
//     自包含实现（递归下降），不引入任何跨方向依赖。

// ───────────────────────────── 命名常量 ─────────────────────────────

///|
/// 基准报告 JSON 的 schema 标识（与既有 `latest-native.json` 形态一致并扩展统计
/// 字段；design.md §2.2）。以命名常量替代散落字面量，避免 magic string。
let benchmark_schema : String = "moonbit-pathfinding.benchmark.v1"

// ───────────────────────────── 数据模型 ─────────────────────────────

///|
/// 单个基准用例的完整记录（Requirement 5.2）。
///
/// 字段语义：
///
/// - `algorithm`：算法名称（如 `"Dijkstra"`）。
/// - `graph_size`：图的节点数。
/// - `edge_count`：图的边数。
/// - `query_count`：查询次数。
/// - `seed`：输入生成器随机种子（64 位无符号），保证可复现（Requirement 5.4）。
/// - `raw_ns`：原始计时样本（通常为纳秒，`≥10` 个 · Requirement 5.3）。
/// - `stats`：由 `raw_ns` 经 `compute_stats` 得到的汇总统计量。
///
/// 派生 `Eq` 以支持往返一致性断言，派生 `Show` 以支持调试输出。
pub(all) struct BenchCase {
  algorithm : String
  graph_size : Int
  edge_count : Int
  query_count : Int
  seed : UInt64
  raw_ns : Array[Double]
  stats : BenchStats
} derive(Eq, Show)

///|
/// 完整基准报告（Requirement 5.1 / 5.2）。
///
/// 字段语义：
///
/// - `moon_version`：MoonBit 工具链版本。
/// - `backend`：目标后端（`wasm-gc` / `js` / `native`）。
/// - `os`：操作系统标识。
/// - `cpu`：CPU 标识。
/// - `generator`：输入生成器标识（如 `"fuzz_graph(seed,n,density)"`）。
/// - `warmup_count`：测量前丢弃的预热次数（`≥3` · Requirement 5.3）。
/// - `cases`：本次报告包含的全部基准用例。
///
/// 派生 `Eq` 以支持往返一致性断言，派生 `Show` 以支持调试输出。
///
/// 注：JSON schema 中的 `generated_at`（ISO8601 UTC 时间戳）由脚本层在序列化时
/// 注入（见 `to_json_with_timestamp`），不作为本结构的字段——它是「报告的生成
/// 元信息」而非「报告的内容」，故 `from_json` 还原时不参与结构等值比较。
pub(all) struct BenchReport {
  moon_version : String
  backend : String
  os : String
  cpu : String
  generator : String
  warmup_count : Int
  cases : Array[BenchCase]
} derive(Eq, Show)

// ───────────────────────────── Markdown 序列化 ─────────────────────────

///|
/// 将报告渲染为人类可读的 Markdown 文本（Requirement 5.1）。
///
/// 输出包含两部分：
///
/// 1. 元信息列表：moon 版本 / 后端 / 操作系统 / CPU / 生成器 / 预热次数。
/// 2. 统计表：表头为「算法 / 规模 / 边数 / 查询数 / min / median / mean / p95 /
///    stddev」，**为每个用例产出恰好一行**。
///
/// 全程以 `@infra_text.TextBuilder` 追加构建，循环体内只调用 `push_*`，绝不使用
/// 字符串 `+` 累加（Requirement 22.4）。复杂度对用例数呈 O(n) 线性。
pub fn BenchReport::to_markdown(self : BenchReport) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("# Benchmark Report\n\n")
  md_push_meta(tb, "moon_version", self.moon_version)
  md_push_meta(tb, "backend", self.backend)
  md_push_meta(tb, "os", self.os)
  md_push_meta(tb, "cpu", self.cpu)
  md_push_meta(tb, "generator", self.generator)
  // warmup_count 为整型，单独追加（非循环，单次拼装合规）。
  tb.push_str("- warmup_count: ")
  tb.push_str(self.warmup_count.to_string())
  tb.push_str("\n\n")
  // 统计表表头与分隔行。
  tb.push_str(
    "| 算法 | 规模 | 边数 | 查询数 | min | median | mean | p95 | stddev |\n",
  )
  tb.push_str("| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n")
  for c in self.cases {
    tb.push_str("| ")
    tb.push_str(c.algorithm)
    md_push_cell_int(tb, c.graph_size)
    md_push_cell_int(tb, c.edge_count)
    md_push_cell_int(tb, c.query_count)
    md_push_cell_double(tb, c.stats.min)
    md_push_cell_double(tb, c.stats.median)
    md_push_cell_double(tb, c.stats.mean)
    md_push_cell_double(tb, c.stats.p95)
    md_push_cell_double(tb, c.stats.stddev)
    tb.push_str(" |\n")
  }
  tb.build()
}

///|
/// 追加一行「- key: value」元信息（单次顺序 push，非循环拼接）。
fn md_push_meta(
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

///|
/// 追加一个以「 | 」分隔的整型表格单元（前导分隔，行尾由调用方补「 |」）。
fn md_push_cell_int(tb : @infra_text.TextBuilder, v : Int) -> Unit {
  tb.push_str(" | ")
  tb.push_str(v.to_string())
}

///|
/// 追加一个以「 | 」分隔的浮点表格单元。
fn md_push_cell_double(tb : @infra_text.TextBuilder, v : Double) -> Unit {
  tb.push_str(" | ")
  tb.push_str(v.to_string())
}

// ───────────────────────────── JSON 序列化 ─────────────────────────────

///|
/// 将报告序列化为紧凑 JSON 文本（Requirement 5.1 / 5.2）。
///
/// `generated_at` 字段以空串写出；若需注入真实 ISO8601 UTC 时间戳，使用
/// `to_json_with_timestamp`。无论时间戳取值如何，`from_json` 还原出的结构都与
/// 原 `BenchReport` 逐字段相等（时间戳不参与结构等值），故本方法的输出满足
/// 往返一致（Property 6，任务 6.4）。
pub fn BenchReport::to_json(self : BenchReport) -> String {
  self.to_json_with_timestamp("")
}

///|
/// 将报告序列化为紧凑 JSON 文本，并写入给定的 `generated_at` 时间戳。
///
/// JSON 结构（键顺序确定，利于确定性输出与审计）：
/// `schema` / `generated_at` / `moon_version` / `backend` /
/// `machine{os,cpu}` / `generator` / `warmup_count` / `cases[...]`。
/// 每个 case 含 `algorithm` / `graph_size` / `edge_count` / `query_count` /
/// `seed` / `raw_ns[...]` / `stats{min,max,median,mean,p95,stddev,sample_count}`。
///
/// 全程以 `@infra_text.TextBuilder` 追加构建，循环体内只调用 `push_*`，绝不使用
/// 字符串 `+` 累加（Requirement 22.4）。
pub fn BenchReport::to_json_with_timestamp(
  self : BenchReport,
  generated_at : String,
) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_char('{')
  json_push_field_str(tb, "schema", benchmark_schema, true)
  json_push_field_str(tb, "generated_at", generated_at, false)
  json_push_field_str(tb, "moon_version", self.moon_version, false)
  json_push_field_str(tb, "backend", self.backend, false)
  // machine 嵌套对象。
  tb.push_str(",\"machine\":{")
  json_push_field_str(tb, "os", self.os, true)
  json_push_field_str(tb, "cpu", self.cpu, false)
  tb.push_char('}')
  json_push_field_str(tb, "generator", self.generator, false)
  // warmup_count（整型字段）。
  tb.push_str(",\"warmup_count\":")
  tb.push_str(self.warmup_count.to_string())
  // cases 数组。
  tb.push_str(",\"cases\":[")
  let mut first = true
  for c in self.cases {
    if first {
      first = false
    } else {
      tb.push_char(',')
    }
    json_push_case(tb, c)
  }
  tb.push_str("]}")
  tb.build()
}

///|
/// 追加单个 `BenchCase` 的 JSON 对象。
fn json_push_case(tb : @infra_text.TextBuilder, c : BenchCase) -> Unit {
  tb.push_char('{')
  json_push_field_str(tb, "algorithm", c.algorithm, true)
  json_push_field_int(tb, "graph_size", c.graph_size)
  json_push_field_int(tb, "edge_count", c.edge_count)
  json_push_field_int(tb, "query_count", c.query_count)
  // seed 为无符号 64 位整型，以十进制字面量写出。
  tb.push_str(",\"seed\":")
  tb.push_str(c.seed.to_string())
  // raw_ns 浮点数组。
  tb.push_str(",\"raw_ns\":[")
  let mut first = true
  for x in c.raw_ns {
    if first {
      first = false
    } else {
      tb.push_char(',')
    }
    tb.push_str(x.to_string())
  }
  tb.push_char(']')
  // stats 嵌套对象。
  tb.push_str(",\"stats\":")
  json_push_stats(tb, c.stats)
  tb.push_char('}')
}

///|
/// 追加 `BenchStats` 的 JSON 对象。
fn json_push_stats(tb : @infra_text.TextBuilder, s : BenchStats) -> Unit {
  tb.push_char('{')
  json_push_field_double(tb, "min", s.min, true)
  json_push_field_double(tb, "max", s.max, false)
  json_push_field_double(tb, "median", s.median, false)
  json_push_field_double(tb, "mean", s.mean, false)
  json_push_field_double(tb, "p95", s.p95, false)
  json_push_field_double(tb, "stddev", s.stddev, false)
  json_push_field_int(tb, "sample_count", s.sample_count)
  tb.push_char('}')
}

///|
/// 追加一个字符串字段 `"key":"value"`。`leading` 为真表示是对象内首个字段
/// （不加前导逗号），否则补一个分隔逗号。
fn json_push_field_str(
  tb : @infra_text.TextBuilder,
  key : String,
  value : String,
  leading : Bool,
) -> Unit {
  if not(leading) {
    tb.push_char(',')
  }
  json_push_string(tb, key)
  tb.push_char(':')
  json_push_string(tb, value)
}

///|
/// 追加一个整型字段 `,"key":value`（始终带前导逗号，用于非首字段）。
fn json_push_field_int(
  tb : @infra_text.TextBuilder,
  key : String,
  value : Int,
) -> Unit {
  tb.push_char(',')
  json_push_string(tb, key)
  tb.push_char(':')
  tb.push_str(value.to_string())
}

///|
/// 追加一个浮点字段 `"key":value`。`leading` 控制是否补前导逗号。
fn json_push_field_double(
  tb : @infra_text.TextBuilder,
  key : String,
  value : Double,
  leading : Bool,
) -> Unit {
  if not(leading) {
    tb.push_char(',')
  }
  json_push_string(tb, key)
  tb.push_char(':')
  tb.push_str(value.to_string())
}

///|
/// 将一个带引号、按 JSON 规则转义的字符串追加到 `TextBuilder`（摊还 O(1)）。
/// 循环体内仅 `push_*`，无字符串 `+` 累加（Requirement 22.4）。
fn json_push_string(tb : @infra_text.TextBuilder, s : String) -> Unit {
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
      json_push_hex4(tb, code)
    } else {
      tb.push_char(c)
    }
  }
  tb.push_char('"')
}

///|
/// 将一个码位写为 4 位小写十六进制（\uXXXX 转义）。
fn json_push_hex4(tb : @infra_text.TextBuilder, code : Int) -> Unit {
  tb.push_char(hex_digit_char(code / 4096 % 16))
  tb.push_char(hex_digit_char(code / 256 % 16))
  tb.push_char(hex_digit_char(code / 16 % 16))
  tb.push_char(hex_digit_char(code % 16))
}

///|
/// 单个十六进制位（0..15）→ 小写字符。
fn hex_digit_char(d : Int) -> Char {
  if d < 10 {
    ('0'.to_int() + d).unsafe_to_char()
  } else {
    ('a'.to_int() + (d - 10)).unsafe_to_char()
  }
}

// ───────────────────────── 包内最小 JSON 值模型 ─────────────────────────
//
// 为「JSON 文本 → 结构化 struct」的还原提供中间表示。数值以原始字面量文本
// `JNum(String)` 保留，避免在结构解析阶段过早做数值转换；真正的数值转换在
// 字段映射阶段经 `@strconv` 完成，保证 `parse(to_string(x)) == x` 逐位往返。

///|
/// 包内最小 JSON 值模型（精确枚举，不以字符串模拟结构 · Requirement 22.6）。
/// `JObj` 以「有序键值对数组」保留键顺序，便于确定性与往返。
priv enum BJson {
  JNull
  JBool(Bool)
  JNum(String)
  JStr(String)
  JArr(Array[BJson])
  JObj(Array[(String, BJson)])
}

///|
/// 递归下降 JSON 解析游标：不可变字符序列 + 可变偏移。
priv struct BJParser {
  chars : Array[Char]
  mut pos : Int
}

///|
/// 查看当前字符（不前进）；越界返回 `None`。
fn BJParser::peek(self : BJParser) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
/// 跳过零个或多个 JSON 空白（空格 / 制表 / 换行 / 回车）。
fn BJParser::skip_ws(self : BJParser) -> Unit {
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
fn bj_is_digit(c : Char?) -> Bool {
  match c {
    Some(d) => d >= '0' && d <= '9'
    None => false
  }
}

///|
/// 解析整串为一个 JSON 值；要求恰为一个 JSON 值（尾随多余字符视为失败）。
fn bj_parse(text : String) -> BJson? {
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
fn BJParser::parse_value(self : BJParser) -> BJson? {
  self.skip_ws()
  match self.peek() {
    None => None
    Some('{') => self.parse_object()
    Some('[') => self.parse_array()
    Some('"') =>
      match self.parse_string_lit() {
        Some(s) => Some(JStr(s))
        None => None
      }
    Some('t') => self.parse_keyword("true", JBool(true))
    Some('f') => self.parse_keyword("false", JBool(false))
    Some('n') => self.parse_keyword("null", JNull)
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
fn BJParser::parse_keyword(
  self : BJParser,
  word : String,
  value : BJson,
) -> BJson? {
  for c in word {
    match self.peek() {
      Some(x) => if x == c { self.pos = self.pos + 1 } else { return None }
      None => return None
    }
  }
  Some(value)
}

///|
/// 解析 JSON 数值并保留原始字面量文本为 `JNum`。语法：可选负号、整数部分（至少
/// 一位）、可选小数部分、可选指数部分；任一部分非法返回 `None`。
fn BJParser::parse_number(self : BJParser) -> BJson? {
  let start = self.pos
  if self.peek() == Some('-') {
    self.pos = self.pos + 1
  }
  let int_start = self.pos
  while bj_is_digit(self.peek()) {
    self.pos = self.pos + 1
  }
  if self.pos == int_start {
    return None
  }
  if self.peek() == Some('.') {
    self.pos = self.pos + 1
    let frac_start = self.pos
    while bj_is_digit(self.peek()) {
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
      while bj_is_digit(self.peek()) {
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
  Some(JNum(tb.build()))
}

///|
/// 解析一个 JSON 字符串字面量（含转义）。当前字符须为开引号 `"`。未闭合 / 非法
/// 转义返回 `None`。
fn BJParser::parse_string_lit(self : BJParser) -> String? {
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
fn BJParser::parse_hex4(self : BJParser) -> Int? {
  let mut code = 0
  let mut i = 0
  while i < 4 {
    match self.peek() {
      None => return None
      Some(c) => {
        let d = bj_hex_value(c)
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
fn bj_hex_value(c : Char) -> Int {
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
fn BJParser::parse_object(self : BJParser) -> BJson? {
  self.pos = self.pos + 1
  let fields : Array[(String, BJson)] = []
  self.skip_ws()
  if self.peek() == Some('}') {
    self.pos = self.pos + 1
    return Some(JObj(fields))
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
        return Some(JObj(fields))
      }
      _ => return None
    }
  }
  None
}

///|
/// 解析 JSON 数组。当前字符须为 `[`。缺逗号或闭括号返回 `None`。
fn BJParser::parse_array(self : BJParser) -> BJson? {
  self.pos = self.pos + 1
  let items : Array[BJson] = []
  self.skip_ws()
  if self.peek() == Some(']') {
    self.pos = self.pos + 1
    return Some(JArr(items))
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
        return Some(JArr(items))
      }
      _ => return None
    }
  }
  None
}

// ───────────────────────── JSON → struct 字段映射 ───────────────────────

///|
/// 在有序键值对中按 key 查找首个匹配项；不存在返回 `None`。
fn bj_obj_get(fields : Array[(String, BJson)], key : String) -> BJson? {
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
fn bj_as_string(j : BJson) -> String? {
  match j {
    JStr(s) => Some(s)
    _ => None
  }
}

///|
/// 取整型字段（须为 `JNum` 且为十进制整数字面量）；否则返回 `None`。
fn bj_as_int(j : BJson) -> Int? {
  match j {
    JNum(s) =>
      match (try? @strconv.parse_int(s)) {
        Ok(n) => Some(n)
        Err(_) => None
      }
    _ => None
  }
}

///|
/// 取无符号 64 位整型字段（须为 `JNum`）；否则返回 `None`。
fn bj_as_uint64(j : BJson) -> UInt64? {
  match j {
    JNum(s) =>
      match (try? @strconv.parse_uint64(s)) {
        Ok(n) => Some(n)
        Err(_) => None
      }
    _ => None
  }
}

///|
/// 取浮点字段（须为 `JNum`）；否则返回 `None`。`@strconv.parse_double` 与
/// `Double::to_string` 互逆，保证逐位往返无损。
fn bj_as_double(j : BJson) -> Double? {
  match j {
    JNum(s) =>
      match (try? @strconv.parse_double(s)) {
        Ok(f) => Some(f)
        Err(_) => None
      }
    _ => None
  }
}

///|
/// 取对象字段（有序键值对）；非对象返回 `None`。
fn bj_as_obj(j : BJson) -> Array[(String, BJson)]? {
  match j {
    JObj(fields) => Some(fields)
    _ => None
  }
}

///|
/// 取数组字段；非数组返回 `None`。
fn bj_as_array(j : BJson) -> Array[BJson]? {
  match j {
    JArr(items) => Some(items)
    _ => None
  }
}

///|
/// 构造一个统一的解析失败错误（携带定位诊断）。
fn report_parse_error(detail : String) -> @graph.PathError {
  @graph.PathError::InvalidArgument("BenchReport::from_json: " + detail)
}

// ───────────────────────────── JSON 反序列化 ───────────────────────────

///|
/// 从 JSON 文本还原 `BenchReport`（Requirement 5.1，往返 Property 6）。
///
/// 行为保证：
///
/// - 结构 / 字段缺失 / 类型不符 / 数值字面量非法时返回
///   `Err(@graph.PathError::InvalidArgument(...))`，并附带定位诊断。
/// - `to_json` 产出的文本必可被本函数解析回与原报告逐字段相等的结构（`generated_at`
///   不参与结构等值）。
/// - 解析过程不修改任何外部状态；数值经 `@strconv` 逐位还原。
pub fn BenchReport::from_json(
  json : String,
) -> Result[BenchReport, @graph.PathError] {
  let root = match bj_parse(json) {
    Some(v) => v
    None => return Err(report_parse_error("JSON 语法非法或非单一值"))
  }
  let fields = match bj_as_obj(root) {
    Some(f) => f
    None => return Err(report_parse_error("顶层不是 JSON 对象"))
  }
  let moon_version = match bj_lookup_string(fields, "moon_version") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let backend = match bj_lookup_string(fields, "backend") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  // machine 嵌套对象提供 os / cpu。
  let machine = match bj_obj_get(fields, "machine") {
    Some(m) =>
      match bj_as_obj(m) {
        Some(mf) => mf
        None => return Err(report_parse_error("machine 不是对象"))
      }
    None => return Err(report_parse_error("缺少 machine 字段"))
  }
  let os = match bj_lookup_string(machine, "os") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let cpu = match bj_lookup_string(machine, "cpu") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let generator = match bj_lookup_string(fields, "generator") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let warmup_count = match bj_lookup_int(fields, "warmup_count") {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let cases_json = match bj_obj_get(fields, "cases") {
    Some(c) =>
      match bj_as_array(c) {
        Some(items) => items
        None => return Err(report_parse_error("cases 不是数组"))
      }
    None => return Err(report_parse_error("缺少 cases 字段"))
  }
  let cases : Array[BenchCase] = []
  for cj in cases_json {
    match parse_case(cj) {
      Ok(c) => cases.push(c)
      Err(e) => return Err(e)
    }
  }
  Ok({ moon_version, backend, os, cpu, generator, warmup_count, cases })
}

///|
/// `parse_report` —— `from_json` 的别名入口（更贴近脚本层「解析报告」语义）。
/// 返回 `Result[BenchReport, @graph.PathError]`，行为与 `from_json` 完全一致。
/// 入参 `json` 为 `to_json` 产出的报告文本；成功时还原出逐字段等值的
/// `BenchReport`（往返一致，见 Property 6）。当 JSON 结构非法、缺字段或类型
/// 不符时返回 `Err(@graph.PathError::InvalidArgument)` 并附诊断，不抛异常。
/// 该别名供门禁脚本以语义化名称调用，便于阅读。
pub fn parse_report(json : String) -> Result[BenchReport, @graph.PathError] {
  BenchReport::from_json(json)
}

///|
/// 解析单个 `BenchCase` 对象。
fn parse_case(j : BJson) -> Result[BenchCase, @graph.PathError] {
  let fields = match bj_as_obj(j) {
    Some(f) => f
    None => return Err(report_parse_error("case 不是对象"))
  }
  let algorithm = match bj_lookup_string(fields, "algorithm") {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let graph_size = match bj_lookup_int(fields, "graph_size") {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let edge_count = match bj_lookup_int(fields, "edge_count") {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let query_count = match bj_lookup_int(fields, "query_count") {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let seed = match bj_obj_get(fields, "seed") {
    Some(v) =>
      match bj_as_uint64(v) {
        Some(n) => n
        None =>
          return Err(report_parse_error("seed 不是合法的无符号整数"))
      }
    None => return Err(report_parse_error("缺少 seed 字段"))
  }
  let raw_json = match bj_obj_get(fields, "raw_ns") {
    Some(v) =>
      match bj_as_array(v) {
        Some(items) => items
        None => return Err(report_parse_error("raw_ns 不是数组"))
      }
    None => return Err(report_parse_error("缺少 raw_ns 字段"))
  }
  let raw_ns : Array[Double] = []
  for x in raw_json {
    match bj_as_double(x) {
      Some(d) => raw_ns.push(d)
      None => return Err(report_parse_error("raw_ns 含非法浮点数"))
    }
  }
  let stats = match bj_obj_get(fields, "stats") {
    Some(v) =>
      match parse_stats(v) {
        Ok(s) => s
        Err(e) => return Err(e)
      }
    None => return Err(report_parse_error("缺少 stats 字段"))
  }
  Ok({ algorithm, graph_size, edge_count, query_count, seed, raw_ns, stats })
}

///|
/// 解析 `BenchStats` 对象（同包可直接构造结构体字面量）。
fn parse_stats(j : BJson) -> Result[BenchStats, @graph.PathError] {
  let fields = match bj_as_obj(j) {
    Some(f) => f
    None => return Err(report_parse_error("stats 不是对象"))
  }
  let min = match bj_lookup_double(fields, "min") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let max = match bj_lookup_double(fields, "max") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let median = match bj_lookup_double(fields, "median") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let mean = match bj_lookup_double(fields, "mean") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let p95 = match bj_lookup_double(fields, "p95") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let stddev = match bj_lookup_double(fields, "stddev") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let sample_count = match bj_lookup_int(fields, "sample_count") {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  Ok({ min, max, median, mean, p95, stddev, sample_count })
}

///|
/// 查找并取字符串字段；缺失或类型不符返回携带定位的 `Err`。
fn bj_lookup_string(
  fields : Array[(String, BJson)],
  key : String,
) -> Result[String, @graph.PathError] {
  match bj_obj_get(fields, key) {
    Some(v) =>
      match bj_as_string(v) {
        Some(s) => Ok(s)
        None => Err(report_parse_error(key + " 不是字符串"))
      }
    None => Err(report_parse_error("缺少 " + key + " 字段"))
  }
}

///|
/// 查找并取整型字段；缺失或类型不符返回携带定位的 `Err`。
fn bj_lookup_int(
  fields : Array[(String, BJson)],
  key : String,
) -> Result[Int, @graph.PathError] {
  match bj_obj_get(fields, key) {
    Some(v) =>
      match bj_as_int(v) {
        Some(n) => Ok(n)
        None => Err(report_parse_error(key + " 不是合法整数"))
      }
    None => Err(report_parse_error("缺少 " + key + " 字段"))
  }
}

///|
/// 查找并取浮点字段；缺失或类型不符返回携带定位的 `Err`。
fn bj_lookup_double(
  fields : Array[(String, BJson)],
  key : String,
) -> Result[Double, @graph.PathError] {
  match bj_obj_get(fields, key) {
    Some(v) =>
      match bj_as_double(v) {
        Some(d) => Ok(d)
        None => Err(report_parse_error(key + " 不是合法浮点数"))
      }
    None => Err(report_parse_error("缺少 " + key + " 字段"))
  }
}
