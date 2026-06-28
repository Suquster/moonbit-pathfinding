// trace_codec.mbt —— DST_Framework 旗舰深化：轨迹持久化与跨会话重放（旁路新增，设计 4.11）。
//
// 将 `DesResult`（含 `seed` / `trace` / `status` / `finals`）编码为**确定性、自描述、
// 纯 ASCII** 的空白分隔记号序列文本，并能无损解码（R8.1 / R8.2 / R8.3）。字符串
// （失败原因、KV 键）以「字符数 + 各字符码点」编码，故文本恒为 ASCII（十进制数字 /
// 空白 / 负号），与 `Bytes` 互转平凡且可逆。任一字段非法 / 损坏即返回携带原因与记号
// 偏移的 `Malformed`，**绝不返回部分构造的 `DesResult`**（R8.5）。

///|
/// 持久化错误（codec error）—— 携带人类可读原因 `reason` 与出错记号偏移 `pos`。
pub(all) enum CodecError {
  Malformed(reason~ : String, pos~ : Int)
} derive(Eq, Debug)

///|
/// 取出持久化错误的出错记号偏移。
pub fn CodecError::pos(self : CodecError) -> Int {
  match self {
    Malformed(pos~, ..) => pos
  }
}

// ─────────────────────────────── 序列化（编码） ────────────────────────────

///|
/// 记号写入器：以空白分隔累积记号。
priv struct TokenWriter {
  sb : StringBuilder
  mut count : Int
}

///|
fn TokenWriter::new() -> TokenWriter {
  { sb: StringBuilder::new(), count: 0 }
}

///|
/// 写入一个原始记号（自动补空白分隔）。
fn TokenWriter::raw(self : TokenWriter, tok : String) -> Unit {
  if self.count > 0 {
    self.sb.write_char(' ')
  }
  self.sb.write_string(tok)
  self.count = self.count + 1
}

///|
fn TokenWriter::int(self : TokenWriter, n : Int) -> Unit {
  self.raw("\{n}")
}

///|
fn TokenWriter::u64(self : TokenWriter, n : UInt64) -> Unit {
  self.raw("\{n}")
}

///|
fn TokenWriter::i64(self : TokenWriter, n : Int64) -> Unit {
  self.raw("\{n}")
}

///|
/// 字符串以「字符数 + 各字符码点」编码（保证文本恒为 ASCII，且任意字符可逆）。
fn TokenWriter::str(self : TokenWriter, s : String) -> Unit {
  let codes : Array[Int] = []
  for c in s {
    codes.push(c.to_int())
  }
  self.int(codes.length())
  for code in codes {
    self.int(code)
  }
}

///|
/// 编码 `NetFaultKind`：标签 + 附加参数。
fn TokenWriter::fault_kind(self : TokenWriter, k : NetFaultKind) -> Unit {
  match k {
    Crash => self.int(0)
    Delay(by~) => {
      self.int(1)
      self.u64(by)
    }
    Drop => self.int(2)
    Partition(group~, until_step~) => {
      self.int(3)
      self.int(group)
      self.int(until_step)
    }
    Reorder => self.int(4)
    Duplicate => self.int(5)
    ClockSkew(offset~) => {
      self.int(6)
      self.i64(offset)
    }
    Byzantine => self.int(7)
  }
}

///|
/// 编码单个事件：标签 + 字段。
fn TokenWriter::event(self : TokenWriter, e : SimEvent) -> Unit {
  match e {
    EvScheduled(time~, task_id~) => {
      self.int(0)
      self.u64(time)
      self.int(task_id)
    }
    EvCompleted(time~, task_id~) => {
      self.int(1)
      self.u64(time)
      self.int(task_id)
    }
    EvFaulted(time~, task_id~, kind~) => {
      self.int(2)
      self.u64(time)
      self.int(task_id)
      self.fault_kind(kind)
    }
    EvSend(time~, from~, to~, msg~) => {
      self.int(3)
      self.u64(time)
      self.int(from)
      self.int(to)
      self.int(msg.id)
      self.int(msg.payload)
    }
    EvDeliver(time~, from~, to~, msg~) => {
      self.int(4)
      self.u64(time)
      self.int(from)
      self.int(to)
      self.int(msg.id)
      self.int(msg.payload)
    }
  }
}

///|
/// 将 `DesResult` 序列化为确定性、自描述的纯 ASCII 记号文本（R8.1）。
pub fn serialize_result(r : DesResult) -> String {
  let w = TokenWriter::new()
  w.u64(r.seed)
  // status
  match r.status {
    Completed => w.int(0)
    Failed(reason~) => {
      w.int(1)
      w.str(reason)
    }
  }
  // trace
  w.int(r.trace.length())
  for e in r.trace {
    w.event(e)
  }
  // finals
  w.int(r.finals.length())
  for pair in r.finals {
    let (id, app) = pair
    w.int(id)
    w.int(app.log.length())
    for v in app.log {
      w.int(v)
    }
    w.int(app.kv.length())
    for kv in app.kv {
      let (key, value) = kv
      w.str(key)
      w.int(value)
    }
  }
  w.sb.to_string()
}

