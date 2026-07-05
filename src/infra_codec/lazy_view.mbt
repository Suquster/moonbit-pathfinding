// lazy_view.mbt —— E2 序列化深化：零拷贝惰性字段视图。
//
// 对标 protobuf lazy parsing / flatbuffers 的按需访问模型：消息保持编码
// 态字节缓冲，字段访问时只做「键扫描 + 定点解码」——键为 protobuf 规范的
// `(field_number << 3) | wire_type` varint，LEN 字段按长度前缀 O(1) 跳过，
// 不物化未访问字段（不建 Map、不拷贝字符串、不解码嵌套消息）。
//
// 稀疏访问工作负载（RPC 网关取路由键、日志管道取时间戳等只碰少数字段）
// 下，惰性视图代价 = O(键扫描) + O(命中字段解码)；朴素做法全量解码整条
// 消息（含全部字符串物化）为 O(总字节数)。嵌套消息返回零拷贝子视图
// （同一缓冲上的 [start, end) 窗口），逐层惰性。
//
// wire type：0 = varint，1 = fixed64，2 = LEN（bytes/string/嵌套消息），
// 5 = fixed32（与 protobuf 编码规范一致）；畸形输入一律 None 不 panic。
//
// 对外 API：FieldWriter（在 ByteWriter 上写带键字段）/
// MsgView::{over, varint_field, zigzag_field, fixed64_field, fixed32_field,
// string_field, bytes_field, message_field, has_field, field_count}。

///|
/// 在 ByteWriter 上追加「键 + 值」编码字段（protobuf 兼容）。
pub struct FieldWriter {
  w : ByteWriter
}

///|
/// 包装一个 ByteWriter。
pub fn FieldWriter::over(w : ByteWriter) -> FieldWriter {
  { w, }
}

///|
fn FieldWriter::key(self : FieldWriter, field_no : Int, wire : Int) -> Unit {
  self.w.write_varint(
    ((field_no << 3) | wire).to_int64().reinterpret_as_uint64(),
  )
}

///|
/// varint 字段（wire type 0）。
pub fn FieldWriter::varint_field(
  self : FieldWriter,
  field_no : Int,
  v : UInt64,
) -> Unit {
  self.key(field_no, 0)
  self.w.write_varint(v)
}

///|
/// zigzag 有符号字段（wire type 0，sint64 语义）。
pub fn FieldWriter::zigzag_field(
  self : FieldWriter,
  field_no : Int,
  v : Int64,
) -> Unit {
  self.key(field_no, 0)
  self.w.write_zigzag(v)
}

///|
/// fixed64 字段（wire type 1）。
pub fn FieldWriter::fixed64_field(
  self : FieldWriter,
  field_no : Int,
  v : UInt64,
) -> Unit {
  self.key(field_no, 1)
  self.w.write_u64(v)
}

///|
/// fixed32 字段（wire type 5）。
pub fn FieldWriter::fixed32_field(
  self : FieldWriter,
  field_no : Int,
  v : UInt,
) -> Unit {
  self.key(field_no, 5)
  self.w.write_u32(v)
}

///|
/// string 字段（wire type 2，字节长度前缀 + 码点 varint 序列载荷）。
pub fn FieldWriter::string_field(
  self : FieldWriter,
  field_no : Int,
  s : String,
) -> Unit {
  let tmp = ByteWriter::new()
  for c in s.iter() {
    tmp.write_varint(c.to_int().to_uint64())
  }
  self.key(field_no, 2)
  self.w.write_varint(tmp.length().to_int64().reinterpret_as_uint64())
  for b in tmp.to_bytes() {
    self.w.buf.push(b)
  }
}

///|
/// 嵌套消息字段（wire type 2）：body 为子消息编码字节。
pub fn FieldWriter::message_field(
  self : FieldWriter,
  field_no : Int,
  body : Array[Int],
) -> Unit {
  self.key(field_no, 2)
  self.w.write_varint(body.length().to_int64().reinterpret_as_uint64())
  for b in body {
    self.w.buf.push(b)
  }
}

///|
/// 编码态消息的零拷贝窗口视图 [start, end)。
pub struct MsgView {
  buf : Array[Int]
  start : Int
  end : Int
}

///|
/// 覆盖整个缓冲的视图。
pub fn MsgView::over(buf : Array[Int]) -> MsgView {
  { buf, start: 0, end: buf.length() }
}

///|
/// 视图内在偏移 pos 处读 varint，返回 (值, 新偏移)；畸形返回 None。
fn MsgView::read_varint_at(self : MsgView, pos : Int) -> (UInt64, Int)? {
  let mut p = pos
  let mut shift = 0
  let mut acc = 0UL
  while p < self.end && shift < 64 {
    let b = self.buf[p]
    acc = acc | ((b & 0x7F).to_uint64() << shift)
    p = p + 1
    if (b & 0x80) == 0 {
      return Some((acc, p))
    }
    shift = shift + 7
  }
  None
}

