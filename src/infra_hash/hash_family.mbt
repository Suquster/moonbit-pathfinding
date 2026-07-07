// hash_family.mbt —— 哈希家族补全（对标业界标准库广度）。
//
// paper-to-code：
// - SHA-1：RFC 3174 / FIPS 180-4 §6.1——512 位分组、80 轮压缩、
//   Merkle–Damgård 填充（与 SHA-256 同构，逻辑函数 f/K 分四段）；
// - SHA-512：FIPS 180-4 §6.4——1024 位分组、80 轮、64 位字、
//   128 位长度域（此处消息长以 64 位表达，高 64 位恒 0）；
// - MD5：RFC 1321——512 位分组、64 步、4 轮非线性函数 F/G/H/I、
//   小端字序（校验/指纹用途；已知碰撞弱点，不作安全用途，文档声明）；
// - xxHash32：xxHash 规范（Yann Collet）seed 可调、5 个素数常量、
//   16 字节条带 + 尾部收敛 + 雪崩终混；
// - Adler-32：RFC 1950 §8.2（zlib 校验和）——模 65521 双累加器；
// - SipHash-2-4：Aumasson & Bernstein《SipHash: a fast short-input PRF》——
//   128 位密钥、2 轮压缩 + 4 轮终混，hashmap 抗 HashDoS 业界标准。
//
// 输入统一为字节数组（每元素 0..255）；纯计算、三后端逐位一致。

// ───────────────────────────── SHA-1（RFC 3174） ─────────────────────────

///|
/// 32 位循环左移。
fn rotl32(x : UInt, n : Int) -> UInt {
  (x << n) | (x >> (32 - n))
}

