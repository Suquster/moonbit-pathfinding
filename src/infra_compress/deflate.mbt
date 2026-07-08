// deflate.mbt —— DEFLATE（RFC 1951）与 gzip（RFC 1952）。
//
// paper-to-code：
// - inflate：RFC 1951 §3.2——三种块（BTYPE=00 stored / 01 fixed Huffman /
//   10 dynamic Huffman）全支持；规范 Huffman 码按 §3.2.2 由码长序列构造
//   （码长计数 → 各长度首码 → 顺序编号）；长度/距离符号的基数+额外位
//   查表见 §3.2.5；码长字母表 16/17/18 重复编码见 §3.2.7；
// - deflate 压缩：LZ77 哈希链匹配（3 字节哈希头 + 链式回溯，贪心取最长
//   匹配，窗口 32 KiB、匹配长 3..258）+ fixed Huffman 块编码（§3.2.6）；
// - gzip：RFC 1952——魔数 1F 8B、CM=8、FLG（FEXTRA/FNAME/FCOMMENT/FHCRC
//   跳过解析）、尾部 CRC-32 与 ISIZE（模 2^32 原始长度）校验。
//
// 输入输出统一为字节数组（每元素 0..255）；解码总体函数不 panic，
// 畸形输入返回 None。

// ---------------------------------------------------------------------------
// 位流读取器（LSB-first，RFC 1951 §3.1.1）
// ---------------------------------------------------------------------------

///|
/// LSB-first 位流读取器。
priv struct BitReader {
  data : Array[Int]
  mut pos : Int // 下一字节下标
  mut bit_buf : Int // 位缓冲
  mut bit_cnt : Int // 缓冲中的位数
}

///|
fn BitReader::new(data : Array[Int]) -> BitReader {
  { data, pos: 0, bit_buf: 0, bit_cnt: 0 }
}

///|
/// 读 n 位（n <= 24）；越界返回 -1。
fn BitReader::take(self : BitReader, n : Int) -> Int {
  while self.bit_cnt < n {
    if self.pos >= self.data.length() {
      return -1
    }
    self.bit_buf = self.bit_buf | ((self.data[self.pos] & 0xFF) << self.bit_cnt)
    self.pos = self.pos + 1
    self.bit_cnt = self.bit_cnt + 8
  }
  let v = self.bit_buf & ((1 << n) - 1)
  self.bit_buf = self.bit_buf >> n
  self.bit_cnt = self.bit_cnt - n
  v
}

///|
/// 丢弃到字节边界（stored 块前，§3.2.4）。
fn BitReader::align_byte(self : BitReader) -> Unit {
  self.bit_buf = 0
  self.bit_cnt = 0
}

// ---------------------------------------------------------------------------
// 规范 Huffman 解码表（RFC 1951 §3.2.2）
// ---------------------------------------------------------------------------

///|
/// 规范 Huffman 解码表：按码长分组存符号。
priv struct HuffTable {
  // counts[len] = 码长为 len 的符号数（len 1..15）
  counts : Array[Int]
  // 按（码长升序、符号升序）排列的符号表
  symbols : Array[Int]
}

///|
/// 由码长序列构造规范 Huffman 表；全零或过订阅（over-subscribed）返回 None。
fn huff_build(lengths : Array[Int]) -> HuffTable? {
  let counts : Array[Int] = Array::make(16, 0)
  for l in lengths {
    if l < 0 || l > 15 {
      return None
    }
    counts[l] = counts[l] + 1
  }
  if counts[0] == lengths.length() {
    return None // 没有任何符号
  }
  // Kraft 不等式检查：不允许过订阅。
  let mut left = 1
  for len in 1..<16 {
    left = left * 2 - counts[len]
    if left < 0 {
      return None
    }
  }
  // offsets[len] = 码长 len 的符号在 symbols 中的起始下标。
  let offsets : Array[Int] = Array::make(16, 0)
  for len in 1..<15 {
    offsets[len + 1] = offsets[len] + counts[len]
  }
  let total = offsets[15] + counts[15]
  let symbols : Array[Int] = Array::make(total, 0)
  for sym in 0..<lengths.length() {
    let l = lengths[sym]
    if l != 0 {
      symbols[offsets[l]] = sym
      offsets[l] = offsets[l] + 1
    }
  }
  Some({ counts, symbols })
}

