// jsonrpc_frame.mbt —— JSON-RPC 成帧（Content-Length 头）与 JSON-RPC 2.0
// 结构校验（旗舰深化，任务 11.1 旁路新增；仅新增、不改既有签名）。
//
// paper-to-code 追溯（design.md §「LSP 协议鲁棒性设计」/ Requirement 10.1/10.2/10.3/10.6）：
//   * LSP 基础协议传输层使用「头部 + 空行 + 内容」帧格式：
//       Content-Length: <N><换行><换行><body>
//     头部各行以换行分隔，头部与内容之间隔一空行。LSP 规范要求头部行使用
//     `\r\n`，但为鲁棒性（不同客户端/系统行为差异）本实现**同时兼容 `\r\n`
//     与 `\n`**（即头体之间可能是 `\r\n\r\n` 或 `\n\n`，亦可混用）。
//     <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#baseProtocol>
//   * JSON-RPC 2.0：消息必须是对象且 `"jsonrpc":"2.0"`；请求含 method+id、
//     通知含 method 无 id、响应含 id 且 result/error 二者恰具其一。
//     <https://www.jsonrpc.org/specification>
//
// ⚠ Content-Length 长度度量口径（务必与真实 LSP 的「UTF-8 字节数」区分）：
//   真实 LSP 的 `Content-Length` 是 body 的 **UTF-8 字节数**。但 MoonBit `String`
//   底层为 UTF-16，且本仓库统一以「Unicode 码位（codepoint）」为字符串切割单位
//   （见 sync.mbt 的 `to_codepoints` / `rebuild`，三后端逐位一致）。为保证
//   `encode_frame` / `decode_frame` 严格对偶可往返（Requirement 10.3），本模块
//   约定 **N = body 的 Unicode 码位数（codepoint count）**：
//     * `encode_frame` 写入的 N 即 body 的码位数；
//     * `decode_frame` 在空行之后按「码位」截取 N 个码位为 body，余下为 rest。
//   由于编解码使用同一度量且按码位切割（不会切在多码元字符中间），往返严格成立。
//   若未来需严格 UTF-8 字节语义，可改为按 `body.to_bytes().length()` 计量并按字节
//   切割，但需保证 decode 据此可切分；当前以「可往返、三后端一致」为首要目标。

// ───────────────────────────── 命名常量 ─────────────────────────────────

///|
/// `Content-Length` 头部字段名（大小写不敏感匹配；不硬编码散落字面量）。
let content_length_field : String = "Content-Length"

///|
/// 头部「字段名」与「字段值」之间的分隔串。
let header_kv_separator : String = ": "

///|
/// 头部与内容之间的终结分隔串（`encode_frame` 采用规范的 `\r\n\r\n`；
/// `decode_frame` 解析时兼容 `\r\n` 与 `\n`）。
let header_terminator : String = "\r\n\r\n"

///|
/// JSON-RPC 协议版本字面量。
let jsonrpc_version : String = "2.0"

///|
/// JSON-RPC 消息对象中的字段名。
let field_jsonrpc : String = "jsonrpc"

///|
let field_method : String = "method"

///|
let field_id : String = "id"

///|
let field_result : String = "result"

///|
let field_error : String = "error"

///|
/// 关键 ASCII 码位常量（避免散落的 magic number）。
let lf_codepoint : Int = 0x0A // '\n'

///|
let cr_codepoint : Int = 0x0D // '\r'

///|
let colon_codepoint : Int = 0x3A // ':'

///|
let space_codepoint : Int = 0x20 // ' '

///|
let tab_codepoint : Int = 0x09 // '\t'

///|
let digit_zero_codepoint : Int = 0x30 // '0'

///|
let digit_nine_codepoint : Int = 0x39 // '9'

///|
let upper_a_codepoint : Int = 0x41 // 'A'

///|
let upper_z_codepoint : Int = 0x5A // 'Z'

///|
let ascii_case_gap : Int = 0x20 // 大小写字母码位差

// ───────────────────────────── 成帧错误 ─────────────────────────────────

///|
/// 成帧解析错误（Requirement 10.2）。
pub enum FrameError {
  MissingContentLength // 头部缺失 Content-Length
  InvalidContentLength(raw~ : String) // Content-Length 值非数字（携带原始文本）
  IncompleteBody(need~ : Int, got~ : Int) // 内容不足 N 个码位（携带期望/实际）
} derive(Eq, Show)

// ───────────────────────────── 成帧编码 ─────────────────────────────────

///|
/// 将消息体 `body` 编码为带 `Content-Length` 头的帧（Requirement 10.2）：
///   "Content-Length: <N>\r\n\r\n" + body
/// 其中 N 为 body 的 Unicode 码位数（见文件头度量口径说明）。头部构建经
/// `TextBuilder` 一次性物化，避免循环内字符串 `+`。
pub fn encode_frame(body : String) -> String {
  let n = to_codepoints(body).length()
  let sb = @infra_text.TextBuilder::new()
  sb.push_str(content_length_field)
  sb.push_str(header_kv_separator)
  sb.push_str(n.to_string())
  sb.push_str(header_terminator)
  sb.push_str(body)
  sb.build()
}

