// framing.mbt —— LSP Base Protocol 的 `Content-Length` 头部帧编解码与流式读取
// 器（任务 1.1，旁路新增）。
//
// paper-to-code 来源（LSP Base Protocol / Header Part）：
//   LSP 传输约定每条消息前置一个「头部块（header part）」，随后接「正文块
//   （content part）」。头部块由若干 `Name: Value\r\n` 行组成，并以一个空行
//   `\r\n` 结束（即头部与正文之间恰为 `\r\n\r\n`）。其中 `Content-Length` 头部
//   （以字节计的正文长度）为**必需**字段。正文为 JSON-RPC 2.0 报文。
//   参见 Microsoft Language Server Protocol Specification §「Base Protocol —
//   Header Part / Content Part」与 JSON-RPC 2.0 规范。
//
// 设计原则（design.md §3.2「头部帧」）：本模块与既有 `decode_message` /
// `encode_message` **正交**——帧函数只负责「字节流 ⇄ 正文字节」的切分与拼装，
// 正文仍交既有裸 JSON 编解码处理。既有「无头部帧的裸 JSON 正文」行为不变。
//
// 三后端一致性：全部逐字节（ASCII）处理，无浮点、无平台相关 API。头部控制结构
// （`Content-Length`、`:`、空白、`\r\n`）均为 ASCII。json.mbt 的 `bytes_to_text`
// / `text_to_bytes` 为包内私有 helper，按任务约束本文件内自实现等价的 ASCII 逐
// 字节转换（命名加 `frame_` 前缀以避免同包重名）。
//
// 错误契约（Requirement 2.3 / 11.3）：缺 `Content-Length`、其值非非负整数或正文
// 长度不足时，`decode_framed` 返回 `Err(parse_error_code, ..)`，绝不 panic/abort，
// 也不产出半成品消息。`FrameReader::next` 对「数据不足」返回 `Ok(None)`（缓冲保
// 持可继续），仅对「畸形帧」（缺/非法 `Content-Length`）返回 `Err`。

// ───────────────────────────── 字节 ⇄ ASCII 文本（本文件自实现） ─────────────