///|
/// 从位流按规范序解一个符号（逐位延长前缀，Mark Adler puff.c 同构算法）；
/// 位流耗尽或码字非法返回 -1。
fn huff_decode(br : BitReader, table : HuffTable) -> Int {
  let mut code = 0
  let mut first = 0
  let mut index = 0
  for len in 1..<16 {
    let bit = br.take(1)
    if bit < 0 {
      return -1
    }
    code = code | bit
    let count = table.counts[len]
    if code - first < count {
      return table.symbols[index + (code - first)]
    }
    index = index + count
    first = (first + count) << 1
    code = code << 1
  }
  -1
}

// ---------------------------------------------------------------------------
// inflate（RFC 1951 §3.2.3–3.2.7）
// ---------------------------------------------------------------------------

///|
/// 长度符号 257..285 的基数（§3.2.5）。
let length_base : Array[Int] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83,
  99, 115, 131, 163, 195, 227, 258,
]

///|
/// 长度符号 257..285 的额外位数。
let length_extra : Array[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5,
  5, 0,
]

///|
/// 距离符号 0..29 的基数（§3.2.5）。
let dist_base : Array[Int] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
]

///|
/// 距离符号 0..29 的额外位数。
let dist_extra : Array[Int] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
  12, 12, 13, 13,
]

///|
/// fixed Huffman literal/length 码长（§3.2.6：0..143→8，144..255→9，
/// 256..279→7，280..287→8）。
fn fixed_lit_lengths() -> Array[Int] {
  let lengths : Array[Int] = Array::make(288, 0)
  for i in 0..<144 {
    lengths[i] = 8
  }
  for i in 144..<256 {
    lengths[i] = 9
  }
  for i in 256..<280 {
    lengths[i] = 7
  }
  for i in 280..<288 {
    lengths[i] = 8
  }
  lengths
}

///|
/// 解一个 Huffman 编码块的符号流（literal / length+distance 回拷 / 256 结束）。
fn inflate_block(
  br : BitReader,
  lit : HuffTable,
  dist : HuffTable,
  out : Array[Int],
) -> Bool {
  for ;; {
    let sym = huff_decode(br, lit)
    if sym < 0 {
      return false
    }
    if sym < 256 {
      out.push(sym)
    } else if sym == 256 {
      return true
    } else {
      if sym > 285 {
        return false
      }
      let li = sym - 257
      let eb = br.take(length_extra[li])
      if eb < 0 {
        return false
      }
      let length = length_base[li] + eb
      let dsym = huff_decode(br, dist)
      if dsym < 0 || dsym > 29 {
        return false
      }
      let de = br.take(dist_extra[dsym])
      if de < 0 {
        return false
      }
      let distance = dist_base[dsym] + de
      if distance > out.length() {
        return false // 引用越过输出起点
      }
      let start = out.length() - distance
      for k in 0..<length {
        out.push(out[start + k])
      }
    }
  }
}

///|
/// 码长字母表的符号读取顺序（§3.2.7）。
let clen_order : Array[Int] = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
]

