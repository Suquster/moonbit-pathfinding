// cbor.mbt —— CBOR（RFC 8949）编解码。
//
// paper-to-code：IETF RFC 8949 *Concise Binary Object Representation*：
// - 每个数据项 = 首字节（高 3 位 major type + 低 5 位 additional info）
//   + 可选扩展长度字节 + 载荷；
// - major type：0=无符号整数、1=负整数（-1-n）、2=字节串、3=UTF-8 文本、
//   4=数组、5=映射、6=tag、7=简单值/浮点
//   （false/true/null/undefined/float16/float32/float64）；
// - 整数与长度编码侧使用最短编码（canonical，RFC 8949 §4.2.1）：
//   0..23 内联，24/25/26/27 → 1/2/4/8 字节大端扩展；
// - 解码侧额外接受不定长（info=31）字节串/文本/数组/映射
//   （RFC 8949 §3.2，块必须是同类型定长项，0xFF break 终止），
//   以及 float16/float32（§3.3，解码为 Double）。
//
// 解码为总体函数：畸形输入 / 越界 / 超深嵌套返回 None 不 panic；
// `cbor_decode` 强制「单一数据项 + 无尾随字节」。

///|
/// CBOR 数据项（RFC 8949；不定长编码在解码时归一化为定长值）。
pub(all) enum CborValue {
  /// major type 0：无符号整数。
  CborUInt(UInt64)
  /// major type 1：负整数，实际值为 -1 - n（n 为载荷）。
  CborNInt(UInt64)
  /// major type 2：字节串（每元素 0..255）。
  CborBytes(Array[Int])
  /// major type 3：UTF-8 文本串。
  CborText(String)
  /// major type 4：数组。
  CborArray(Array[CborValue])
  /// major type 5：映射（保序键值对列表，不去重）。
  CborMap(Array[(CborValue, CborValue)])
  /// major type 7 / simple 20、21。
  CborBool(Bool)
  /// major type 7 / simple 22。
  CborNull
  /// major type 7 / simple 23。
  CborUndefined
  /// major type 7：IEEE-754 浮点（float16/32 解码时提升为 float64）。
  CborFloat(Double)
  /// major type 6：带 tag 数据项（RFC 8949 §3.4）。
  CborTag(UInt64, CborValue)
} derive(Eq, Debug)

///|
/// 诊断输出（供 assert_eq 等测试断言使用）。
pub impl Show for CborValue with fn output(self, logger) {
  match self {
    CborUInt(n) => logger.write_string("CborUInt(\{n})")
    CborNInt(n) => logger.write_string("CborNInt(\{n})")
    CborBytes(bs) => {
      logger.write_string("CborBytes([")
      for i, b in bs {
        if i > 0 {
          logger.write_string(", ")
        }
        logger.write_string(b.to_string())
      }
      logger.write_string("])")
    }
    CborText(s) => logger.write_string("CborText(\{s.escape()})")
    CborArray(items) => {
      logger.write_string("CborArray([")
      for i, item in items {
        if i > 0 {
          logger.write_string(", ")
        }
        item.output(logger)
      }
      logger.write_string("])")
    }
    CborMap(pairs) => {
      logger.write_string("CborMap([")
      for i, pair in pairs {
        if i > 0 {
          logger.write_string(", ")
        }
        logger.write_string("(")
        pair.0.output(logger)
        logger.write_string(", ")
        pair.1.output(logger)
        logger.write_string(")")
      }
      logger.write_string("])")
    }
    CborBool(b) => logger.write_string("CborBool(\{b})")
    CborNull => logger.write_string("CborNull")
    CborUndefined => logger.write_string("CborUndefined")
    CborFloat(d) => logger.write_string("CborFloat(\{d})")
    CborTag(t, inner) => {
      logger.write_string("CborTag(\{t}, ")
      inner.output(logger)
      logger.write_string(")")
    }
  }
}

///|
/// 解码嵌套深度上限（防御恶意深嵌套导致栈溢出）。
pub let cbor_max_depth : Int = 512