///|
/// SHA-1（RFC 3174 / FIPS 180-4 §6.1）：输入字节数组，输出 20 字节摘要。
/// 注：SHA-1 碰撞抗性已被攻破（SHAttered, 2017），仅供互操作/校验用途。
pub fn sha1(data : Array[Int]) -> Array[Int] {
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
  let h : Array[UInt] = [
    0x67452301U, 0xEFCDAB89U, 0x98BADCFEU, 0x10325476U, 0xC3D2E1F0U,
  ]
  let w : Array[UInt] = Array::make(80, 0U)
  let mut off = 0
  while off < msg.length() {
    for t in 0..<16 {
      let base = off + t * 4
      w[t] = (msg[base].reinterpret_as_uint() << 24) |
        (msg[base + 1].reinterpret_as_uint() << 16) |
        (msg[base + 2].reinterpret_as_uint() << 8) |
        msg[base + 3].reinterpret_as_uint()
    }
    for t in 16..<80 {
      w[t] = rotl32(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1)
    }
    let mut a = h[0]
    let mut b = h[1]
    let mut c = h[2]
    let mut d = h[3]
    let mut e = h[4]
    for t in 0..<80 {
      let (f, k) = if t < 20 {
        ((b & c) | (b.lnot() & d), 0x5A827999U)
      } else if t < 40 {
        (b ^ c ^ d, 0x6ED9EBA1U)
      } else if t < 60 {
        ((b & c) | (b & d) | (c & d), 0x8F1BBCDCU)
      } else {
        (b ^ c ^ d, 0xCA62C1D6U)
      }
      let tmp = rotl32(a, 5) + f + e + k + w[t]
      e = d
      d = c
      c = rotl32(b, 30)
      b = a
      a = tmp
    }
    h[0] = h[0] + a
    h[1] = h[1] + b
    h[2] = h[2] + c
    h[3] = h[3] + d
    h[4] = h[4] + e
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

// ───────────────────────────── SHA-512（FIPS 180-4 §6.4） ────────────────

///|
/// SHA-512 轮常量（前 80 个素数立方根小数部分，FIPS 180-4 §4.2.3）。
let sha512_k : Array[UInt64] = [
  0x428a2f98d728ae22UL, 0x7137449123ef65cdUL, 0xb5c0fbcfec4d3b2fUL, 0xe9b5dba58189dbbcUL,
  0x3956c25bf348b538UL, 0x59f111f1b605d019UL, 0x923f82a4af194f9bUL, 0xab1c5ed5da6d8118UL,
  0xd807aa98a3030242UL, 0x12835b0145706fbeUL, 0x243185be4ee4b28cUL, 0x550c7dc3d5ffb4e2UL,
  0x72be5d74f27b896fUL, 0x80deb1fe3b1696b1UL, 0x9bdc06a725c71235UL, 0xc19bf174cf692694UL,
  0xe49b69c19ef14ad2UL, 0xefbe4786384f25e3UL, 0x0fc19dc68b8cd5b5UL, 0x240ca1cc77ac9c65UL,
  0x2de92c6f592b0275UL, 0x4a7484aa6ea6e483UL, 0x5cb0a9dcbd41fbd4UL, 0x76f988da831153b5UL,
  0x983e5152ee66dfabUL, 0xa831c66d2db43210UL, 0xb00327c898fb213fUL, 0xbf597fc7beef0ee4UL,
  0xc6e00bf33da88fc2UL, 0xd5a79147930aa725UL, 0x06ca6351e003826fUL, 0x142929670a0e6e70UL,
  0x27b70a8546d22ffcUL, 0x2e1b21385c26c926UL, 0x4d2c6dfc5ac42aedUL, 0x53380d139d95b3dfUL,
  0x650a73548baf63deUL, 0x766a0abb3c77b2a8UL, 0x81c2c92e47edaee6UL, 0x92722c851482353bUL,
  0xa2bfe8a14cf10364UL, 0xa81a664bbc423001UL, 0xc24b8b70d0f89791UL, 0xc76c51a30654be30UL,
  0xd192e819d6ef5218UL, 0xd69906245565a910UL, 0xf40e35855771202aUL, 0x106aa07032bbd1b8UL,
  0x19a4c116b8d2d0c8UL, 0x1e376c085141ab53UL, 0x2748774cdf8eeb99UL, 0x34b0bcb5e19b48a8UL,
  0x391c0cb3c5c95a63UL, 0x4ed8aa4ae3418acbUL, 0x5b9cca4f7763e373UL, 0x682e6ff3d6b2b8a3UL,
  0x748f82ee5defb2fcUL, 0x78a5636f43172f60UL, 0x84c87814a1f0ab72UL, 0x8cc702081a6439ecUL,
  0x90befffa23631e28UL, 0xa4506cebde82bde9UL, 0xbef9a3f7b2c67915UL, 0xc67178f2e372532bUL,
  0xca273eceea26619cUL, 0xd186b8c721c0c207UL, 0xeada7dd6cde0eb1eUL, 0xf57d4f7fee6ed178UL,
  0x06f067aa72176fbaUL, 0x0a637dc5a2c898a6UL, 0x113f9804bef90daeUL, 0x1b710b35131c471bUL,
  0x28db77f523047d84UL, 0x32caab7b40c72493UL, 0x3c9ebe0a15c9bebcUL, 0x431d67c49c100d4cUL,
  0x4cc5d4becb3e42b6UL, 0x597f299cfc657e2aUL, 0x5fcb6fab3ad6faecUL, 0x6c44198c4a475817UL,
]

///|
/// 64 位循环右移。
fn rotr64(x : UInt64, n : Int) -> UInt64 {
  (x >> n) | (x << (64 - n))
}

///|
/// SHA-512（FIPS 180-4 §6.4）：输入字节数组，输出 64 字节摘要。
pub fn sha512(data : Array[Int]) -> Array[Int] {
  let msg : Array[Int] = []
  for b in data {
    msg.push(b & 0xFF)
  }
  let bit_len = data.length().to_int64() * 8L
  msg.push(0x80)
  while msg.length() % 128 != 112 {
    msg.push(0x00)
  }
  // 128 位长度域：高 64 位恒 0（消息长以 64 位比特数表达已远超实际需要）。
  for _ in 0..<8 {
    msg.push(0x00)
  }
  for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
    msg.push(((bit_len >> shift) & 0xFFL).to_int())
  }
  let h : Array[UInt64] = [
    0x6a09e667f3bcc908UL, 0xbb67ae8584caa73bUL, 0x3c6ef372fe94f82bUL, 0xa54ff53a5f1d36f1UL,
    0x510e527fade682d1UL, 0x9b05688c2b3e6c1fUL, 0x1f83d9abfb41bd6bUL, 0x5be0cd19137e2179UL,
  ]
  let w : Array[UInt64] = Array::make(80, 0UL)
  let mut off = 0
  while off < msg.length() {
    for t in 0..<16 {
      let base = off + t * 8
      let mut v = 0UL
      for j in 0..<8 {
        v = (v << 8) | (msg[base + j] & 0xFF).to_uint64()
      }
      w[t] = v
    }
    for t in 16..<80 {
      let s0 = rotr64(w[t - 15], 1) ^ rotr64(w[t - 15], 8) ^ (w[t - 15] >> 7)
      let s1 = rotr64(w[t - 2], 19) ^ rotr64(w[t - 2], 61) ^ (w[t - 2] >> 6)
      w[t] = w[t - 16] + s0 + w[t - 7] + s1
    }
    let mut a = h[0]
    let mut b = h[1]
    let mut c = h[2]
    let mut d = h[3]
    let mut e = h[4]
    let mut f = h[5]
    let mut g = h[6]
    let mut hh = h[7]
    for t in 0..<80 {
      let big_s1 = rotr64(e, 14) ^ rotr64(e, 18) ^ rotr64(e, 41)
      let ch = (e & f) ^ (e.lnot() & g)
      let t1 = hh + big_s1 + ch + sha512_k[t] + w[t]
      let big_s0 = rotr64(a, 28) ^ rotr64(a, 34) ^ rotr64(a, 39)
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
    off = off + 128
  }
  let out : Array[Int] = []
  for x in h {
    for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
      out.push(((x >> shift) & 0xFFUL).to_int())
    }
  }
  out
}

// ───────────────────────────── MD5（RFC 1321） ───────────────────────────

///|
/// MD5 每步循环左移位数表（RFC 1321 §3.4）。
let md5_s : Array[Int] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9,
  14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
]