///|
/// 解 dynamic Huffman 块头（§3.2.7），返回 (literal 表, distance 表)。
fn inflate_dynamic_tables(br : BitReader) -> (HuffTable, HuffTable)? {
  let hlit = br.take(5)
  let hdist = br.take(5)
  let hclen = br.take(4)
  if hlit < 0 || hdist < 0 || hclen < 0 {
    return None
  }
  let nlit = hlit + 257
  let ndist = hdist + 1
  let nclen = hclen + 4
  if nlit > 286 || ndist > 30 {
    return None
  }
  let clen_lengths : Array[Int] = Array::make(19, 0)
  for i in 0..<nclen {
    let v = br.take(3)
    if v < 0 {
      return None
    }
    clen_lengths[clen_order[i]] = v
  }
  guard huff_build(clen_lengths) is Some(clen_table) else { return None }
  // 用码长表解出 literal+distance 的码长序列（16/17/18 重复编码）。
  let lengths : Array[Int] = []
  while lengths.length() < nlit + ndist {
    let sym = huff_decode(br, clen_table)
    if sym < 0 {
      return None
    }
    if sym < 16 {
      lengths.push(sym)
    } else if sym == 16 {
      if lengths.length() == 0 {
        return None
      }
      let prev = lengths[lengths.length() - 1]
      let rep = br.take(2)
      if rep < 0 {
        return None
      }
      for _ in 0..<(rep + 3) {
        lengths.push(prev)
      }
    } else if sym == 17 {
      let rep = br.take(3)
      if rep < 0 {
        return None
      }
      for _ in 0..<(rep + 3) {
        lengths.push(0)
      }
    } else {
      let rep = br.take(7)
      if rep < 0 {
        return None
      }
      for _ in 0..<(rep + 11) {
        lengths.push(0)
      }
    }
  }
  if lengths.length() != nlit + ndist {
    return None
  }
  let lit_lengths : Array[Int] = []
  for i in 0..<nlit {
    lit_lengths.push(lengths[i])
  }
  let dist_lengths : Array[Int] = []
  for i in 0..<ndist {
    dist_lengths.push(lengths[nlit + i])
  }
  guard huff_build(lit_lengths) is Some(lit_table) else { return None }
  // 只有一个距离码长为 0 的退化情形：RFC 允许（纯 literal 数据）。
  match huff_build(dist_lengths) {
    Some(dist_table) => Some((lit_table, dist_table))
    None => {
      // 全零距离表：构造空表占位（inflate_block 中不会用到）。
      let one : Array[Int] = Array::make(30, 0)
      one[0] = 1
      guard huff_build(one) is Some(dist_table) else { return None }
      Some((lit_table, dist_table))
    }
  }
}

///|
/// 解压 raw DEFLATE 流（RFC 1951）；畸形输入返回 None。
pub fn inflate(data : Array[Int]) -> Array[Int]? {
  match inflate_at(data, 0) {
    Some((out, _)) => Some(out)
    None => None
  }
}

///|
/// 自 `start` 字节偏移起解压一条 DEFLATE 流，返回（输出，流结束后按
/// 字节对齐的下一偏移）。供 gzip 多成员解析定位成员边界使用。
fn inflate_at(data : Array[Int], start : Int) -> (Array[Int], Int)? {
  let br = BitReader::new(data)
  br.pos = start
  let out : Array[Int] = []
  for ;; {
    let bfinal = br.take(1)
    let btype = br.take(2)
    if bfinal < 0 || btype < 0 {
      return None
    }
    if btype == 0 {
      // stored（§3.2.4）：对齐字节边界，LEN + ~LEN + 原始字节。
      br.align_byte()
      if br.pos + 4 > br.data.length() {
        return None
      }
      let len = (br.data[br.pos] & 0xFF) | ((br.data[br.pos + 1] & 0xFF) << 8)
      let nlen = (br.data[br.pos + 2] & 0xFF) |
        ((br.data[br.pos + 3] & 0xFF) << 8)
      if len != (nlen ^ 0xFFFF) {
        return None
      }
      br.pos = br.pos + 4
      if br.pos + len > br.data.length() {
        return None
      }
      for k in 0..<len {
        out.push(br.data[br.pos + k] & 0xFF)
      }
      br.pos = br.pos + len
    } else if btype == 1 {
      // fixed Huffman（§3.2.6）。
      guard huff_build(fixed_lit_lengths()) is Some(lit_table) else {
        return None
      }
      let dist_lengths : Array[Int] = Array::make(30, 5)
      guard huff_build(dist_lengths) is Some(dist_table) else { return None }
      if !inflate_block(br, lit_table, dist_table, out) {
        return None
      }
    } else if btype == 2 {
      // dynamic Huffman（§3.2.7）。
      guard inflate_dynamic_tables(br) is Some((lit_table, dist_table)) else {
        return None
      }
      if !inflate_block(br, lit_table, dist_table, out) {
        return None
      }
    } else {
      return None // BTYPE=11 保留
    }
    if bfinal == 1 {
      br.align_byte()
      return Some((out, br.pos))
    }
  }
}

