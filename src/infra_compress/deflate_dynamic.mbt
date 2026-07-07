// deflate_dynamic.mbt —— 动态 Huffman 编码 + zlib 封装（B4 补深）。
//
// paper-to-code：
// - 动态 Huffman 块编码：RFC 1951 §3.2.7——LZ77 token 化后按符号频率构造
//   长度受限（≤15 位）Huffman 码；限长用「超长层层上折」的规范修正法
//   （与 zlib `gen_bitlen` 的溢出修正同思路）；码长序列再经 16/17/18
//   RLE（重复前值 / 短零串 / 长零串）+ 码长码（≤7 位）二级编码进块头；
// - 规范码分配：RFC 1951 §3.2.2 `next_code` 算法（与 inflate 侧同构）；
// - zlib 封装：RFC 1950——CMF/FLG 头（CM=8、FCHECK 使 (CMF<<8|FLG) 模 31
//   为 0）+ deflate 体 + Adler-32（大端）校验尾。
//
// 与既有 `deflate`（fixed Huffman）旁路共存：`deflate_dynamic` 产出
// 单个 BTYPE=10 final 块，既有 `inflate` 可直接解码（自内 roundtrip），
// 高频偏斜数据显著小于 fixed 编码。

// ───────────────────────────── LZ77 token 化 ─────────────────────────────

///|
/// LZ77 token：字面量或 (长度, 距离) 匹配。
priv enum LzToken {
  Lit(Int)
  Match(Int, Int) // (length 3..258, distance 1..32768)
}

///|
/// 与既有 `deflate` 相同的哈希链贪心匹配，但产出 token 序列（两遍编码需要
/// 先统计频率再定码）。
fn lz77_tokenize(data : Array[Int]) -> Array[LzToken] {
  let tokens : Array[LzToken] = []
  let n = data.length()
  let head : Array[Int] = Array::make(0x8000, -1)
  let prev : Array[Int] = Array::make(lz_window, -1)
  let mut i = 0
  while i < n {
    let mut best_len = 0
    let mut best_dist = 0
    if i + lz_min_match <= n {
      let h = lz_hash(data, i)
      let mut cand = head[h]
      let mut chain = 0
      let limit = if n - i < lz_max_match { n - i } else { lz_max_match }
      while cand >= 0 && i - cand <= lz_window && chain < lz_max_chain {
        let mut l = 0
        while l < limit && (data[cand + l] & 0xFF) == (data[i + l] & 0xFF) {
          l = l + 1
        }
        if l > best_len {
          best_len = l
          best_dist = i - cand
          if l == limit {
            break
          }
        }
        cand = prev[cand & (lz_window - 1)]
        chain = chain + 1
      }
    }
    if best_len >= lz_min_match {
      tokens.push(Match(best_len, best_dist))
      let end = i + best_len
      while i < end {
        if i + lz_min_match <= n {
          let h = lz_hash(data, i)
          prev[i & (lz_window - 1)] = head[h]
          head[h] = i
        }
        i = i + 1
      }
    } else {
      tokens.push(Lit(data[i] & 0xFF))
      if i + lz_min_match <= n {
        let h = lz_hash(data, i)
        prev[i & (lz_window - 1)] = head[h]
        head[h] = i
      }
      i = i + 1
    }
  }
  tokens
}

// ───────────────────────────── 限长 Huffman 码长 ─────────────────────────