///|
/// 首字节 + 最短编码扩展长度（RFC 8949 §4.2.1 canonical 整数编码）。
fn cbor_write_head(w : ByteWriter, major : Int, n : UInt64) -> Unit {
  let base = major << 5
  if n < 24UL {
    w.buf.push(base | n.to_int())
  } else if n < 256UL {
    w.buf.push(base | 24)
    w.buf.push(n.to_int())
  } else if n < 65536UL {
    w.buf.push(base | 25)
    w.buf.push((n >> 8).to_int() & 0xFF)
    w.buf.push(n.to_int() & 0xFF)
  } else if n < 4294967296UL {
    w.buf.push(base | 26)
    for shift in [24, 16, 8, 0] {
      w.buf.push((n >> shift).to_int() & 0xFF)
    }
  } else {
    w.buf.push(base | 27)
    for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
      w.buf.push((n >> shift).to_int() & 0xFF)
    }
  }
}

///|
/// 把一个 CBOR 数据项追加进 ByteWriter（canonical 最短整数编码）。
pub fn cbor_encode_into(w : ByteWriter, v : CborValue) -> Unit {
  match v {
    CborUInt(n) => cbor_write_head(w, 0, n)
    CborNInt(n) => cbor_write_head(w, 1, n)
    CborBytes(bs) => {
      cbor_write_head(w, 2, bs.length().to_int64().reinterpret_as_uint64())
      for b in bs {
        w.buf.push(b & 0xFF)
      }
    }
    CborText(s) => {
      let utf8 = utf8_bytes_of_string(s)
      cbor_write_head(w, 3, utf8.length().to_int64().reinterpret_as_uint64())
      for b in utf8 {
        w.buf.push(b)
      }
    }
    CborArray(items) => {
      cbor_write_head(w, 4, items.length().to_int64().reinterpret_as_uint64())
      for item in items {
        cbor_encode_into(w, item)
      }
    }
    CborMap(pairs) => {
      cbor_write_head(w, 5, pairs.length().to_int64().reinterpret_as_uint64())
      for pair in pairs {
        cbor_encode_into(w, pair.0)
        cbor_encode_into(w, pair.1)
      }
    }
    CborBool(b) => w.buf.push((7 << 5) | (if b { 21 } else { 20 }))
    CborNull => w.buf.push((7 << 5) | 22)
    CborUndefined => w.buf.push((7 << 5) | 23)
    CborTag(t, inner) => {
      cbor_write_head(w, 6, t)
      cbor_encode_into(w, inner)
    }
    CborFloat(d) => {
      w.buf.push((7 << 5) | 27)
      let bits = d.reinterpret_as_uint64()
      for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
        w.buf.push((bits >> shift).to_int() & 0xFF)
      }
    }
  }
}

///|
/// 编码单个 CBOR 数据项为字节数组。
pub fn cbor_encode(v : CborValue) -> Array[Int] {
  let w = ByteWriter::new()
  cbor_encode_into(w, v)
  w.to_bytes()
}

///|
/// 读取 n 个大端字节组成 UInt64；越界返回 None。
fn cbor_read_be(r : ByteReader, n : Int) -> UInt64? {
  if r.pos + n > r.buf.length() {
    return None
  }
  let mut acc = 0UL
  for _ in 0..<n {
    acc = (acc << 8) | (r.buf[r.pos] & 0xFF).to_uint64()
    r.pos = r.pos + 1
  }
  Some(acc)
}

///|
/// 解码首字节的 additional info 为载荷值（仅接受定长编码 0..27）。
fn cbor_read_head_value(r : ByteReader, info : Int) -> UInt64? {
  if info < 24 {
    Some(info.to_uint64())
  } else if info == 24 {
    cbor_read_be(r, 1)
  } else if info == 25 {
    cbor_read_be(r, 2)
  } else if info == 26 {
    cbor_read_be(r, 4)
  } else if info == 27 {
    cbor_read_be(r, 8)
  } else {
    None // 28..30 保留；31 不定长由调用方按 major type 单独处理
  }
}

///|
/// 2 的整数次幂（|k| ≤ 200，逐步乘除保持精确）。
fn cbor_pow2(k : Int) -> Double {
  let mut acc = 1.0
  if k >= 0 {
    for _ in 0..<k {
      acc = acc * 2.0
    }
  } else {
    for _ in 0..<-k {
      acc = acc * 0.5
    }
  }
  acc
}