// ---------------------------------------------------------------------------
// deflate 压缩（LZ77 哈希链 + fixed Huffman）
// ---------------------------------------------------------------------------

///|
/// LSB-first 位流写入器。
priv struct BitWriter {
  out : Array[Int]
  mut bit_buf : Int
  mut bit_cnt : Int
}

///|
fn BitWriter::new() -> BitWriter {
  { out: [], bit_buf: 0, bit_cnt: 0 }
}

///|
/// 写 n 位（值的低位先出）。
fn BitWriter::put(self : BitWriter, value : Int, n : Int) -> Unit {
  self.bit_buf = self.bit_buf | ((value & ((1 << n) - 1)) << self.bit_cnt)
  self.bit_cnt = self.bit_cnt + n
  while self.bit_cnt >= 8 {
    self.out.push(self.bit_buf & 0xFF)
    self.bit_buf = self.bit_buf >> 8
    self.bit_cnt = self.bit_cnt - 8
  }
}

///|
/// Huffman 码字位序是 MSB-first（§3.1.1），写入前需反转 n 位。
fn BitWriter::put_huff(self : BitWriter, code : Int, n : Int) -> Unit {
  let mut rev = 0
  for i in 0..<n {
    rev = (rev << 1) | ((code >> i) & 1)
  }
  self.put(rev, n)
}

///|
/// 冲刷尾部不满一字节的位（补零）。
fn BitWriter::flush(self : BitWriter) -> Unit {
  if self.bit_cnt > 0 {
    self.out.push(self.bit_buf & 0xFF)
    self.bit_buf = 0
    self.bit_cnt = 0
  }
}

///|
/// fixed Huffman literal/length 编码（§3.2.6 表）：返回 (code, bits)。
fn fixed_lit_code(sym : Int) -> (Int, Int) {
  if sym < 144 {
    (0x30 + sym, 8) // 00110000..10111111
  } else if sym < 256 {
    (0x190 + (sym - 144), 9) // 110010000..111111111
  } else if sym < 280 {
    (sym - 256, 7) // 0000000..0010111
  } else {
    (0xC0 + (sym - 280), 8) // 11000000..11000111
  }
}

///|
/// 把匹配长度 3..258 映射为 (符号, 额外位值, 额外位数)。
fn length_symbol(length : Int) -> (Int, Int, Int) {
  let mut i = length_base.length() - 1
  while length_base[i] > length {
    i = i - 1
  }
  (257 + i, length - length_base[i], length_extra[i])
}

///|
/// 把距离 1..32768 映射为 (符号, 额外位值, 额外位数)。
fn dist_symbol(distance : Int) -> (Int, Int, Int) {
  let mut i = dist_base.length() - 1
  while dist_base[i] > distance {
    i = i - 1
  }
  (i, distance - dist_base[i], dist_extra[i])
}

///|
/// LZ77 参数：窗口 32 KiB、最小/最大匹配长、哈希链最大回溯次数。
let lz_window : Int = 32768

///|
let lz_min_match : Int = 3

///|
let lz_max_match : Int = 258

///|
let lz_max_chain : Int = 64

///|
/// 3 字节滚动哈希（15 位桶）。
fn lz_hash(data : Array[Int], i : Int) -> Int {
  (
    (data[i] & 0xFF) * 506832829 +
    (data[i + 1] & 0xFF) * 65599 +
    (data[i + 2] & 0xFF)
  ) &
  0x7FFF
}

///|
/// 压缩为 raw DEFLATE 流（单个 fixed Huffman final 块，
/// LZ77 哈希链贪心最长匹配）。
pub fn deflate(data : Array[Int]) -> Array[Int] {
  let bw = BitWriter::new()
  bw.put(1, 1) // BFINAL=1
  bw.put(1, 2) // BTYPE=01 fixed Huffman
  let n = data.length()
  // head[h] = 哈希桶 h 最近出现位置；prev[i & (window-1)] = 链上前一位置。
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
      let (lsym, lextra, lbits) = length_symbol(best_len)
      let (lcode, lclen) = fixed_lit_code(lsym)
      bw.put_huff(lcode, lclen)
      if lbits > 0 {
        bw.put(lextra, lbits)
      }
      let (dsym, dextra, dbits) = dist_symbol(best_dist)
      bw.put_huff(dsym, 5) // fixed 距离码：5 位定长
      if dbits > 0 {
        bw.put(dextra, dbits)
      }
      // 匹配覆盖的每个位置都入哈希链。
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
      let (code, bits) = fixed_lit_code(data[i] & 0xFF)
      bw.put_huff(code, bits)
      if i + lz_min_match <= n {
        let h = lz_hash(data, i)
        prev[i & (lz_window - 1)] = head[h]
        head[h] = i
      }
      i = i + 1
    }
  }
  let (eob_code, eob_bits) = fixed_lit_code(256)
  bw.put_huff(eob_code, eob_bits)
  bw.flush()
  bw.out
}