///|
/// 由符号频率构造长度受限（≤ max_bits）Huffman 码长。
/// 经典两步：先建霍夫曼树得自然码长，超过 max_bits 的层层上折修正
/// （保持 Kraft 不等式 Σ2^-len ≤ 1，与 zlib gen_bitlen 同思路）。
/// 非零频符号 ≤ 1 时给 1 位码（DEFLATE 不允许 0 位码字）。
fn limited_huffman_lengths(freqs : Array[Int], max_bits : Int) -> Array[Int] {
  let n = freqs.length()
  let lens : Array[Int] = Array::make(n, 0)
  // 收集活跃符号。
  let active : Array[Int] = []
  for s in 0..<n {
    if freqs[s] > 0 {
      active.push(s)
    }
  }
  if active.length() == 0 {
    return lens
  }
  if active.length() == 1 {
    lens[active[0]] = 1
    return lens
  }
  // 朴素 O(k²) 霍夫曼合并（k ≤ 288，规模可控）：
  // node = (weight, 由哪些符号组成)。每个符号深度 = 参与合并次数。
  let weights : Array[Int] = []
  let members : Array[Array[Int]] = []
  for s in active {
    weights.push(freqs[s])
    members.push([s])
  }
  let alive : Array[Bool] = Array::make(weights.length() * 2, true)
  let mut count = weights.length()
  while count > 1 {
    // 找最小两个活节点。
    let mut a = -1
    let mut b = -1
    for j in 0..<weights.length() {
      if !alive[j] {
        continue
      }
      if a < 0 || weights[j] < weights[a] {
        b = a
        a = j
      } else if b < 0 || weights[j] < weights[b] {
        b = j
      }
    }
    // 合并 a、b：成员深度 +1。
    let merged : Array[Int] = []
    for s in members[a] {
      lens[s] = lens[s] + 1
      merged.push(s)
    }
    for s in members[b] {
      lens[s] = lens[s] + 1
      merged.push(s)
    }
    alive[a] = false
    alive[b] = false
    weights.push(weights[a] + weights[b])
    members.push(merged)
    alive[weights.length() - 1] = true
    count = count - 1
  }
  // 限长修正：把超长码折到 max_bits，再自底向上恢复 Kraft 等式。
  let bl_count : Array[Int] = Array::make(max_bits + 1, 0)
  let mut overflow = 0
  for s in 0..<n {
    if lens[s] > max_bits {
      overflow = overflow + 1
      lens[s] = max_bits
    }
  }
  for s in 0..<n {
    if lens[s] > 0 {
      bl_count[lens[s]] = bl_count[lens[s]] + 1
    }
  }
  while overflow > 0 {
    // 找最深的非满层 < max_bits，把一个码下移一层腾出空间。
    let mut bits = max_bits - 1
    while bl_count[bits] == 0 {
      bits = bits - 1
    }
    bl_count[bits] = bl_count[bits] - 1
    bl_count[bits + 1] = bl_count[bits + 1] + 2
    bl_count[max_bits] = bl_count[max_bits] - 1
    overflow = overflow - 2
  }
  // 按频率升序把码长重新分配给活跃符号（长码给低频）。
  // 排序活跃符号：频率升序、符号升序（确定性）。
  let order : Array[Int] = []
  for s in active {
    order.push(s)
  }
  // 插入排序（k 小）。
  for x in 1..<order.length() {
    let key = order[x]
    let mut y = x - 1
    while y >= 0 &&
          (
            freqs[order[y]] > freqs[key] ||
            (freqs[order[y]] == freqs[key] && order[y] > key)
          ) {
      order[y + 1] = order[y]
      y = y - 1
    }
    order[y + 1] = key
  }
  let mut idx = 0
  let mut bits = max_bits
  while bits >= 1 {
    for _ in 0..<bl_count[bits] {
      lens[order[idx]] = bits
      idx = idx + 1
    }
    bits = bits - 1
  }
  lens
}

///|
/// 规范码分配（RFC 1951 §3.2.2 next_code）：由码长得码字。
fn assign_codes(lens : Array[Int], max_bits : Int) -> Array[Int] {
  let bl_count : Array[Int] = Array::make(max_bits + 1, 0)
  for l in lens {
    if l > 0 {
      bl_count[l] = bl_count[l] + 1
    }
  }
  let next_code : Array[Int] = Array::make(max_bits + 1, 0)
  let mut code = 0
  for bits in 1..<=max_bits {
    code = (code + bl_count[bits - 1]) << 1
    next_code[bits] = code
  }
  let codes : Array[Int] = Array::make(lens.length(), 0)
  for s in 0..<lens.length() {
    if lens[s] > 0 {
      codes[s] = next_code[lens[s]]
      next_code[lens[s]] = next_code[lens[s]] + 1
    }
  }
  codes
}