///|
/// MD5 加法常量表 K[i] = floor(2^32 × |sin(i+1)|)（RFC 1321 §3.4）。
let md5_k : Array[UInt] = [
  0xd76aa478U, 0xe8c7b756U, 0x242070dbU, 0xc1bdceeeU, 0xf57c0fafU, 0x4787c62aU, 0xa8304613U,
  0xfd469501U, 0x698098d8U, 0x8b44f7afU, 0xffff5bb1U, 0x895cd7beU, 0x6b901122U, 0xfd987193U,
  0xa679438eU, 0x49b40821U, 0xf61e2562U, 0xc040b340U, 0x265e5a51U, 0xe9b6c7aaU, 0xd62f105dU,
  0x02441453U, 0xd8a1e681U, 0xe7d3fbc8U, 0x21e1cde6U, 0xc33707d6U, 0xf4d50d87U, 0x455a14edU,
  0xa9e3e905U, 0xfcefa3f8U, 0x676f02d9U, 0x8d2a4c8aU, 0xfffa3942U, 0x8771f681U, 0x6d9d6122U,
  0xfde5380cU, 0xa4beea44U, 0x4bdecfa9U, 0xf6bb4b60U, 0xbebfbc70U, 0x289b7ec6U, 0xeaa127faU,
  0xd4ef3085U, 0x04881d05U, 0xd9d4d039U, 0xe6db99e5U, 0x1fa27cf8U, 0xc4ac5665U, 0xf4292244U,
  0x432aff97U, 0xab9423a7U, 0xfc93a039U, 0x655b59c3U, 0x8f0ccc92U, 0xffeff47dU, 0x85845dd1U,
  0x6fa87e4fU, 0xfe2ce6e0U, 0xa3014314U, 0x4e0811a1U, 0xf7537e82U, 0xbd3af235U, 0x2ad7d2bbU,
  0xeb86d391U,
]

