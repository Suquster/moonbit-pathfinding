// sha3.mbt —— SHA-3 家族（FIPS 202）。
//
// paper-to-code：NIST FIPS 202 *SHA-3 Standard: Permutation-Based Hash and
// Extendable-Output Functions*：
// - Keccak-f[1600] 置换：24 轮 θ/ρ/π/χ/ι 五步（§3.2–§3.4），
//   状态为 5×5 的 64 位 lane（小端字节序，§B.1）；
// - 海绵结构（§4）：吸收阶段按 rate 分组异或进状态，挤出阶段截取输出；
// - SHA3-d 域分隔后缀 `01`（pad10*1 前）：吸收尾字节 0x06、rate 末字节 0x80
//   （§B.2 padding 合并写法）；
// - 各档 rate：SHA3-224=144、SHA3-256=136、SHA3-384=104、SHA3-512=72 字节。
//
// 测试向量：NIST FIPS 202 示例值（空串与 "abc" 的标准摘要，
// 与 CPython hashlib.sha3_256/sha3_512 输出一致）。

///|
/// Keccak-f[1600] 轮常量 RC[0..23]（FIPS 202 §3.2.5，由 LFSR rc(t) 生成）。
let keccak_rc : Array[UInt64] = [
  0x0000000000000001UL, 0x0000000000008082UL, 0x800000000000808aUL, 0x8000000080008000UL,
  0x000000000000808bUL, 0x0000000080000001UL, 0x8000000080008081UL, 0x8000000000008009UL,
  0x000000000000008aUL, 0x0000000000000088UL, 0x0000000080008009UL, 0x000000008000000aUL,
  0x000000008000808bUL, 0x800000000000008bUL, 0x8000000000008089UL, 0x8000000000008003UL,
  0x8000000000008002UL, 0x8000000000000080UL, 0x000000000000800aUL, 0x800000008000000aUL,
  0x8000000080008081UL, 0x8000000000008080UL, 0x0000000080000001UL, 0x8000000080008008UL,
]

///|
/// ρ 步各 lane 的循环左移位数（FIPS 202 表 2，按 x + 5y 索引）。
let keccak_rho : Array[Int] = [
  0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18,
  2, 61, 56, 14,
]

///|
/// 64 位循环左移。
fn rotl64(x : UInt64, n : Int) -> UInt64 {
  if n == 0 {
    x
  } else {
    (x << n) | (x >> (64 - n))
  }
}

///|
/// Keccak-f[1600] 置换：24 轮 θ→ρ→π→χ→ι（原地更新 25 lane 状态）。
fn keccak_f(st : Array[UInt64]) -> Unit {
  let bc : Array[UInt64] = Array::make(5, 0UL)
  for round in 0..<24 {
    // θ：列奇偶校验扩散。
    for x in 0..<5 {
      bc[x] = st[x] ^ st[x + 5] ^ st[x + 10] ^ st[x + 15] ^ st[x + 20]
    }
    for x in 0..<5 {
      let t = bc[(x + 4) % 5] ^ rotl64(bc[(x + 1) % 5], 1)
      for y in 0..<5 {
        st[x + 5 * y] = st[x + 5 * y] ^ t
      }
    }
    // ρ + π：lane 旋转与位置换（合并实施，FIPS 202 §3.2.2–3.2.3）。
    let tmp : Array[UInt64] = Array::make(25, 0UL)
    for x in 0..<5 {
      for y in 0..<5 {
        let idx = x + 5 * y
        // π: (x, y) → (y, 2x+3y mod 5)。
        let nx = y
        let ny = (2 * x + 3 * y) % 5
        tmp[nx + 5 * ny] = rotl64(st[idx], keccak_rho[idx])
      }
    }
    // χ：行内非线性。
    for y in 0..<5 {
      for x in 0..<5 {
        st[x + 5 * y] = tmp[x + 5 * y] ^
          (tmp[(x + 1) % 5 + 5 * y].lnot() & tmp[(x + 2) % 5 + 5 * y])
      }
    }
    // ι：轮常量注入。
    st[0] = st[0] ^ keccak_rc[round]
  }
}

///|
/// SHA-3 海绵（吸收 + 挤出）：`rate` 为分组字节数、`out_len` 为输出字节数，
/// 域分隔 + pad10*1 按 SHA-3 定形后缀 0x06 / 0x80 实施。
fn sha3_sponge(data : Array[Int], rate : Int, out_len : Int) -> Array[Int] {
  let st : Array[UInt64] = Array::make(25, 0UL)
  // 吸收整块。
  let n = data.length()
  let mut off = 0
  while n - off >= rate {
    for i in 0..<rate {
      let lane = i / 8
      let shift = i % 8 * 8
      st[lane] = st[lane] ^ ((data[off + i] & 0xFF).to_uint64() << shift)
    }
    keccak_f(st)
    off = off + rate
  }
  // 末块：残余 + 0x06 后缀 + rate-1 处 0x80（pad10*1）。
  let block : Array[Int] = Array::make(rate, 0)
  for i in off..<n {
    block[i - off] = data[i] & 0xFF
  }
  block[n - off] = block[n - off] | 0x06
  block[rate - 1] = block[rate - 1] | 0x80
  for i in 0..<rate {
    let lane = i / 8
    let shift = i % 8 * 8
    st[lane] = st[lane] ^ ((block[i] & 0xFF).to_uint64() << shift)
  }
  keccak_f(st)
  // 挤出（SHA-3 固定输出各档均 ≤ rate，单次挤出即可；写成循环以备扩展）。
  let out : Array[Int] = []
  let mut produced = 0
  while produced < out_len {
    let take = if out_len - produced < rate { out_len - produced } else { rate }
    for i in 0..<take {
      let lane = i / 8
      let shift = i % 8 * 8
      out.push(((st[lane] >> shift) & 0xFFUL).to_int())
    }
    produced = produced + take
    if produced < out_len {
      keccak_f(st)
    }
  }
  out
}

///|
/// SHA3-224（FIPS 202）：rate 144 字节，输出 28 字节。
pub fn sha3_224(data : Array[Int]) -> Array[Int] {
  sha3_sponge(data, 144, 28)
}

///|
/// SHA3-256（FIPS 202）：rate 136 字节，输出 32 字节。
pub fn sha3_256(data : Array[Int]) -> Array[Int] {
  sha3_sponge(data, 136, 32)
}

///|
/// SHA3-384（FIPS 202）：rate 104 字节，输出 48 字节。
pub fn sha3_384(data : Array[Int]) -> Array[Int] {
  sha3_sponge(data, 104, 48)
}

///|
/// SHA3-512（FIPS 202）：rate 72 字节，输出 64 字节。
pub fn sha3_512(data : Array[Int]) -> Array[Int] {
  sha3_sponge(data, 72, 64)
}

///|
/// SHA3-256 of UTF-8 字符串，十六进制输出。
pub fn sha3_256_hex(s : String) -> String {
  digest_hex(sha3_256(utf8_bytes(s)))
}

///|
/// SHA3-512 of UTF-8 字符串，十六进制输出。
pub fn sha3_512_hex(s : String) -> String {
  digest_hex(sha3_512(utf8_bytes(s)))
}