// ---------------------------------------------------------------------------
// gzip（RFC 1952）
// ---------------------------------------------------------------------------

///|
/// gzip 压缩：10 字节头（无 FNAME/FEXTRA）+ deflate 体 + CRC-32 + ISIZE。
pub fn gzip_compress(data : Array[Int]) -> Array[Int] {
  let out : Array[Int] = [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255]
  for b in deflate(data) {
    out.push(b)
  }
  let crc = @infra_hash.crc32(data)
  for shift in [0, 8, 16, 24] {
    out.push(((crc >> shift) & 0xFFU).reinterpret_as_int())
  }
  let isize = data.length().reinterpret_as_uint()
  for shift in [0, 8, 16, 24] {
    out.push(((isize >> shift) & 0xFFU).reinterpret_as_int())
  }
  out
}

///|
/// gzip 解压：校验魔数/CM、跳过可选字段（FEXTRA/FNAME/FCOMMENT/FHCRC）、
/// 解 deflate 体并核对 CRC-32 与 ISIZE；任一不符返回 None。
///
/// 支持 RFC 1952 §2.2 多成员流（若干 gzip 成员首尾拼接，如 `cat a.gz b.gz`）：
/// 逐成员解压并拼接输出；成员之间/末尾不允许残留垃圾字节。
pub fn gzip_decompress(data : Array[Int]) -> Array[Int]? {
  let n = data.length()
  if n < 18 {
    return None
  }
  let out : Array[Int] = []
  let mut pos = 0
  while pos < n {
    if pos + 18 > n {
      return None
    }
    if (data[pos] & 0xFF) != 0x1F ||
      (data[pos + 1] & 0xFF) != 0x8B ||
      (data[pos + 2] & 0xFF) != 8 {
      return None
    }
    let flg = data[pos + 3] & 0xFF
    pos = pos + 10
    if (flg & 0x04) != 0 {
      // FEXTRA
      if pos + 2 > n {
        return None
      }
      let xlen = (data[pos] & 0xFF) | ((data[pos + 1] & 0xFF) << 8)
      pos = pos + 2 + xlen
    }
    if (flg & 0x08) != 0 {
      // FNAME：NUL 结尾
      while pos < n && (data[pos] & 0xFF) != 0 {
        pos = pos + 1
      }
      pos = pos + 1
    }
    if (flg & 0x10) != 0 {
      // FCOMMENT
      while pos < n && (data[pos] & 0xFF) != 0 {
        pos = pos + 1
      }
      pos = pos + 1
    }
    if (flg & 0x02) != 0 {
      pos = pos + 2 // FHCRC
    }
    if pos + 8 > n {
      return None
    }
    guard inflate_at(data, pos) is Some((raw, body_end)) else { return None }
    if body_end + 8 > n {
      return None
    }
    let mut crc_stored = 0U
    for k in 0..<4 {
      crc_stored = crc_stored |
        ((data[body_end + k] & 0xFF).reinterpret_as_uint() << (8 * k))
    }
    let mut isize_stored = 0U
    for k in 0..<4 {
      isize_stored = isize_stored |
        ((data[body_end + 4 + k] & 0xFF).reinterpret_as_uint() << (8 * k))
    }
    if @infra_hash.crc32(raw) != crc_stored {
      return None
    }
    if raw.length().reinterpret_as_uint() != isize_stored {
      return None
    }
    for b in raw {
      out.push(b)
    }
    pos = body_end + 8
  }
  Some(out)
}
