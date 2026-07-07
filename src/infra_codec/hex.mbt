// hex.mbt —— 十六进制编解码（RFC 4648 §8 Base16）。
//
// - 编码输出小写；
// - 解码同时接受大小写，奇数长度或非法字符返回 None（总体函数不 panic）。

///|
/// 小写十六进制字符表。
let hex_digits : String = "0123456789abcdef"

///|
/// 把字节数组（每元素 0..255）编码为小写十六进制串。
pub fn hex_encode(bytes : Array[Int]) -> String {
  let sb = StringBuilder::new()
  for b in bytes {
    let v = b & 0xFF
    sb.write_char(hex_digits.get_char(v >> 4).unwrap())
    sb.write_char(hex_digits.get_char(v & 0xF).unwrap())
  }
  sb.to_string()
}

///|
/// 单个十六进制字符的数值；非法字符返回 -1。
fn hex_digit_value(c : Char) -> Int {
  let cp = c.to_int()
  if cp >= 48 && cp <= 57 {
    cp - 48 // '0'..'9'
  } else if cp >= 97 && cp <= 102 {
    cp - 87 // 'a'..'f'
  } else if cp >= 65 && cp <= 70 {
    cp - 55 // 'A'..'F'
  } else {
    -1
  }
}

///|
/// 解码十六进制串（大小写皆可）；奇数长度或非法字符返回 None。
pub fn hex_decode(text : String) -> Array[Int]? {
  let chars = text.iter().to_array()
  if chars.length() % 2 != 0 {
    return None
  }
  let out : Array[Int] = []
  let mut i = 0
  while i < chars.length() {
    let hi = hex_digit_value(chars[i])
    let lo = hex_digit_value(chars[i + 1])
    if hi < 0 || lo < 0 {
      return None
    }
    out.push((hi << 4) | lo)
    i = i + 2
  }
  Some(out)
}