// ───────────────────────────── 码长序列 RLE（§3.2.7） ────────────────────

///|
/// 码长码字母表的置换序（RFC 1951 §3.2.7）。
let clc_order : Array[Int] = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
]

///|
/// 码长序列 → (符号, 额外位值, 额外位数) RLE 流：
/// 16=重复前值 3..6 次、17=零串 3..10、18=零串 11..138。
fn rle_code_lengths(lens : Array[Int]) -> Array[(Int, Int, Int)] {
  let out : Array[(Int, Int, Int)] = []
  let n = lens.length()
  let mut i = 0
  while i < n {
    let v = lens[i]
    let mut run = 1
    while i + run < n && lens[i + run] == v {
      run = run + 1
    }
    if v == 0 {
      let mut rest = run
      while rest >= 11 {
        let take = if rest > 138 { 138 } else { rest }
        out.push((18, take - 11, 7))
        rest = rest - take
      }
      if rest >= 3 {
        out.push((17, rest - 3, 3))
        rest = 0
      }
      for _ in 0..<rest {
        out.push((0, 0, 0))
      }
    } else {
      out.push((v, 0, 0))
      let mut rest = run - 1
      while rest >= 3 {
        let take = if rest > 6 { 6 } else { rest }
        out.push((16, take - 3, 2))
        rest = rest - take
      }
      for _ in 0..<rest {
        out.push((v, 0, 0))
      }
    }
    i = i + run
  }
  out
}

// ───────────────────────────── 动态块编码主流程 ──────────────────────────

///|
/// 压缩为 raw DEFLATE 流（单个 dynamic Huffman final 块，BTYPE=10）。
/// 两遍：先 LZ77 token 化统计频率，再按频率定制码表编码；
/// 高频偏斜数据显著小于 `deflate`（fixed 码表）。
pub fn deflate_dynamic(data : Array[Int]) -> Array[Int] {
  let tokens = lz77_tokenize(data)
  // 频率统计（literal/length 288 符号 + distance 30 符号）。
  let lit_freq : Array[Int] = Array::make(288, 0)
  let dist_freq : Array[Int] = Array::make(30, 0)
  for t in tokens {
    match t {
      Lit(b) => lit_freq[b] = lit_freq[b] + 1
      Match(len, dist) => {
        let (lsym, _, _) = length_symbol(len)
        lit_freq[lsym] = lit_freq[lsym] + 1
        let (dsym, _, _) = dist_symbol(dist)
        dist_freq[dsym] = dist_freq[dsym] + 1
      }
    }
  }
  lit_freq[256] = lit_freq[256] + 1 // EOB 必现
  // 距离表全空时补一个 1 位哑码（RFC 允许 HDIST 最少 1 个码长）。
  let lit_lens = limited_huffman_lengths(lit_freq, 15)
  let dist_lens = limited_huffman_lengths(dist_freq, 15)
  let mut dist_used = false
  for l in dist_lens {
    if l > 0 {
      dist_used = true
      break
    }
  }
  if !dist_used {
    dist_lens[0] = 1
  }
  let lit_codes = assign_codes(lit_lens, 15)
  let dist_codes = assign_codes(dist_lens, 15)
  // HLIT / HDIST：截去尾部零码长。
  let mut hlit = 288
  while hlit > 257 && lit_lens[hlit - 1] == 0 {
    hlit = hlit - 1
  }
  let mut hdist = 30
  while hdist > 1 && dist_lens[hdist - 1] == 0 {
    hdist = hdist - 1
  }
  // 合并码长序列做 RLE，统计码长码频率。
  let combined : Array[Int] = []
  for s in 0..<hlit {
    combined.push(lit_lens[s])
  }
  for s in 0..<hdist {
    combined.push(dist_lens[s])
  }
  let rle = rle_code_lengths(combined)
  let clc_freq : Array[Int] = Array::make(19, 0)
  for e in rle {
    clc_freq[e.0] = clc_freq[e.0] + 1
  }
  let clc_lens = limited_huffman_lengths(clc_freq, 7)
  let clc_codes = assign_codes(clc_lens, 7)
  // HCLEN：按置换序截尾。
  let mut hclen = 19
  while hclen > 4 && clc_lens[clc_order[hclen - 1]] == 0 {
    hclen = hclen - 1
  }
  // ── 写块 ──
  let bw = BitWriter::new()
  bw.put(1, 1) // BFINAL
  bw.put(2, 2) // BTYPE=10
  bw.put(hlit - 257, 5)
  bw.put(hdist - 1, 5)
  bw.put(hclen - 4, 4)
  for k in 0..<hclen {
    bw.put(clc_lens[clc_order[k]], 3)
  }
  for e in rle {
    bw.put_huff(clc_codes[e.0], clc_lens[e.0])
    if e.2 > 0 {
      bw.put(e.1, e.2)
    }
  }
  // token 流。
  for t in tokens {
    match t {
      Lit(b) => bw.put_huff(lit_codes[b], lit_lens[b])
      Match(len, dist) => {
        let (lsym, lextra, lbits) = length_symbol(len)
        bw.put_huff(lit_codes[lsym], lit_lens[lsym])
        if lbits > 0 {
          bw.put(lextra, lbits)
        }
        let (dsym, dextra, dbits) = dist_symbol(dist)
        bw.put_huff(dist_codes[dsym], dist_lens[dsym])
        if dbits > 0 {
          bw.put(dextra, dbits)
        }
      }
    }
  }
  bw.put_huff(lit_codes[256], lit_lens[256]) // EOB
  bw.flush()
  bw.out
}