// ───────────────────────────── 成帧解码 ─────────────────────────────────

///|
/// 将帧字符串解码为 `(body, rest)`（Requirement 10.2）：
///   * 解析头部各行（行分隔兼容 `\r\n` 与 `\n`），定位空行之后为内容起点；
///   * 从内容起点按「码位」截取 N 个码位为 body，余下码位为 rest。
///
/// 错误：头部无 `Content-Length` → `MissingContentLength`；其值非数字 →
/// `InvalidContentLength(raw)`；内容不足 N 个码位 → `IncompleteBody(need, got)`。
pub fn decode_frame(input : String) -> Result[(String, String), FrameError] {
  let cps = to_codepoints(input)
  let (headers, body_start) = split_header_lines(cps)
  // 在头部各行中查找 Content-Length（字段名大小写不敏感）。
  let mut raw_value : String? = None
  for line in headers {
    match parse_header_line(line) {
      Some((key, value)) =>
        if ascii_case_insensitive_eq(key, content_length_field) {
          raw_value = Some(value)
        }
      None => ()
    }
  }
  match raw_value {
    None => Err(MissingContentLength)
    Some(raw) =>
      match parse_nonneg_int(raw) {
        None => Err(InvalidContentLength(raw~))
        Some(need) => {
          let available = cps.length() - body_start
          if available < need {
            Err(IncompleteBody(need~, got=available))
          } else {
            let body = rebuild(cps, body_start, body_start + need)
            let rest = rebuild(cps, body_start + need, cps.length())
            Ok((body, rest))
          }
        }
      }
  }
}

///|
/// 扫描头部行：从码位序列起始逐行读取（行以 `\n` 结束，若紧邻前一码位为 `\r`
/// 则一并剥离），遇到空行即视为头部结束，返回 (头部行文本数组, 内容起点码位下标)。
/// 若未遇到空行即耗尽输入，则无内容段（body_start 指向序列末尾）。
fn split_header_lines(cps : Array[Int]) -> (Array[String], Int) {
  let lines : Array[String] = []
  let n = cps.length()
  let mut i = 0
  while i < n {
    // 定位本行末尾（'\n' 处或序列末尾）。
    let mut j = i
    while j < n && cps[j] != lf_codepoint {
      j = j + 1
    }
    // 行内容 [i, end)，若以 '\r' 结尾则剥离之。
    let mut end = j
    if end > i && cps[end - 1] == cr_codepoint {
      end = end - 1
    }
    let line = rebuild(cps, i, end)
    if j < n {
      // 消费掉位于 j 的 '\n'。
      let next = j + 1
      if line == "" {
        // 空行 → 头部结束，内容自 next 起。
        return (lines, next)
      }
      lines.push(line)
      i = next
    } else {
      // 抵达序列末尾且无 '\n'：补入非空末行，无独立内容段。
      if line != "" {
        lines.push(line)
      }
      return (lines, n)
    }
  }
  // 输入为空。
  (lines, n)
}

///|
/// 将一行头部解析为 `(字段名, 字段值)`（在首个 ':' 处切分，两侧去除空白）；
/// 无 ':' 返回 `None`。
fn parse_header_line(line : String) -> (String, String)? {
  let cps = to_codepoints(line)
  let mut colon = -1
  let mut i = 0
  while i < cps.length() {
    if cps[i] == colon_codepoint {
      colon = i
      break
    }
    i = i + 1
  }
  if colon < 0 {
    return None
  }
  let key = trim_codepoints(cps, 0, colon)
  let value = trim_codepoints(cps, colon + 1, cps.length())
  Some((key, value))
}

///|
/// 由码位子区间 `[from, to)` 去除首尾空白（空格 / 制表符）后重建字符串。
fn trim_codepoints(cps : Array[Int], from : Int, to : Int) -> String {
  let mut a = from
  let mut b = to
  while a < b && is_ascii_space(cps[a]) {
    a = a + 1
  }
  while b > a && is_ascii_space(cps[b - 1]) {
    b = b - 1
  }
  rebuild(cps, a, b)
}

///|
/// 是否为可去除的空白码位（空格或制表符）。
fn is_ascii_space(cp : Int) -> Bool {
  cp == space_codepoint || cp == tab_codepoint
}

///|
/// 将十进制非负整数文本解析为 `Int`；空串或含非数字字符返回 `None`。
fn parse_nonneg_int(s : String) -> Int? {
  let cps = to_codepoints(s)
  if cps.length() == 0 {
    return None
  }
  let mut v = 0
  for cp in cps {
    if cp >= digit_zero_codepoint && cp <= digit_nine_codepoint {
      v = v * 10 + (cp - digit_zero_codepoint)
    } else {
      return None
    }
  }
  Some(v)
}