///|
/// MD5（RFC 1321）：输入字节数组，输出 16 字节摘要（小端字序）。
/// 注：MD5 碰撞早已被攻破，仅供指纹/互操作用途，不作安全用途。
pub fn md5(data : Array[Int]) -> Array[Int] {
  let msg : Array[Int] = []
  for b in data {
    msg.push(b & 0xFF)
  }
  let bit_len = data.length().to_int64() * 8L
  msg.push(0x80)
  while msg.length() % 64 != 56 {
    msg.push(0x00)
  }
  // 64 位小端比特长度。
  for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
    msg.push(((bit_len >> shift) & 0xFFL).to_int())
  }
  let mut a0 = 0x67452301U
  let mut b0 = 0xefcdab89U
  let mut c0 = 0x98badcfeU
  let mut d0 = 0x10325476U
  let m : Array[UInt] = Array::make(16, 0U)
  let mut off = 0
  while off < msg.length() {
    for j in 0..<16 {
      let base = off + j * 4
      m[j] = msg[base].reinterpret_as_uint() |
        (msg[base + 1].reinterpret_as_uint() << 8) |
        (msg[base + 2].reinterpret_as_uint() << 16) |
        (msg[base + 3].reinterpret_as_uint() << 24)
    }
    let mut a = a0
    let mut b = b0
    let mut c = c0
    let mut d = d0
    for i in 0..<64 {
      let (f, g) = if i < 16 {
        ((b & c) | (b.lnot() & d), i)
      } else if i < 32 {
        ((d & b) | (d.lnot() & c), (5 * i + 1) % 16)
      } else if i < 48 {
        (b ^ c ^ d, (3 * i + 5) % 16)
      } else {
        (c ^ (b | d.lnot()), 7 * i % 16)
      }
      let tmp = d
      d = c
      c = b
      b = b + rotl32(a + f + md5_k[i] + m[g], md5_s[i])
      a = tmp
    }
    a0 = a0 + a
    b0 = b0 + b
    c0 = c0 + c
    d0 = d0 + d
    off = off + 64
  }
  let out : Array[Int] = []
  for x in [a0, b0, c0, d0] {
    for shift in [0, 8, 16, 24] {
      out.push(((x >> shift) & 0xFFU).reinterpret_as_int())
    }
  }
  out
}

// ───────────────────────────── xxHash32 ──────────────────────────────────

///|
/// xxHash32 素数常量（xxHash 规范）。
let xxh_p1 : UInt = 0x9E3779B1U

///|
let xxh_p2 : UInt = 0x85EBCA77U

///|
let xxh_p3 : UInt = 0xC2B2AE3DU

///|
let xxh_p4 : UInt = 0x27D4EB2FU

///|
let xxh_p5 : UInt = 0x165667B1U

///|
/// 读小端 32 位字。
fn xxh_read32(data : Array[Int], off : Int) -> UInt {
  data[off].reinterpret_as_uint() |
  ((data[off + 1] & 0xFF).reinterpret_as_uint() << 8) |
  ((data[off + 2] & 0xFF).reinterpret_as_uint() << 16) |
  ((data[off + 3] & 0xFF).reinterpret_as_uint() << 24)
}

///|
/// xxHash32（Yann Collet 规范，seed 可调）：非加密快速哈希，
/// 官方测试向量对齐（xxhash.com sanity check）。
pub fn xxhash32(data : Array[Int], seed : UInt) -> UInt {
  let n = data.length()
  let mut h : UInt = 0U
  let mut i = 0
  if n >= 16 {
    let mut v1 = seed + xxh_p1 + xxh_p2
    let mut v2 = seed + xxh_p2
    let mut v3 = seed
    let mut v4 = seed - xxh_p1
    while i + 16 <= n {
      v1 = rotl32(v1 + xxh_read32(data, i) * xxh_p2, 13) * xxh_p1
      v2 = rotl32(v2 + xxh_read32(data, i + 4) * xxh_p2, 13) * xxh_p1
      v3 = rotl32(v3 + xxh_read32(data, i + 8) * xxh_p2, 13) * xxh_p1
      v4 = rotl32(v4 + xxh_read32(data, i + 12) * xxh_p2, 13) * xxh_p1
      i = i + 16
    }
    h = rotl32(v1, 1) + rotl32(v2, 7) + rotl32(v3, 12) + rotl32(v4, 18)
  } else {
    h = seed + xxh_p5
  }
  h = h + n.reinterpret_as_uint()
  while i + 4 <= n {
    h = rotl32(h + xxh_read32(data, i) * xxh_p3, 17) * xxh_p4
    i = i + 4
  }
  while i < n {
    h = rotl32(h + (data[i] & 0xFF).reinterpret_as_uint() * xxh_p5, 11) * xxh_p1
    i = i + 1
  }
  h = h ^ (h >> 15)
  h = h * xxh_p2
  h = h ^ (h >> 13)
  h = h * xxh_p3
  h = h ^ (h >> 16)
  h
}

// ───────────────────────────── Adler-32（RFC 1950） ──────────────────────

///|
/// Adler-32（RFC 1950 §8.2，zlib 校验和）：a、b 双累加器模 65521。
pub fn adler32(data : Array[Int]) -> UInt {
  let mut a = 1U
  let mut b = 0U
  for x in data {
    a = (a + (x & 0xFF).reinterpret_as_uint()) % 65521U
    b = (b + a) % 65521U
  }
  (b << 16) | a
}