// ───────────────────────────── zlib 封装（RFC 1950） ─────────────────────

///|
/// zlib 压缩：CMF/FLG 头 + 动态 Huffman deflate 体 + Adler-32（大端）。
/// CMF=0x78（CM=8, CINFO=7：32K 窗口）；FCHECK 使 (CMF<<8|FLG) ≡ 0 (mod 31)。
pub fn zlib_compress(data : Array[Int]) -> Array[Int] {
  let cmf = 0x78
  let mut flg = 0 // FLEVEL=0、FDICT=0
  let rem = (cmf * 256 + flg) % 31
  if rem != 0 {
    flg = flg + (31 - rem)
  }
  let out : Array[Int] = [cmf, flg]
  for b in deflate_dynamic(data) {
    out.push(b)
  }
  let adler = @infra_hash.adler32(data)
  for shift in [24, 16, 8, 0] {
    out.push(((adler >> shift) & 0xFFU).reinterpret_as_int())
  }
  out
}

///|
/// zlib 解压：校验 CMF/FLG（CM=8、FCHECK、不支持 FDICT）、解 deflate 体、
/// 核对 Adler-32；任一不符返回 None。
pub fn zlib_decompress(data : Array[Int]) -> Array[Int]? {
  if data.length() < 6 {
    return None
  }
  let cmf = data[0] & 0xFF
  let flg = data[1] & 0xFF
  if (cmf & 0x0F) != 8 {
    return None // CM 必须是 deflate
  }
  if (cmf * 256 + flg) % 31 != 0 {
    return None // FCHECK
  }
  if (flg & 0x20) != 0 {
    return None // FDICT 不支持
  }
  let body : Array[Int] = []
  for i in 2..<(data.length() - 4) {
    body.push(data[i])
  }
  guard inflate(body) is Some(raw) else { return None }
  let mut expected = 0U
  for i in (data.length() - 4)..<data.length() {
    expected = (expected << 8) | (data[i] & 0xFF).reinterpret_as_uint()
  }
  if @infra_hash.adler32(raw) != expected {
    return None
  }
  Some(raw)
}