///|
/// IEEE-754 binary16 位型提升为 Double（RFC 8949 §3.3 / 附录 D）。
fn cbor_half_to_double(bits : Int) -> Double {
  let sign = if (bits & 0x8000) != 0 { -1.0 } else { 1.0 }
  let exp = (bits >> 10) & 0x1F
  let frac = bits & 0x3FF
  if exp == 0 {
    // 次正规：frac * 2^-24。
    sign * frac.to_double() * cbor_pow2(-24)
  } else if exp == 31 {
    if frac == 0 {
      sign * 0x7FF0000000000000UL.reinterpret_as_double()
    } else {
      0x7FF8000000000000UL.reinterpret_as_double()
    }
  } else {
    sign * (1.0 + frac.to_double() * cbor_pow2(-10)) * cbor_pow2(exp - 15)
  }
}

///|
/// IEEE-754 binary32 位型提升为 Double（RFC 8949 §3.3）。
fn cbor_single_to_double(bits : UInt64) -> Double {
  let sign = if (bits & 0x80000000UL) != 0UL { -1.0 } else { 1.0 }
  let exp = ((bits >> 23) & 0xFFUL).to_int()
  let frac = (bits & 0x7FFFFFUL).to_int()
  if exp == 0 {
    // 次正规：frac * 2^-149。
    sign * frac.to_double() * cbor_pow2(-149)
  } else if exp == 255 {
    if frac == 0 {
      sign * 0x7FF0000000000000UL.reinterpret_as_double()
    } else {
      0x7FF8000000000000UL.reinterpret_as_double()
    }
  } else {
    sign * (1.0 + frac.to_double() * cbor_pow2(-23)) * cbor_pow2(exp - 127)
  }
}

///|
/// 不定长字节串/文本串体（RFC 8949 §3.2.3）：块必须为同 major type 的
/// 定长串，0xFF break 终止；返回拼接后的原始字节。
fn cbor_read_indefinite_chunks(r : ByteReader, major : Int) -> Array[Int]? {
  let bs : Array[Int] = []
  while true {
    if r.pos >= r.buf.length() {
      return None
    }
    let head = r.buf[r.pos] & 0xFF
    r.pos = r.pos + 1
    if head == 0xFF {
      break
    }
    if head >> 5 != major || (head & 0x1F) == 31 {
      return None // 块类型不符或嵌套不定长（RFC 8949 明确禁止）。
    }
    match cbor_read_head_value(r, head & 0x1F) {
      Some(len64) => {
        let len = len64.to_int()
        if len64 > 2147483647UL || r.pos + len > r.buf.length() {
          return None
        }
        for _ in 0..<len {
          bs.push(r.buf[r.pos] & 0xFF)
          r.pos = r.pos + 1
        }
      }
      None => return None
    }
  }
  Some(bs)
}

///|
/// 窥视下一字节是否为 break（0xFF）；是则消费并返回 true。
fn cbor_try_break(r : ByteReader) -> Bool {
  if r.pos < r.buf.length() && (r.buf[r.pos] & 0xFF) == 0xFF {
    r.pos = r.pos + 1
    true
  } else {
    false
  }
}