// ─────────────────────────────── 反序列化（解码） ──────────────────────────

///|
/// 记号读取器：记号数组 + 游标。
priv struct TokenReader {
  toks : Array[String]
  mut pos : Int
}

///|
/// 把文本切分为空白分隔的记号数组。
fn tokenize(s : String) -> Array[String] {
  let toks : Array[String] = []
  let mut sb = StringBuilder::new()
  let mut has = false
  for c in s {
    if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
      if has {
        toks.push(sb.to_string())
        sb = StringBuilder::new()
        has = false
      }
    } else {
      sb.write_char(c)
      has = true
    }
  }
  if has {
    toks.push(sb.to_string())
  }
  toks
}

///|
/// 读取下一个原始记号；耗尽返回 `None`。
fn TokenReader::raw(self : TokenReader) -> String? {
  if self.pos < self.toks.length() {
    let t = self.toks[self.pos]
    self.pos = self.pos + 1
    Some(t)
  } else {
    None
  }
}

///|
/// 手写十进制整数解析（支持前导负号），非法返回 `None`。避免外部依赖。
fn parse_int_token(tok : String) -> Int? {
  let chars : Array[Char] = []
  for c in tok {
    chars.push(c)
  }
  if chars.length() == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if chars[0] == '-' {
    neg = true
    i = 1
    if chars.length() == 1 {
      return None
    }
  }
  let mut v = 0
  while i < chars.length() {
    let c = chars[i]
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - '0'.to_int())
    i = i + 1
  }
  Some(if neg { -v } else { v })
}

///|
/// 手写十进制 `UInt64` 解析，非法返回 `None`。
fn parse_u64_token(tok : String) -> UInt64? {
  let chars : Array[Char] = []
  for c in tok {
    chars.push(c)
  }
  if chars.length() == 0 {
    return None
  }
  let mut v = 0UL
  for c in chars {
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10UL + (c.to_int() - '0'.to_int()).to_uint64()
  }
  Some(v)
}

///|
/// 手写十进制 `Int64` 解析（支持前导负号），非法返回 `None`。
fn parse_i64_token(tok : String) -> Int64? {
  let chars : Array[Char] = []
  for c in tok {
    chars.push(c)
  }
  if chars.length() == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if chars[0] == '-' {
    neg = true
    i = 1
    if chars.length() == 1 {
      return None
    }
  }
  let mut v = 0L
  while i < chars.length() {
    let c = chars[i]
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10L + (c.to_int() - '0'.to_int()).to_int64()
    i = i + 1
  }
  Some(if neg { -v } else { v })
}

///|
fn TokenReader::int(self : TokenReader) -> Int? {
  match self.raw() {
    Some(t) => parse_int_token(t)
    None => None
  }
}

///|
fn TokenReader::u64(self : TokenReader) -> UInt64? {
  match self.raw() {
    Some(t) => parse_u64_token(t)
    None => None
  }
}

///|
fn TokenReader::i64(self : TokenReader) -> Int64? {
  match self.raw() {
    Some(t) => parse_i64_token(t)
    None => None
  }
}

///|
/// 读取「字符数 + 码点」编码的字符串；非法返回 `None`。
fn TokenReader::str(self : TokenReader) -> String? {
  match self.int() {
    Some(n) => {
      if n < 0 {
        return None
      }
      let sb = StringBuilder::new()
      let mut i = 0
      while i < n {
        match self.int() {
          Some(code) =>
            if code < 0 {
              return None
            } else {
              sb.write_char(code.unsafe_to_char())
            }
          None => return None
        }
        i = i + 1
      }
      Some(sb.to_string())
    }
    None => None
  }
}

///|
/// 解码 `NetFaultKind`；非法返回 `None`。
fn TokenReader::fault_kind(self : TokenReader) -> NetFaultKind? {
  match self.int() {
    Some(0) => Some(NetFaultKind::Crash)
    Some(1) =>
      match self.u64() {
        Some(by) => Some(NetFaultKind::Delay(by~))
        None => None
      }
    Some(2) => Some(NetFaultKind::Drop)
    Some(3) =>
      match self.int() {
        Some(group) =>
          match self.int() {
            Some(until_step) =>
              Some(NetFaultKind::Partition(group~, until_step~))
            None => None
          }
        None => None
      }
    Some(4) => Some(NetFaultKind::Reorder)
    Some(5) => Some(NetFaultKind::Duplicate)
    Some(6) =>
      match self.i64() {
        Some(offset) => Some(NetFaultKind::ClockSkew(offset~))
        None => None
      }
    Some(7) => Some(NetFaultKind::Byzantine)
    _ => None
  }
}

