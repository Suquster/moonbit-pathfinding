// kdf.mbt —— 密钥派生函数族（infra_hash 补深第二轮）。
//
// paper-to-code：
// - HKDF（RFC 5869，Krawczyk 2010）：extract-then-expand 两段式——
//   `HKDF-Extract(salt, IKM) = HMAC(salt, IKM)` 得 PRK，
//   `HKDF-Expand(PRK, info, L)` 以 `T(i) = HMAC(PRK, T(i-1) ‖ info ‖ i)`
//   级联展开至 L 字节（i 为单字节计数器，L ≤ 255×HashLen）；
// - PBKDF2（RFC 8018 §5.2）：`F = U1 ⊕ U2 ⊕ … ⊕ Uc`，
//   `U1 = PRF(P, S ‖ INT(i))`、`Uj = PRF(P, Uj-1)`，块序号大端 4 字节；
//   PRF 用 HMAC-SHA256（RFC 7914 §11 提供官方向量）。
//
// 全部纯函数、字节数组进出，与既有 hmac_sha256/hmac_sha1 直接组合。

///|
/// HKDF-Extract（RFC 5869 §2.2）：salt 为空时按规范用 HashLen 个零字节。
pub fn hkdf_extract(salt : Array[Int], ikm : Array[Int]) -> Array[Int] {
  let key = if salt.length() == 0 {
    let zeros : Array[Int] = Array::make(32, 0)
    zeros
  } else {
    salt
  }
  hmac_sha256(key, ikm)
}

///|
/// HKDF-Expand（RFC 5869 §2.3）：展开 PRK 至 length 字节；
/// length > 255×32 违反规范返回 None。
pub fn hkdf_expand(
  prk : Array[Int],
  info : Array[Int],
  length : Int,
) -> Array[Int]? {
  if length < 0 || length > 255 * 32 {
    return None
  }
  let out : Array[Int] = []
  let mut t : Array[Int] = []
  let mut counter = 1
  while out.length() < length {
    let block : Array[Int] = []
    for b in t {
      block.push(b)
    }
    for b in info {
      block.push(b)
    }
    block.push(counter)
    t = hmac_sha256(prk, block)
    for b in t {
      if out.length() < length {
        out.push(b)
      }
    }
    counter = counter + 1
  }
  Some(out)
}

///|
/// HKDF 一步式（extract + expand）。
pub fn hkdf(
  salt : Array[Int],
  ikm : Array[Int],
  info : Array[Int],
  length : Int,
) -> Array[Int]? {
  hkdf_expand(hkdf_extract(salt, ikm), info, length)
}

///|
/// PBKDF2-HMAC-SHA256（RFC 8018 §5.2）：iterations ≥ 1、
/// dk_len ≤ (2³²−1)×32（实用域内直接钳制为正数校验）。
pub fn pbkdf2_hmac_sha256(
  password : Array[Int],
  salt : Array[Int],
  iterations : Int,
  dk_len : Int,
) -> Array[Int]? {
  if iterations < 1 || dk_len < 1 {
    return None
  }
  let out : Array[Int] = []
  let mut block_idx = 1
  while out.length() < dk_len {
    // U1 = HMAC(P, S ‖ INT_BE(block_idx))
    let s : Array[Int] = []
    for b in salt {
      s.push(b)
    }
    s.push((block_idx >> 24) & 0xFF)
    s.push((block_idx >> 16) & 0xFF)
    s.push((block_idx >> 8) & 0xFF)
    s.push(block_idx & 0xFF)
    let mut u = hmac_sha256(password, s)
    let acc : Array[Int] = []
    for b in u {
      acc.push(b)
    }
    for _ in 1..<iterations {
      u = hmac_sha256(password, u)
      for k in 0..<acc.length() {
        acc[k] = acc[k] ^ u[k]
      }
    }
    for b in acc {
      if out.length() < dk_len {
        out.push(b)
      }
    }
    block_idx = block_idx + 1
  }
  Some(out)
}