///|
/// ASCII 大小写不敏感的字符串相等比较（仅折叠 ASCII A–Z）。
fn ascii_case_insensitive_eq(a : String, b : String) -> Bool {
  let ca = to_codepoints(a)
  let cb = to_codepoints(b)
  if ca.length() != cb.length() {
    return false
  }
  let mut i = 0
  while i < ca.length() {
    if ascii_lower(ca[i]) != ascii_lower(cb[i]) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 将 ASCII 大写字母码位折叠为小写；其余码位原样返回。
fn ascii_lower(cp : Int) -> Int {
  if cp >= upper_a_codepoint && cp <= upper_z_codepoint {
    cp + ascii_case_gap
  } else {
    cp
  }
}

// ───────────────────────────── JSON-RPC 结构校验 ────────────────────────

///|
/// JSON-RPC 2.0 结构校验错误（Requirement 10.1/10.6）。错误码语义与
/// @lsp_binding 的标准码一一对应（parse_error / invalid_request / ...）。
pub enum JsonRpcError {
  ParseErr // 整体非对象 / 无法解析为消息
  InvalidRequest // 结构不符合请求/通知/响应任一形态
  MethodNotFound // 方法未注册（结构校验不产生，供错误码映射完整性）
  InvalidParams // 参数非法（结构校验不产生，供错误码映射完整性）
  InternalErr // 内部错误（供错误码映射完整性）
} derive(Eq, Show)

///|
/// 校验 JSON 是否符合 JSON-RPC 2.0 消息结构（Requirement 10.1/10.6）。
///
/// 校验规则（自洽且与规范一致）：
///   1. 顶层必须是对象，否则 `ParseErr`。
///   2. 必须含 `"jsonrpc":"2.0"`（字符串且等于 "2.0"），否则 `InvalidRequest`。
///   3. 按是否含 `method` 区分形态：
///      * 含 `method`：method 必须为字符串，否则 `InvalidRequest`。
///          - 同时含 `id`（且 id 为 string/number/null）→ 请求（Request），合法；
///            id 类型非法 → `InvalidRequest`。
///          - 无 `id` → 通知（Notification），合法。
///      * 不含 `method`：视为响应（Response），必须含合法 `id`，且 `result` 与
///        `error` 二者**恰具其一**；否则 `InvalidRequest`。
///
/// 注：`MethodNotFound`/`InvalidParams`/`InternalErr` 为路由/执行期语义，结构
/// 校验阶段不产出（保留于枚举以与标准错误码映射保持完整）。
pub fn validate_jsonrpc(json : @lsp_binding.Json) -> Result[Unit, JsonRpcError] {
  let fields = match json {
    @lsp_binding.JObj(fs) => fs
    _ => return Err(ParseErr)
  }
  // 规则 2：jsonrpc == "2.0"。
  match json_lookup_field(fields, field_jsonrpc) {
    Some(@lsp_binding.JStr(v)) =>
      if v != jsonrpc_version {
        return Err(InvalidRequest)
      }
    _ => return Err(InvalidRequest)
  }
  let method = json_lookup_field(fields, field_method)
  let id = json_lookup_field(fields, field_id)
  match method {
    Some(m) => {
      // 含 method：method 必须为字符串。
      match m {
        @lsp_binding.JStr(_) => ()
        _ => return Err(InvalidRequest)
      }
      // 含 id → 请求；无 id → 通知。
      match id {
        Some(idv) => if is_valid_id(idv) { Ok(()) } else { Err(InvalidRequest) }
        None => Ok(())
      }
    }
    None =>
      // 不含 method → 响应：须含合法 id 且 result/error 恰具其一。
      match id {
        None => Err(InvalidRequest)
        Some(idv) => {
          if not(is_valid_id(idv)) {
            return Err(InvalidRequest)
          }
          let has_result = has_field(fields, field_result)
          let has_error = has_field(fields, field_error)
          if has_result && not(has_error) {
            Ok(())
          } else if has_error && not(has_result) {
            Ok(())
          } else {
            Err(InvalidRequest)
          }
        }
      }
  }
}

///|
/// 在字段列表中查找指定键，返回其值（首个匹配）；不存在返回 `None`。
fn json_lookup_field(
  fields : Array[(String, @lsp_binding.Json)],
  key : String,
) -> @lsp_binding.Json? {
  for kv in fields {
    if kv.0 == key {
      return Some(kv.1)
    }
  }
  None
}

///|
/// 字段列表是否含指定键。
fn has_field(fields : Array[(String, @lsp_binding.Json)], key : String) -> Bool {
  match json_lookup_field(fields, key) {
    Some(_) => true
    None => false
  }
}

///|
/// JSON-RPC id 的合法类型：字符串 / 数值 / null。
fn is_valid_id(j : @lsp_binding.Json) -> Bool {
  match j {
    @lsp_binding.JStr(_) | @lsp_binding.JNum(_) | @lsp_binding.JNull => true
    _ => false
  }
}