///|
/// 解码单个事件；非法返回 `None`。
fn TokenReader::event(self : TokenReader) -> SimEvent? {
  match self.int() {
    Some(0) =>
      match (self.u64(), self.int()) {
        (Some(time), Some(task_id)) => Some(EvScheduled(time~, task_id~))
        _ => None
      }
    Some(1) =>
      match (self.u64(), self.int()) {
        (Some(time), Some(task_id)) => Some(EvCompleted(time~, task_id~))
        _ => None
      }
    Some(2) =>
      match (self.u64(), self.int()) {
        (Some(time), Some(task_id)) =>
          match self.fault_kind() {
            Some(kind) => Some(EvFaulted(time~, task_id~, kind~))
            None => None
          }
        _ => None
      }
    Some(3) =>
      match (self.u64(), self.int(), self.int(), self.int(), self.int()) {
        (Some(time), Some(from), Some(to), Some(id), Some(payload)) =>
          Some(EvSend(time~, from~, to~, msg={ id, payload }))
        _ => None
      }
    Some(4) =>
      match (self.u64(), self.int(), self.int(), self.int(), self.int()) {
        (Some(time), Some(from), Some(to), Some(id), Some(payload)) =>
          Some(EvDeliver(time~, from~, to~, msg={ id, payload }))
        _ => None
      }
    _ => None
  }
}

///|
/// 解析完整 `DesResult`；任一字段非法返回 `None`（游标停在出错处，供报告偏移）。
fn parse_result(r : TokenReader) -> DesResult? {
  let seed = match r.u64() {
    Some(s) => s
    None => return None
  }
  let status : SimStatus = match r.int() {
    Some(0) => Completed
    Some(1) =>
      match r.str() {
        Some(reason) => Failed(reason~)
        None => return None
      }
    _ => return None
  }
  let trace_len = match r.int() {
    Some(n) => if n < 0 { return None } else { n }
    None => return None
  }
  let trace : Array[SimEvent] = []
  let mut i = 0
  while i < trace_len {
    match r.event() {
      Some(e) => trace.push(e)
      None => return None
    }
    i = i + 1
  }
  let finals_len = match r.int() {
    Some(n) => if n < 0 { return None } else { n }
    None => return None
  }
  let finals : Array[(Int, NodeApp)] = []
  let mut f = 0
  while f < finals_len {
    let id = match r.int() {
      Some(v) => v
      None => return None
    }
    let log_len = match r.int() {
      Some(n) => if n < 0 { return None } else { n }
      None => return None
    }
    let log : Array[Int] = []
    let mut k = 0
    while k < log_len {
      match r.int() {
        Some(v) => log.push(v)
        None => return None
      }
      k = k + 1
    }
    let kv_len = match r.int() {
      Some(n) => if n < 0 { return None } else { n }
      None => return None
    }
    let kv : Array[(String, Int)] = []
    let mut j = 0
    while j < kv_len {
      let key = match r.str() {
        Some(s) => s
        None => return None
      }
      let value = match r.int() {
        Some(v) => v
        None => return None
      }
      kv.push((key, value))
      j = j + 1
    }
    finals.push((id, { log, kv }))
    f = f + 1
  }
  Some({ seed, trace, status, finals })
}

///|
/// 从序列化文本反序列化重建 `DesResult`；格式非法 / 损坏 / 含多余尾部记号返回携带
/// 原因与偏移的 `Malformed`，绝不返回部分构造值（R8.2 / R8.5）。
pub fn deserialize_result(s : String) -> Result[DesResult, CodecError] {
  let toks = tokenize(s)
  let r : TokenReader = { toks, pos: 0 }
  match parse_result(r) {
    Some(res) =>
      if r.pos == toks.length() {
        Ok(res)
      } else {
        Err(Malformed(reason="多余的尾部记号", pos=r.pos))
      }
    None =>
      Err(Malformed(reason="非法或损坏的序列化文本", pos=r.pos))
  }
}

// ──────────────────── @infra_pbt.round_trip 适配（Bytes 互转） ───────────────

///|
/// 将 `DesResult` 编码为字节序列（序列化文本恒为 ASCII，故逐字符映射为字节）。
pub fn result_to_bytes(r : DesResult) -> Bytes {
  let s = serialize_result(r)
  let arr : Array[Byte] = []
  for c in s {
    arr.push((c.to_int() & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 从字节序列解码 `DesResult`；失败返回 `None`（供 `@infra_pbt.round_trip` 使用）。
pub fn result_of_bytes(b : Bytes) -> DesResult? {
  let sb = StringBuilder::new()
  for i in 0..<b.length() {
    sb.write_char(b[i].to_int().unsafe_to_char())
  }
  match deserialize_result(sb.to_string()) {
    Ok(r) => Some(r)
    Err(_) => None
  }
}