///|
/// 递归解码一个数据项；depth 为剩余允许深度。
fn cbor_decode_item(r : ByteReader, depth : Int) -> CborValue? {
  if depth <= 0 || r.pos >= r.buf.length() {
    return None
  }
  let head = r.buf[r.pos] & 0xFF
  r.pos = r.pos + 1
  let major = head >> 5
  let info = head & 0x1F
  match major {
    0 =>
      match cbor_read_head_value(r, info) {
        Some(n) => Some(CborUInt(n))
        None => None
      }
    1 =>
      match cbor_read_head_value(r, info) {
        Some(n) => Some(CborNInt(n))
        None => None
      }
    2 =>
      if info == 31 {
        match cbor_read_indefinite_chunks(r, 2) {
          Some(bs) => Some(CborBytes(bs))
          None => None
        }
      } else {
        match cbor_read_head_value(r, info) {
          Some(len64) => {
            let len = len64.to_int()
            if len64 > 2147483647UL || r.pos + len > r.buf.length() {
              return None
            }
            let bs : Array[Int] = []
            for _ in 0..<len {
              bs.push(r.buf[r.pos] & 0xFF)
              r.pos = r.pos + 1
            }
            Some(CborBytes(bs))
          }
          None => None
        }
      }
    3 => {
      let bs = if info == 31 {
        match cbor_read_indefinite_chunks(r, 3) {
          Some(bs) => bs
          None => return None
        }
      } else {
        match cbor_read_head_value(r, info) {
          Some(len64) => {
            let len = len64.to_int()
            if len64 > 2147483647UL || r.pos + len > r.buf.length() {
              return None
            }
            let bs : Array[Int] = []
            for _ in 0..<len {
              bs.push(r.buf[r.pos] & 0xFF)
              r.pos = r.pos + 1
            }
            bs
          }
          None => return None
        }
      }
      match string_of_utf8_bytes(bs) {
        Some(s) => Some(CborText(s))
        None => None
      }
    }
    4 =>
      if info == 31 {
        let items : Array[CborValue] = []
        while !cbor_try_break(r) {
          match cbor_decode_item(r, depth - 1) {
            Some(item) => items.push(item)
            None => return None
          }
        }
        Some(CborArray(items))
      } else {
        match cbor_read_head_value(r, info) {
          Some(len64) => {
            if len64 > 2147483647UL {
              return None
            }
            let len = len64.to_int()
            let items : Array[CborValue] = []
            for _ in 0..<len {
              match cbor_decode_item(r, depth - 1) {
                Some(item) => items.push(item)
                None => return None
              }
            }
            Some(CborArray(items))
          }
          None => None
        }
      }
    5 =>
      if info == 31 {
        let pairs : Array[(CborValue, CborValue)] = []
        while !cbor_try_break(r) {
          let k = match cbor_decode_item(r, depth - 1) {
            Some(k) => k
            None => return None
          }
          let v = match cbor_decode_item(r, depth - 1) {
            Some(v) => v
            None => return None
          }
          pairs.push((k, v))
        }
        Some(CborMap(pairs))
      } else {
        match cbor_read_head_value(r, info) {
          Some(len64) => {
            if len64 > 2147483647UL {
              return None
            }
            let len = len64.to_int()
            let pairs : Array[(CborValue, CborValue)] = []
            for _ in 0..<len {
              let k = match cbor_decode_item(r, depth - 1) {
                Some(k) => k
                None => return None
              }
              let v = match cbor_decode_item(r, depth - 1) {
                Some(v) => v
                None => return None
              }
              pairs.push((k, v))
            }
            Some(CborMap(pairs))
          }
          None => None
        }
      }
    6 =>
      match cbor_read_head_value(r, info) {
        Some(t) =>
          match cbor_decode_item(r, depth - 1) {
            Some(inner) => Some(CborTag(t, inner))
            None => None
          }
        None => None
      }
    7 =>
      if info == 20 {
        Some(CborBool(false))
      } else if info == 21 {
        Some(CborBool(true))
      } else if info == 22 {
        Some(CborNull)
      } else if info == 23 {
        Some(CborUndefined)
      } else if info == 25 {
        match cbor_read_be(r, 2) {
          Some(bits) => Some(CborFloat(cbor_half_to_double(bits.to_int())))
          None => None
        }
      } else if info == 26 {
        match cbor_read_be(r, 4) {
          Some(bits) => Some(CborFloat(cbor_single_to_double(bits)))
          None => None
        }
      } else if info == 27 {
        match cbor_read_be(r, 8) {
          Some(bits) => Some(CborFloat(bits.reinterpret_as_double()))
          None => None
        }
      } else {
        // 其余 simple 值（0..19、24 扩展）与孤立 break（31）拒绝。
        None
      }
    _ => None
  }
}

///|
/// 解码单个 CBOR 数据项；要求恰好消费全部输入（无尾随字节），
/// 畸形 / 越界 / 超深嵌套返回 None。
pub fn cbor_decode(bytes : Array[Int]) -> CborValue? {
  let r = ByteReader::new(bytes)
  match cbor_decode_item(r, cbor_max_depth) {
    Some(v) => if r.pos == bytes.length() { Some(v) } else { None }
    None => None
  }
}
