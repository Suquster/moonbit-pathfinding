// codec.mbt —— E2 二进制编解码（protobuf wire format 同构子集）。
//
// paper-to-code：Google Protocol Buffers *Encoding* 规范
// （https://protobuf.dev/programming-guides/encoding/）：
// - varint：LEB128 基数-128 变长整数，低 7 位载荷 + 最高位续传标志，
//   UInt64 最多 10 字节；
// - zigzag：有符号→无符号折叠 (n << 1) ^ (n >> 63)，小绝对值负数编码短
//   （protobuf sint64 语义）；
// - 定长小端 u32/u64（fixed32/fixed64）；
// - length-prefixed bytes / UTF-8 string（LEN wire type）。
//
// 对外 API：ByteWriter（append-only 缓冲）/ ByteReader（游标解码，
// 越界或畸形输入返回 None 不 panic）。

///|
/// append-only 编码缓冲。
pub struct ByteWriter {
  buf : Array[Int] // 每元素 0..255
}

///|
/// 空缓冲。
pub fn ByteWriter::new() -> ByteWriter {
  { buf: [] }
}

///|
/// 已写字节数。
pub fn ByteWriter::length(self : ByteWriter) -> Int {
  self.buf.length()
}

///|
/// 导出字节数组（0..255 的 Int）。
pub fn ByteWriter::to_bytes(self : ByteWriter) -> Array[Int] {
  self.buf.copy()
}

///|
/// varint（LEB128）：低 7 位载荷 + 最高位续传，UInt64 最多 10 字节。
pub fn ByteWriter::write_varint(self : ByteWriter, v : UInt64) -> Unit {
  let mut x = v
  while x >= 0x80UL {
    self.buf.push((x & 0x7FUL).to_int() | 0x80)
    x = x >> 7
  }
  self.buf.push(x.to_int())
}

///|
/// zigzag 折叠后 varint 编码（protobuf sint64）。
pub fn ByteWriter::write_zigzag(self : ByteWriter, v : Int64) -> Unit {
  let z = (v << 1) ^ (v >> 63)
  self.write_varint(z.reinterpret_as_uint64())
}

///|
/// 定长小端 32 位（fixed32）。
pub fn ByteWriter::write_u32(self : ByteWriter, v : UInt) -> Unit {
  let x = v.reinterpret_as_int()
  self.buf.push(x & 0xFF)
  self.buf.push((x >> 8) & 0xFF)
  self.buf.push((x >> 16) & 0xFF)
  self.buf.push((x >> 24) & 0xFF)
}

///|
/// 定长小端 64 位（fixed64）。
pub fn ByteWriter::write_u64(self : ByteWriter, v : UInt64) -> Unit {
  let mut x = v
  for _ in 0..<8 {
    self.buf.push((x & 0xFFUL).to_int())
    x = x >> 8
  }
}

///|
/// length-prefixed 字节串（LEN wire type）。
pub fn ByteWriter::write_bytes(self : ByteWriter, bytes : Array[Int]) -> Unit {
  self.write_varint(bytes.length().to_uint64())
  for b in bytes {
    self.buf.push(b & 0xFF)
  }
}

///|
/// length-prefixed 字符串（按 Unicode 码点序列化为变长整数流，round-trip 无损）。
pub fn ByteWriter::write_string(self : ByteWriter, s : String) -> Unit {
  let chars = s.iter().to_array()
  self.write_varint(chars.length().to_uint64())
  for c in chars {
    self.write_varint(c.to_int().to_uint64())
  }
}

///|
/// 游标解码器：所有读取越界/畸形时返回 None，不 panic。
pub struct ByteReader {
  buf : Array[Int]
  mut pos : Int
}

///|
/// 从字节数组构造。
pub fn ByteReader::new(buf : Array[Int]) -> ByteReader {
  { buf, pos: 0 }
}

///|
/// 剩余未读字节数。
pub fn ByteReader::remaining(self : ByteReader) -> Int {
  self.buf.length() - self.pos
}

///|
/// varint 解码（>10 字节或缓冲耗尽 → None）。
pub fn ByteReader::read_varint(self : ByteReader) -> UInt64? {
  let mut result = 0UL
  let mut shift = 0
  for _ in 0..<10 {
    if self.pos >= self.buf.length() {
      return None
    }
    let b = self.buf[self.pos]
    self.pos = self.pos + 1
    result = result | ((b & 0x7F).to_uint64() << shift)
    if (b & 0x80) == 0 {
      return Some(result)
    }
    shift = shift + 7
  }
  None // 畸形：超过 10 字节仍有续传位
}

///|
/// zigzag 展开：(z >> 1) ^ -(z & 1)。
pub fn ByteReader::read_zigzag(self : ByteReader) -> Int64? {
  match self.read_varint() {
    Some(z) =>
      // 逻辑右移一位，再按最低位取反：(z >>> 1) ^ -(z & 1)。
      Some((z >> 1).reinterpret_as_int64() ^ -(z & 1UL).reinterpret_as_int64())
    None => None
  }
}

///|
/// 定长小端 32 位。
pub fn ByteReader::read_u32(self : ByteReader) -> UInt? {
  if self.remaining() < 4 {
    return None
  }
  let mut x = 0
  for i in 0..<4 {
    x = x | (self.buf[self.pos + i] << (8 * i))
  }
  self.pos = self.pos + 4
  Some(x.reinterpret_as_uint())
}

///|
/// 定长小端 64 位。
pub fn ByteReader::read_u64(self : ByteReader) -> UInt64? {
  if self.remaining() < 8 {
    return None
  }
  let mut x = 0UL
  for i in 0..<8 {
    x = x | (self.buf[self.pos + i].to_uint64() << (8 * i))
  }
  self.pos = self.pos + 8
  Some(x)
}

///|
/// length-prefixed 字节串（长度越界 → None）。
pub fn ByteReader::read_bytes(self : ByteReader) -> Array[Int]? {
  match self.read_varint() {
    Some(len64) => {
      let len = len64.to_int()
      if len < 0 || self.remaining() < len {
        return None
      }
      let out : Array[Int] = []
      for i in 0..<len {
        out.push(self.buf[self.pos + i])
      }
      self.pos = self.pos + len
      Some(out)
    }
    None => None
  }
}

///|
/// 字节长度前缀 + 码点 varint 序列载荷的字符串（FieldWriter::string_field
/// 的编码形式）：顺序解码，畸形/越界返回 None。
pub fn ByteReader::read_string_payload(self : ByteReader) -> String? {
  match self.read_varint() {
    Some(len64) => {
      let len = len64.to_int()
      if len < 0 || self.remaining() < len {
        return None
      }
      let stop = self.pos + len
      let sb = StringBuilder::new()
      while self.pos < stop {
        match self.read_varint() {
          Some(cp) => {
            if self.pos > stop {
              return None
            }
            match cp.to_int().to_char() {
              Some(c) => sb.write_char(c)
              None => return None
            }
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
/// length-prefixed 字符串。
pub fn ByteReader::read_string(self : ByteReader) -> String? {
  match self.read_varint() {
    Some(len64) => {
      let len = len64.to_int()
      if len < 0 {
        return None
      }
      let out = StringBuilder::new()
      for _ in 0..<len {
        match self.read_varint() {
          Some(cp) =>
            match cp.to_int().to_char() {
              Some(c) => out.write_char(c)
              None => return None
            }
          None => return None
        }
      }
      Some(out.to_string())
    }
    None => None
  }
}