// ───────────────────────────── SipHash-2-4 ───────────────────────────────

///|
/// SipRound（Aumasson & Bernstein）：v0..v3 的 ARX 置换。
fn sip_round(v : Array[UInt64]) -> Unit {
  v[0] = v[0] + v[1]
  v[1] = (v[1] << 13) | (v[1] >> 51)
  v[1] = v[1] ^ v[0]
  v[0] = (v[0] << 32) | (v[0] >> 32)
  v[2] = v[2] + v[3]
  v[3] = (v[3] << 16) | (v[3] >> 48)
  v[3] = v[3] ^ v[2]
  v[0] = v[0] + v[3]
  v[3] = (v[3] << 21) | (v[3] >> 43)
  v[3] = v[3] ^ v[0]
  v[2] = v[2] + v[1]
  v[1] = (v[1] << 17) | (v[1] >> 47)
  v[1] = v[1] ^ v[2]
  v[2] = (v[2] << 32) | (v[2] >> 32)
}

///|
/// SipHash-2-4（128 位密钥 k0/k1，64 位输出）：短输入 PRF，
/// hashmap 抗 HashDoS 业界标准（Rust/Python/Ruby 内建采用）。
pub fn siphash24(data : Array[Int], k0 : UInt64, k1 : UInt64) -> UInt64 {
  let v : Array[UInt64] = [
    0x736f6d6570736575UL ^ k0,
    0x646f72616e646f6dUL ^ k1,
    0x6c7967656e657261UL ^ k0,
    0x7465646279746573UL ^ k1,
  ]
  let n = data.length()
  let full = n / 8 * 8
  let mut i = 0
  while i < full {
    let mut m = 0UL
    for j in 0..<8 {
      m = m | ((data[i + j] & 0xFF).to_uint64() << (8 * j))
    }
    v[3] = v[3] ^ m
    sip_round(v)
    sip_round(v)
    v[0] = v[0] ^ m
    i = i + 8
  }
  // 尾块：剩余字节 + 最高字节放消息长度低 8 位。
  let mut tail = (n % 256).to_uint64() << 56
  for j in 0..<(n - full) {
    tail = tail | ((data[full + j] & 0xFF).to_uint64() << (8 * j))
  }
  v[3] = v[3] ^ tail
  sip_round(v)
  sip_round(v)
  v[0] = v[0] ^ tail
  v[2] = v[2] ^ 0xFFUL
  sip_round(v)
  sip_round(v)
  sip_round(v)
  sip_round(v)
  v[0] ^ v[1] ^ v[2] ^ v[3]
}

// ───────────────────────────── HMAC 家族补全 ─────────────────────────────

///|
/// 通用 HMAC 构造（RFC 2104）：给定分组长与哈希函数。
fn hmac_generic(
  key : Array[Int],
  message : Array[Int],
  block : Int,
  h : (Array[Int]) -> Array[Int],
) -> Array[Int] {
  let k0 : Array[Int] = []
  if key.length() > block {
    for b in h(key) {
      k0.push(b)
    }
  } else {
    for b in key {
      k0.push(b & 0xFF)
    }
  }
  while k0.length() < block {
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
  for b in h(inner) {
    outer.push(b)
  }
  h(outer)
}

///|
/// HMAC-SHA1（RFC 2104 + RFC 3174；分组 64 字节）。
pub fn hmac_sha1(key : Array[Int], message : Array[Int]) -> Array[Int] {
  hmac_generic(key, message, 64, sha1)
}

///|
/// HMAC-SHA512（RFC 2104 + FIPS 180-4；分组 128 字节）。
pub fn hmac_sha512(key : Array[Int], message : Array[Int]) -> Array[Int] {
  hmac_generic(key, message, 128, sha512)
}

///|
/// SHA-1 of UTF-8 字符串，十六进制输出。
pub fn sha1_hex(s : String) -> String {
  digest_hex(sha1(utf8_bytes(s)))
}

///|
/// SHA-512 of UTF-8 字符串，十六进制输出。
pub fn sha512_hex(s : String) -> String {
  digest_hex(sha512(utf8_bytes(s)))
}

///|
/// MD5 of UTF-8 字符串，十六进制输出。
pub fn md5_hex(s : String) -> String {
  digest_hex(md5(utf8_bytes(s)))
}