///|
/// 取字节切片 `[start, end)` 为新的 `Bytes`（不修改入参，纯函数）。
fn frame_byte_slice(b : Bytes, start : Int, end : Int) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = start
  while i < end {
    arr.push(b[i])
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
/// 顺序拼接两段 `Bytes`（纯函数，返回新 `Bytes`）。
fn frame_concat_bytes(a : Bytes, b : Bytes) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < a.length() {
    arr.push(a[i])
    i = i + 1
  }
  i = 0
  while i < b.length() {
    arr.push(b[i])
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
/// 字节切片 `[start, end)` → ASCII 文本（逐字节还原为字符；与 json.mbt 的
/// `bytes_to_text` 等价，仅作用于 ASCII 头部区）。
fn frame_slice_to_text(b : Bytes, start : Int, end : Int) -> String {
  let mut s = ""
  let mut i = start
  while i < end {
    s = s + b[i].to_int().unsafe_to_char().to_string()
    i = i + 1
  }
  s
}

///|
/// ASCII 文本 → `Bytes`（逐字符写出低 8 位；与 json.mbt 的 `text_to_bytes`
/// 等价，仅作用于 ASCII 头部）。
fn frame_ascii_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

// ───────────────────────────── 头部解析辅助 ───────────────────────────

///|
/// 在缓冲中定位头部终止序列 `\r\n\r\n`，返回正文起始下标（终止序列之后）；
/// 尚未出现时返回 `None`（头部不完整）。
fn frame_find_header_end(b : Bytes) -> Int? {
  let n = b.length()
  let mut i = 0
  while i + 3 < n {
    if b[i].to_int() == 0x0D &&
      b[i + 1].to_int() == 0x0A &&
      b[i + 2].to_int() == 0x0D &&
      b[i + 3].to_int() == 0x0A {
      return Some(i + 4)
    }
    i = i + 1
  }
  None
}

///|
/// 按 `\r\n` 切分头部文本为各行（不含分隔符本身）。
fn frame_split_crlf(s : String) -> Array[String] {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let lines : Array[String] = []
  let n = chars.length()
  let mut cur = ""
  let mut i = 0
  while i < n {
    if i + 1 < n && chars[i] == '\r' && chars[i + 1] == '\n' {
      lines.push(cur)
      cur = ""
      i = i + 2
    } else {
      cur = cur + chars[i].to_string()
      i = i + 1
    }
  }
  lines.push(cur)
  lines
}

///|
/// 以首个 `:` 切分一行为 `(name, value)`；无冒号返回 `None`（非头部行）。
fn frame_split_first_colon(s : String) -> (String, String)? {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let n = chars.length()
  let mut idx = -1
  let mut i = 0
  while i < n {
    if chars[i] == ':' {
      idx = i
      break
    }
    i = i + 1
  }
  if idx < 0 {
    return None
  }
  let mut name = ""
  let mut j = 0
  while j < idx {
    name = name + chars[j].to_string()
    j = j + 1
  }
  let mut value = ""
  j = idx + 1
  while j < n {
    value = value + chars[j].to_string()
    j = j + 1
  }
  Some((name, value))
}

///|
/// ASCII 小写化（用于头部字段名大小写不敏感比较）。
fn frame_ascii_lower(s : String) -> String {
  let mut out = ""
  for c in s {
    if c >= 'A' && c <= 'Z' {
      out = out + (c.to_int() + 32).unsafe_to_char().to_string()
    } else {
      out = out + c.to_string()
    }
  }
  out
}

///|
/// 去除头尾的空格与制表符。
fn frame_trim_spaces(s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let n = chars.length()
  let mut start = 0
  while start < n && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  let mut end = n
  while end > start && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end = end - 1
  }
  let mut out = ""
  let mut i = start
  while i < end {
    out = out + chars[i].to_string()
    i = i + 1
  }
  out
}

///|
/// 解析「非负整数」：要求至少一位、且全部为十进制数字（拒绝符号与其它字符）；
/// 否则返回 `None`（对应 Requirement 2.3「值非非负整数」）。
fn frame_parse_nonneg_int(s : String) -> Int? {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  if chars.length() == 0 {
    return None
  }
  let mut v = 0
  for c in chars {
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
  }
  Some(v)
}

///|
/// `Content-Length` 头部解析结果。
priv enum ContentLen {
  ContentLenMissing
  ContentLenInvalid
  ContentLenOk(Int)
}

///|
/// 在头部文本中检索 `Content-Length`（字段名大小写不敏感），并解析其值。
fn frame_find_content_length(header : String) -> ContentLen {
  let lines = frame_split_crlf(header)
  let mut result : ContentLen = ContentLenMissing
  for line in lines {
    match frame_split_first_colon(line) {
      None => ()
      Some((name, value)) =>
        if frame_ascii_lower(frame_trim_spaces(name)) == "content-length" {
          match frame_parse_nonneg_int(frame_trim_spaces(value)) {
            Some(n) => result = ContentLenOk(n)
            None => result = ContentLenInvalid
          }
        }
    }
  }
  result
}

///|
/// 单帧扫描结果。
priv enum FrameScan {
  ScanIncomplete // 数据不足（头部未终止，或正文不足）
  ScanBad(RpcError) // 畸形帧（缺/非法 Content-Length）
  ScanFrame(Bytes, Int) // (正文字节, 总消费字节数)
}

///|
/// 在缓冲上尝试切出一帧：返回数据不足 / 畸形 / 成功（正文 + 消费长度）。纯函数，
/// 不修改入参。
fn frame_scan(b : Bytes) -> FrameScan {
  match frame_find_header_end(b) {
    None => ScanIncomplete
    Some(body_start) => {
      let header_text = frame_slice_to_text(b, 0, body_start - 4)
      match frame_find_content_length(header_text) {
        ContentLenMissing =>
          ScanBad(
            RpcError::new(
              parse_error_code, "Parse error: missing Content-Length header",
            ),
          )
        ContentLenInvalid =>
          ScanBad(
            RpcError::new(
              parse_error_code, "Parse error: Content-Length is not a non-negative integer",
            ),
          )
        ContentLenOk(len) => {
          let total = body_start + len
          if b.length() < total {
            ScanIncomplete
          } else {
            ScanFrame(frame_byte_slice(b, body_start, total), total)
          }
        }
      }
    }
  }
}

// ───────────────────────────── 公开接口 ───────────────────────────────

///|
/// 带帧编码：输出 `Content-Length: <正文字节数>\r\n\r\n` 头部后接既有
/// `encode_message` 产出的裸 JSON 正文字节（Requirement 2.1）。
pub fn encode_framed(msg : JsonRpcMessage) -> Bytes {
  let body = encode_message(msg)
  let header = "Content-Length: " + body.length().to_string() + "\r\n\r\n"
  frame_concat_bytes(frame_ascii_to_bytes(header), body)
}

///|
/// 解码单帧：按头部声明的字节数切出正文，并交既有 `decode_message` 解码
/// （Requirement 2.2）。
///
/// 失败契约（Requirement 2.3）：缺 `Content-Length`、其值非非负整数或正文长度
/// 不足时返回 `Err(parse_error_code, ..)`，且不产出半成品消息。
pub fn decode_framed(bytes : Bytes) -> Result[JsonRpcMessage, RpcError] {
  match frame_scan(bytes) {
    ScanIncomplete =>
      Err(
        RpcError::new(
          parse_error_code, "Parse error: incomplete Content-Length frame",
        ),
      )
    ScanBad(e) => Err(e)
    ScanFrame(body, _) => decode_message(body)
  }
}

///|
/// 流式帧读取器：在累积字节缓冲上**纯函数式**反复切出完整帧（无 IO、无可变全局
/// 状态）。`push` 追加字节并返回新读取器；`next` 切出下一条完整消息。
pub struct FrameReader {
  buf : Bytes
} derive(Eq, Show)

///|
/// 构造空读取器。
pub fn FrameReader::new() -> FrameReader {
  let empty : Array[Byte] = []
  { buf: Bytes::from_array(empty) }
}

///|
/// 向缓冲追加字节，返回新的读取器（原读取器不变）。
pub fn FrameReader::push(self : FrameReader, more : Bytes) -> FrameReader {
  { buf: frame_concat_bytes(self.buf, more) }
}

///|
/// 切出下一条完整消息：
///   * `Ok(Some((msg, rest)))` —— 成功切出一帧，`rest` 为消费该帧后剩余缓冲的
///     新读取器；
///   * `Ok(None)` —— 数据不足（头部未终止或正文不足），缓冲保持可继续；
///   * `Err(..)` —— 畸形帧（缺/非法 `Content-Length`）或正文非法 JSON，承载
///     标准错误码，不产出半成品消息（Requirement 2.3）。
pub fn FrameReader::next(
  self : FrameReader,
) -> Result[(JsonRpcMessage, FrameReader)?, RpcError] {
  match frame_scan(self.buf) {
    ScanIncomplete => Ok(None)
    ScanBad(e) => Err(e)
    ScanFrame(body, total) =>
      match decode_message(body) {
        Ok(msg) => {
          let rest = frame_byte_slice(self.buf, total, self.buf.length())
          Ok(Some((msg, { buf: rest })))
        }
        Err(e) => Err(e)
      }
  }
}