///|
/// 定位字段 field_no 的首个匹配：返回 (wire, 值起始偏移)。
/// LEN/fixed 字段 O(1) 跳过；未命中或畸形返回 None。
fn MsgView::locate(self : MsgView, field_no : Int) -> (Int, Int)? {
  let mut p = self.start
  while p < self.end {
    match self.read_varint_at(p) {
      None => return None
      Some((key, q)) => {
        let fno = (key >> 3).to_int()
        let wire = (key & 7UL).to_int()
        if fno == field_no {
          return Some((wire, q))
        }
        // 跳过该字段值。
        match wire {
          0 =>
            match self.read_varint_at(q) {
              Some((_, r)) => p = r
              None => return None
            }
          1 => p = q + 8
          5 => p = q + 4
          2 =>
            match self.read_varint_at(q) {
              Some((len, r)) => p = r + len.to_int()
              None => return None
            }
          _ => return None
        }
        if p > self.end {
          return None
        }
      }
    }
  }
  None
}

///|
/// 字段是否存在（含畸形防护）。
pub fn MsgView::has_field(self : MsgView, field_no : Int) -> Bool {
  self.locate(field_no) is Some(_)
}

///|
/// varint 字段值（wire type 0）。
pub fn MsgView::varint_field(self : MsgView, field_no : Int) -> UInt64? {
  match self.locate(field_no) {
    Some((0, q)) =>
      match self.read_varint_at(q) {
        Some((v, r)) => if r <= self.end { Some(v) } else { None }
        None => None
      }
    _ => None
  }
}

///|
/// zigzag 有符号字段值。
pub fn MsgView::zigzag_field(self : MsgView, field_no : Int) -> Int64? {
  match self.varint_field(field_no) {
    Some(z) => {
      let zi = z.reinterpret_as_int64()
      Some(
        (zi.reinterpret_as_uint64() >> 1).reinterpret_as_int64() ^ -(zi & 1L),
      )
    }
    None => None
  }
}

///|
/// fixed64 字段值（wire type 1，小端）。
pub fn MsgView::fixed64_field(self : MsgView, field_no : Int) -> UInt64? {
  match self.locate(field_no) {
    Some((1, q)) => {
      if q + 8 > self.end {
        return None
      }
      let mut acc = 0UL
      for i in 0..<8 {
        acc = acc | (self.buf[q + i].to_uint64() << (8 * i))
      }
      Some(acc)
    }
    _ => None
  }
}

///|
/// fixed32 字段值（wire type 5，小端）。
pub fn MsgView::fixed32_field(self : MsgView, field_no : Int) -> UInt? {
  match self.locate(field_no) {
    Some((5, q)) => {
      if q + 4 > self.end {
        return None
      }
      let mut acc = 0U
      for i in 0..<4 {
        acc = acc | (self.buf[q + i].reinterpret_as_uint() << (8 * i))
      }
      Some(acc)
    }
    _ => None
  }
}

///|
/// LEN 字段的 (载荷起始, 载荷长度)；畸形/越界返回 None。
fn MsgView::len_payload(self : MsgView, field_no : Int) -> (Int, Int)? {
  match self.locate(field_no) {
    Some((2, q)) =>
      match self.read_varint_at(q) {
        Some((len, r)) => {
          let l = len.to_int()
          if l < 0 || r + l > self.end {
            None
          } else {
            Some((r, l))
          }
        }
        None => None
      }
    _ => None
  }
}

///|
/// bytes 字段值（拷贝出载荷；仅命中时才物化）。
pub fn MsgView::bytes_field(self : MsgView, field_no : Int) -> Array[Int]? {
  match self.len_payload(field_no) {
    Some((off, len)) => {
      let out : Array[Int] = []
      for i in 0..<len {
        out.push(self.buf[off + i])
      }
      Some(out)
    }
    None => None
  }
}

///|
/// string 字段值（码点 varint 序列解码；仅命中时才物化）。
pub fn MsgView::string_field(self : MsgView, field_no : Int) -> String? {
  match self.len_payload(field_no) {
    Some((off, len)) => {
      let sb = StringBuilder::new()
      let mut p = off
      let stop = off + len
      while p < stop {
        match self.read_varint_at(p) {
          Some((cp, q)) => {
            if q > stop {
              return None
            }
            match cp.to_int().to_char() {
              Some(c) => sb.write_char(c)
              None => return None
            }
            p = q
          }
          None => return None
        }
      }
      Some(sb.to_string())
    }
    None => None
  }
}

///|
/// 嵌套消息字段：返回同一缓冲上的零拷贝子视图。
pub fn MsgView::message_field(self : MsgView, field_no : Int) -> MsgView? {
  match self.len_payload(field_no) {
    Some((off, len)) => Some({ buf: self.buf, start: off, end: off + len })
    None => None
  }
}

///|
/// 视图内字段总数（诊断；畸形返回 None）。
pub fn MsgView::field_count(self : MsgView) -> Int? {
  let mut p = self.start
  let mut n = 0
  while p < self.end {
    match self.read_varint_at(p) {
      None => return None
      Some((key, q)) => {
        let wire = (key & 7UL).to_int()
        match wire {
          0 =>
            match self.read_varint_at(q) {
              Some((_, r)) => p = r
              None => return None
            }
          1 => p = q + 8
          5 => p = q + 4
          2 =>
            match self.read_varint_at(q) {
              Some((len, r)) => p = r + len.to_int()
              None => return None
            }
          _ => return None
        }
        if p > self.end {
          return None
        }
        n = n + 1
      }
    }
  }
  Some(n)
}
