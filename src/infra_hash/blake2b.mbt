// blake2b.mbt —— BLAKE2b（RFC 7693）。
//
// paper-to-code：RFC 7693 *The BLAKE2 Cryptographic Hash and MAC*：
// - 12 轮压缩函数 F（§3.2）：G 函数（§3.1）按 SIGMA 消息调度表
//   （§2.7）对 4×4 工作向量做列步/对角步混合；
// - 参数块（§2.5）：摘要长度与密钥长度异或进 h[0]
//   （h[0] ^= 0x01010000 ^ (kk<<8) ^ nn）；
// - 计数器 t 为已压缩字节数（含当前块），末块 f0 = ~0；
// - 支持 keyed 模式（§2.9）：密钥填充为完整首块。
//
// 测试向量：RFC 7693 附录 A（"abc" 的 BLAKE2b-512）+
// CPython hashlib.blake2b 派生向量。

///|
/// BLAKE2b 初始向量（= SHA-512 IV，RFC 7693 §2.6）。
let blake2b_iv : Array[UInt64] = [
  0x6a09e667f3bcc908UL, 0xbb67ae8584caa73bUL, 0x3c6ef372fe94f82bUL, 0xa54ff53a5f1d36f1UL,
  0x510e527fade682d1UL, 0x9b05688c2b3e6c1fUL, 0x1f83d9abfb41bd6bUL, 0x5be0cd19137e2179UL,
]

///|
/// 消息调度表 SIGMA（RFC 7693 §2.7；10 行循环使用，12 轮取 round % 10）。
let blake2b_sigma : Array[Array[Int]] = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
]

///|
/// 64 位循环右移（BLAKE2b 使用右旋 32/24/16/63）。
fn b2_rotr64(x : UInt64, n : Int) -> UInt64 {
  (x >> n) | (x << (64 - n))
}

///|
/// G 混合函数（RFC 7693 §3.1）。
fn blake2b_g(
  v : Array[UInt64],
  a : Int,
  b : Int,
  c : Int,
  d : Int,
  x : UInt64,
  y : UInt64,
) -> Unit {
  v[a] = v[a] + v[b] + x
  v[d] = b2_rotr64(v[d] ^ v[a], 32)
  v[c] = v[c] + v[d]
  v[b] = b2_rotr64(v[b] ^ v[c], 24)
  v[a] = v[a] + v[b] + y
  v[d] = b2_rotr64(v[d] ^ v[a], 16)
  v[c] = v[c] + v[d]
  v[b] = b2_rotr64(v[b] ^ v[c], 63)
}

///|
/// 压缩函数 F（RFC 7693 §3.2）：`block` 为 128 字节、`t` 为累计字节计数、
/// `last` 标记末块。
fn blake2b_compress(
  h : Array[UInt64],
  block : Array[Int],
  t : UInt64,
  last : Bool,
) -> Unit {
  let m : Array[UInt64] = Array::make(16, 0UL)
  for i in 0..<16 {
    let mut w = 0UL
    for j in 0..<8 {
      w = w | ((block[i * 8 + j] & 0xFF).to_uint64() << (j * 8))
    }
    m[i] = w
  }
  let v : Array[UInt64] = Array::make(16, 0UL)
  for i in 0..<8 {
    v[i] = h[i]
    v[i + 8] = blake2b_iv[i]
  }
  v[12] = v[12] ^ t // 计数低 64 位
  // v[13] ^= t_hi：输入长以 64 位计数覆盖，恒 0。
  if last {
    v[14] = v[14].lnot()
  }
  for round in 0..<12 {
    let s = blake2b_sigma[round % 10]
    blake2b_g(v, 0, 4, 8, 12, m[s[0]], m[s[1]])
    blake2b_g(v, 1, 5, 9, 13, m[s[2]], m[s[3]])
    blake2b_g(v, 2, 6, 10, 14, m[s[4]], m[s[5]])
    blake2b_g(v, 3, 7, 11, 15, m[s[6]], m[s[7]])
    blake2b_g(v, 0, 5, 10, 15, m[s[8]], m[s[9]])
    blake2b_g(v, 1, 6, 11, 12, m[s[10]], m[s[11]])
    blake2b_g(v, 2, 7, 8, 13, m[s[12]], m[s[13]])
    blake2b_g(v, 3, 4, 9, 14, m[s[14]], m[s[15]])
  }
  for i in 0..<8 {
    h[i] = h[i] ^ v[i] ^ v[i + 8]
  }
}

///|
/// BLAKE2b（RFC 7693）：`out_len` 1..64 字节、可选 `key`（0..64 字节，
/// keyed-MAC 模式）。参数非法返回空数组（总体函数，不 panic）。
pub fn blake2b(
  data : Array[Int],
  out_len? : Int = 64,
  key? : Array[Int] = [],
) -> Array[Int] {
  if out_len < 1 || out_len > 64 || key.length() > 64 {
    return []
  }
  let h : Array[UInt64] = []
  for x in blake2b_iv {
    h.push(x)
  }
  // 参数块（sequential 模式）：depth=1、fanout=1。
  h[0] = h[0] ^
    0x01010000UL ^
    (key.length().to_uint64() << 8) ^
    out_len.to_uint64()
  let mut t = 0UL
  // keyed 模式：密钥填满 128 字节作为首块。
  let blocks : Array[Int] = []
  if key.length() > 0 {
    for b in key {
      blocks.push(b & 0xFF)
    }
    while blocks.length() < 128 {
      blocks.push(0)
    }
  }
  for b in data {
    blocks.push(b & 0xFF)
  }
  let total = blocks.length()
  // 空消息（且无密钥）也要压缩一个全零末块。
  if total == 0 {
    let zero : Array[Int] = Array::make(128, 0)
    blake2b_compress(h, zero, 0UL, true)
  } else {
    let mut off = 0
    while off < total {
      let remaining = total - off
      if remaining > 128 {
        let block : Array[Int] = []
        for i in 0..<128 {
          block.push(blocks[off + i])
        }
        t = t + 128UL
        blake2b_compress(h, block, t, false)
        off = off + 128
      } else {
        let block : Array[Int] = Array::make(128, 0)
        for i in 0..<remaining {
          block[i] = blocks[off + i]
        }
        t = t + remaining.to_uint64()
        blake2b_compress(h, block, t, true)
        off = total
      }
    }
  }
  let out : Array[Int] = []
  for i in 0..<out_len {
    out.push(((h[i / 8] >> (i % 8 * 8)) & 0xFFUL).to_int())
  }
  out
}

///|
/// BLAKE2b-512 of UTF-8 字符串，十六进制输出。
pub fn blake2b_hex(s : String) -> String {
  digest_hex(blake2b(utf8_bytes(s)))
}
