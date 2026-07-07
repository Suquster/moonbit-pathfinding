// utf8.mbt —— 严格 UTF-8 编解码（RFC 3629）。
//
// paper-to-code：RFC 3629 *UTF-8, a transformation format of ISO 10646*：
// - 1..4 字节序列，码点区间 U+0000..U+10FFFF；
// - 拒绝 overlong 编码（非最短形式）、代理区 U+D800..U+DFFF、
//   超出 U+10FFFF 与截断序列（§3 语法 + §10 安全考虑）。

///|
/// 把字符串编码为严格 UTF-8 字节序列（每元素 0..255）。
pub fn utf8_bytes_of_string(s : String) -> Array[Int] {
  let out : Array[Int] = []
  for c in s.iter() {
    let cp = c.to_int()
    if cp < 0x80 {
      out.push(cp)
    } else if cp < 0x800 {
      out.push(0xC0 | (cp >> 6))
      out.push(0x80 | (cp & 0x3F))
    } else if cp < 0x10000 {
      out.push(0xE0 | (cp >> 12))
      out.push(0x80 | ((cp >> 6) & 0x3F))
      out.push(0x80 | (cp & 0x3F))
    } else {
      out.push(0xF0 | (cp >> 18))
      out.push(0x80 | ((cp >> 12) & 0x3F))
      out.push(0x80 | ((cp >> 6) & 0x3F))
      out.push(0x80 | (cp & 0x3F))
    }
  }
  out
}

///|
/// 严格解码 UTF-8 字节序列为字符串；overlong / 代理区 / 超范围 / 截断
/// 一律返回 None（RFC 3629 §3 / §10）。
pub fn string_of_utf8_bytes(bytes : Array[Int]) -> String? {
  let sb = StringBuilder::new()
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b0 = bytes[i] & 0xFF
    let (cp, size) = if b0 < 0x80 {
      (b0, 1)
    } else if (b0 & 0xE0) == 0xC0 {
      if i + 1 >= n {
        return None
      }
      let b1 = bytes[i + 1] & 0xFF
      if (b1 & 0xC0) != 0x80 {
        return None
      }
      (((b0 & 0x1F) << 6) | (b1 & 0x3F), 2)
    } else if (b0 & 0xF0) == 0xE0 {
      if i + 2 >= n {
        return None
      }
      let b1 = bytes[i + 1] & 0xFF
      let b2 = bytes[i + 2] & 0xFF
      if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 {
        return None
      }
      (((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F), 3)
    } else if (b0 & 0xF8) == 0xF0 {
      if i + 3 >= n {
        return None
      }
      let b1 = bytes[i + 1] & 0xFF
      let b2 = bytes[i + 2] & 0xFF
      let b3 = bytes[i + 3] & 0xFF
      if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        return None
      }
      (
        ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F),
        4,
      )
    } else {
      return None // 孤立续字节或非法首字节 0xF8..0xFF
    }
    // overlong：解码值必须落在该长度的最小码点之上。
    let min_cp = match size {
      1 => 0x0
      2 => 0x80
      3 => 0x800
      _ => 0x10000
    }
    if cp < min_cp {
      return None
    }
    // 代理区与超范围。
    if (cp >= 0xD800 && cp <= 0xDFFF) || cp > 0x10FFFF {
      return None
    }
    match cp.to_char() {
      Some(c) => sb.write_char(c)
      None => return None
    }
    i = i + size
  }
  Some(sb.to_string())
}
