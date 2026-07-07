// hash.mbt —— 哈希与校验基础设施。
//
// paper-to-code：
// - SHA-256：NIST FIPS 180-4 *Secure Hash Standard* §6.2——512 位分组、
//   64 轮压缩（Ch/Maj/Σ/σ 逻辑函数 + 前 64 个素数立方根小数部分常量）、
//   Merkle–Damgård 长度填充；
// - HMAC-SHA256：RFC 2104——H((K ⊕ opad) ∥ H((K ⊕ ipad) ∥ m))，
//   超长密钥先做一次哈希；
// - CRC-32：IEEE 802.3 反射多项式 0xEDB88320，表驱动逐字节更新，
//   初值/终值取反（与 zlib `crc32()` 一致）；
// - FNV-1a：Fowler–Noll–Vo，先异或后乘素数（32 位 0x01000193 /
//   64 位 0x100000001B3）。
//
// 输入统一为字节数组（每元素 0..255）；纯计算、三后端逐位一致。

///|
/// SHA-256 轮常量（前 64 个素数立方根小数部分，FIPS 180-4 §4.2.2）。
let sha256_k : Array[UInt] = [
  0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U,
  0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU,
  0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU,
  0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU, 0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
  0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU,
  0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
  0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U, 0x19a4c116U,
  0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
  0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U,
  0xc67178f2U,
]

///|
/// 32 位循环右移。
fn rotr(x : UInt, n : Int) -> UInt {
  (x >> n) | (x << (32 - n))
}

///|
/// SHA-256（FIPS 180-4）：输入字节数组，输出 32 字节摘要。
pub fn sha256(data : Array[Int]) -> Array[Int] {
  // Merkle–Damgård 填充：0x80 + 若干 0x00 + 64 位大端比特长度。
  let msg : Array[Int] = []
  for b in data {
    msg.push(b & 0xFF)
  }
  let bit_len = data.length().to_int64() * 8L
  msg.push(0x80)
  while msg.length() % 64 != 56 {
    msg.push(0x00)
  }
  for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
    msg.push(((bit_len >> shift) & 0xFFL).to_int())
  }
  // 初始哈希值（前 8 个素数平方根小数部分，§5.3.3）。
  let h : Array[UInt] = [
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
    0x1f83d9abU, 0x5be0cd19U,
  ]
  let w : Array[UInt] = Array::make(64, 0U)
  let mut off = 0
  while off < msg.length() {
    // 消息调度。
    for t in 0..<16 {
      let base = off + t * 4
      w[t] = (msg[base].reinterpret_as_uint() << 24) |
        (msg[base + 1].reinterpret_as_uint() << 16) |
        (msg[base + 2].reinterpret_as_uint() << 8) |
        msg[base + 3].reinterpret_as_uint()
    }
    for t in 16..<64 {
      let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
      let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
      w[t] = w[t - 16] + s0 + w[t - 7] + s1
    }
    // 64 轮压缩。
    let mut a = h[0]
    let mut b = h[1]
    let mut c = h[2]
    let mut d = h[3]
    let mut e = h[4]
    let mut f = h[5]
    let mut g = h[6]
    let mut hh = h[7]
    for t in 0..<64 {
      let big_s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
      let ch = (e & f) ^ (e.lnot() & g)
      let t1 = hh + big_s1 + ch + sha256_k[t] + w[t]
      let big_s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
      let maj = (a & b) ^ (a & c) ^ (b & c)
      let t2 = big_s0 + maj
      hh = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    }
    h[0] = h[0] + a
    h[1] = h[1] + b
    h[2] = h[2] + c
    h[3] = h[3] + d
    h[4] = h[4] + e
    h[5] = h[5] + f
    h[6] = h[6] + g
    h[7] = h[7] + hh
    off = off + 64
  }
  let out : Array[Int] = []
  for x in h {
    for shift in [24, 16, 8, 0] {
      out.push(((x >> shift) & 0xFFU).reinterpret_as_int())
    }
  }
  out
}

///|
/// HMAC-SHA256（RFC 2104）：H((K⊕opad) ∥ H((K⊕ipad) ∥ m))；
/// 超过分组长（64 字节）的密钥先做一次 SHA-256。
pub fn hmac_sha256(key : Array[Int], message : Array[Int]) -> Array[Int] {
  let k0 : Array[Int] = []
  if key.length() > 64 {
    for b in sha256(key) {
      k0.push(b)
    }
  } else {
    for b in key {
      k0.push(b & 0xFF)
    }
  }
  while k0.length() < 64 {
    k0.push(0x00)
  }
  let inner : Array[Int] = []
  for b in k0 {
    inner.push(b ^ 0x36)
  }
  for b in message {
    inner.push(b & 0xFF)
  }
  let outer : Array[Int] = []
  for b in k0 {
    outer.push(b ^ 0x5C)
  }
  for b in sha256(inner) {
    outer.push(b)
  }
  sha256(outer)
}

///|
/// CRC-32 查找表（反射多项式 0xEDB88320，惰性构建的确定性常量表）。
let crc32_table : Array[UInt] = crc32_make_table()

///|
fn crc32_make_table() -> Array[UInt] {
  let table : Array[UInt] = Array::make(256, 0U)
  for i in 0..<256 {
    let mut c = i.reinterpret_as_uint()
    for _ in 0..<8 {
      c = if (c & 1U) != 0U { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
    }
    table[i] = c
  }
  table
}

///|
/// CRC-32（IEEE 802.3 / zlib `crc32()` 语义）：初值 0xFFFFFFFF、
/// 表驱动逐字节更新、终值取反。
pub fn crc32(data : Array[Int]) -> UInt {
  let mut c = 0xFFFFFFFFU
  for b in data {
    c = crc32_table[((c ^ (b & 0xFF).reinterpret_as_uint()) & 0xFFU).reinterpret_as_int()] ^
      (c >> 8)
  }
  c ^ 0xFFFFFFFFU
}

///|
/// FNV-1a 32 位：offset basis 0x811C9DC5、素数 0x01000193，先异或后乘。
pub fn fnv1a_32(data : Array[Int]) -> UInt {
  let mut h = 0x811C9DC5U
  for b in data {
    h = h ^ (b & 0xFF).reinterpret_as_uint()
    h = h * 0x01000193U
  }
  h
}

///|
/// FNV-1a 64 位：offset basis 0xCBF29CE484222325、素数 0x100000001B3。
pub fn fnv1a_64(data : Array[Int]) -> UInt64 {
  let mut h = 0xCBF29CE484222325UL
  for b in data {
    h = h ^ (b & 0xFF).to_uint64()
    h = h * 0x100000001B3UL
  }
  h
}

///|
/// 便捷入口：字符串按 UTF-8 编码后计算（与其他语言实现对齐）。
pub fn utf8_bytes(s : String) -> Array[Int] {
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
/// 摘要转小写十六进制串。
pub fn digest_hex(digest : Array[Int]) -> String {
  let digits = "0123456789abcdef"
  let sb = StringBuilder::new()
  for b in digest {
    let v = b & 0xFF
    sb.write_char(digits.get_char(v >> 4).unwrap())
    sb.write_char(digits.get_char(v & 0xF).unwrap())
  }
  sb.to_string()
}

///|
/// SHA-256 of UTF-8 字符串，十六进制输出（常用便捷组合）。
pub fn sha256_hex(s : String) -> String {
  digest_hex(sha256(utf8_bytes(s)))
}
