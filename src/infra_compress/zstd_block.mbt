// zstd_block.mbt —— Zstandard Compressed 块解码（RFC 8878 §4）。
//
// paper-to-code：Collet & Kucherawy *RFC 8878*：
// - §4.1 FSE（有限状态熵）：正向头部比特流解正规化计数
//   （accuracy_log、less-than-one 概率、repeat-zero 标志），
//   spread-position 摆表（step = tableSize/2 + tableSize/8 + 3），
//   逆向比特流按 (baseline, nb_bits) 迁移状态；
// - §4.2.1 字面量段：Raw / RLE / Compressed(Huffman) / Treeless，
//   1 流与 4 流（跳表 6 字节）两种布局；Huffman 权重经 FSE 压缩
//   （双状态交替）或 4-bit 直存，末权重由 2^AL 剩余量隐式推出；
// - §4.2.2 序列段：LL/OF/ML 三张 FSE 表（Predefined / RLE /
//   FSE_Compressed / Repeat 四模式），逆向流按 OF→ML→LL 读附加位、
//   按 LL→ML→OF 更新状态；重复偏移 rep1..rep3 历史在帧内跨块延续；
// - §3.1.1.5 序列执行：字面量拷贝 + 允许自重叠的匹配回拷。
//
// 范围声明（诚实边界）：不支持字典帧（Dictionary_ID ≠ 0 在帧层已拒绝）。
// 帧内 Treeless 字面量 / Repeat FSE 模式 / 重复偏移历史均完整支持。
//
// 测试：python-zstandard（level 3/19）黄金帧解码对拍 + 畸形拒绝 +
// 与 Raw/RLE 路径的 roundtrip 互通。

///|
/// 32 位最高有效位下标（v > 0）。
fn zstd_highbit(v : Int) -> Int {
  let mut x = v
  let mut r = 0
  while x > 1 {
    x = x >> 1
    r = r + 1
  }
  r
}

///|
/// 逆向比特流（RFC 8878 §4.1）：写入端 LSB-first 顺序写位，
/// 末字节最高置位比特为哨兵；读取端从哨兵向低位地址回退消费。
/// `pos` 为剩余可用比特数；peek 允许零填充越界（参考实现语义），
/// 消费后 `pos` 可为负以标记 overflow。
priv struct ZstdBitReader {
  bits : Array[Int] // 展平比特数组（bit i = 流内第 i 位）
  mut pos : Int
}

///|
/// 从字节切片构造逆向比特流；末字节为 0（无哨兵）返回 None。
fn zstd_bit_reader(data : Array[Int], start : Int, len : Int) -> ZstdBitReader? {
  if len <= 0 {
    return None
  }
  let last = data[start + len - 1] & 0xFF
  if last == 0 {
    return None
  }
  let bits : Array[Int] = []
  for k in 0..<len {
    let b = data[start + k] & 0xFF
    for j in 0..<8 {
      bits.push((b >> j) & 1)
    }
  }
  let total = (len - 1) * 8 + zstd_highbit(last)
  Some({ bits, pos: total })
}

///|
/// 预读 n 位（首个待消费位为结果 MSB；越过流首零填充），不消费。
fn ZstdBitReader::peek(self : ZstdBitReader, n : Int) -> Int {
  let mut v = 0
  for j in 0..<n {
    let idx = self.pos - n + j
    let bit = if idx >= 0 && idx < self.bits.length() {
      self.bits[idx]
    } else {
      0
    }
    v = v | (bit << j)
  }
  v
}

///|
/// 读 n 位并消费；overflow 后仍可零填充读取（终检 pos 判定合法性）。
fn ZstdBitReader::read(self : ZstdBitReader, n : Int) -> Int {
  let v = self.peek(n)
  self.pos = self.pos - n
  v
}

///|
/// FSE 解码表单元：输出符号 + 状态迁移 (nb_bits, baseline)。
priv struct FseCell {
  symbol : Int
  nb_bits : Int
  baseline : Int
}

///|
/// FSE 解码表（accuracy_log + 1<<AL 个单元）。
priv struct FseTable {
  accuracy_log : Int
  cells : Array[FseCell]
}

///|
/// 由正规化计数构建 FSE 解码表（RFC 8878 §4.1.1 摆表算法）：
/// -1（less-than-one）符号占据表尾单元，正概率符号按
/// step 螺旋散布；每单元 nb_bits = AL - highbit(next_state)，
/// baseline = (next_state << nb_bits) - tableSize。
fn fse_build_table(norm : Array[Int], accuracy_log : Int) -> FseTable? {
  let table_size = 1 << accuracy_log
  let symbols : Array[Int] = Array::make(table_size, 0)
  let mut high_threshold = table_size - 1
  for s in 0..<norm.length() {
    if norm[s] == -1 {
      symbols[high_threshold] = s
      high_threshold = high_threshold - 1
    }
  }
  let step = (table_size >> 1) + (table_size >> 3) + 3
  let mask = table_size - 1
  let mut position = 0
  for s in 0..<norm.length() {
    if norm[s] > 0 {
      for _k in 0..<norm[s] {
        symbols[position] = s
        position = (position + step) & mask
        while position > high_threshold {
          position = (position + step) & mask
        }
      }
    }
  }
  if position != 0 {
    return None // 摆表未回到原点 → 计数表损坏。
  }
  let next : Array[Int] = Array::make(norm.length(), 0)
  for s in 0..<norm.length() {
    next[s] = if norm[s] == -1 { 1 } else { norm[s] }
  }
  let cells : Array[FseCell] = []
  for i in 0..<table_size {
    let s = symbols[i]
    let state = next[s]
    next[s] = state + 1
    let nb_bits = accuracy_log - zstd_highbit(state)
    cells.push({ symbol: s, nb_bits, baseline: (state << nb_bits) - table_size })
  }
  Some({ accuracy_log, cells })
}

///|
/// 单符号 RLE“表”（AL=0，读 0 位恒返同一符号）。
fn fse_rle_table(symbol : Int) -> FseTable {
  { accuracy_log: 0, cells: [{ symbol, nb_bits: 0, baseline: 0 }] }
}

///|
/// 解 FSE 计数头（RFC 8878 §4.1.1 正向 LSB-first 比特流）：
/// 4 位 accuracy_log-5，变宽概率（含 -1），prob=0 后接 2 位
/// repeat-zero 标志链。返回 (norm, accuracy_log, 消费字节数)。
fn fse_read_ncount(
  data : Array[Int],
  start : Int,
  end : Int,
  max_symbol : Int,
  max_accuracy : Int,
) -> (Array[Int], Int, Int)? {
  let mut bitpos = 0
  let avail_bits = (end - start) * 8
  fn fread(n : Int) -> Int? {
    if bitpos + n > avail_bits {
      return None
    }
    let mut v = 0
    for j in 0..<n {
      let idx = bitpos + j
      let bit = (data[start + idx / 8] >> (idx % 8)) & 1
      v = v | (bit << j)
    }
    bitpos = bitpos + n
    Some(v)
  }

  let accuracy_log = match fread(4) {
    None => return None
    Some(v) => v + 5
  }
  if accuracy_log > max_accuracy {
    return None
  }
  let table_size = 1 << accuracy_log
  let norm : Array[Int] = []
  let mut remaining = table_size + 1
  let mut threshold = table_size
  let mut nb_bits = accuracy_log + 1
  let mut previous0 = false
  while remaining > 1 && norm.length() <= max_symbol {
    if previous0 {
      // repeat-zero 标志链：2 位一组，3 表示继续。
      let mut go = true
      while go {
        let flag = match fread(2) {
          None => return None
          Some(v) => v
        }
        for _k in 0..<flag {
          if norm.length() > max_symbol {
            return None
          }
          norm.push(0)
        }
        go = flag == 3
      }
      previous0 = false
      if remaining <= 1 || norm.length() > max_symbol {
        break
      }
    }
    let max = 2 * threshold - 1 - remaining
    let low = match fread(nb_bits - 1) {
      None => return None
      Some(v) => v
    }
    let mut count = 0
    if low < max {
      count = low
    } else {
      // 需要完整 nb_bits：补读最高 1 位。
      let hi = match fread(1) {
        None => return None
        Some(v) => v
      }
      let full = low | (hi << (nb_bits - 1))
      count = if full >= threshold { full - max } else { full }
    }
    let prob = count - 1 // -1 即 less-than-one。
    remaining = remaining - (if prob < 0 { 1 } else { prob })
    norm.push(prob)
    previous0 = prob == 0
    while remaining < threshold && remaining > 1 {
      nb_bits = nb_bits - 1
      threshold = threshold >> 1
    }
  }
  if remaining != 1 {
    return None
  }
  Some((norm, accuracy_log, (bitpos + 7) / 8))
}

///|
/// Huffman 解码表：tableLog + 每索引 (symbol, nb_bits)。
priv struct ZstdHuffTable {
  table_log : Int
  symbols : Array[Int]
  lengths : Array[Int]
}

///|
/// 由权重构建 Huffman 单级解码表（参考实现 X1 布局）：
/// 末权重由 2^AL 剩余量隐式推出；weight w 占据 2^(w-1) 个
/// 连续单元（rank 起点自低权重累计），nb_bits = tableLog+1-w。
fn huf_build_table(weights : Array[Int]) -> ZstdHuffTable? {
  let mut total = 0
  let mut max_w = 0
  for w in weights {
    if w > 12 {
      return None
    }
    if w > 0 {
      total = total + (1 << (w - 1))
    }
    if w > max_w {
      max_w = w
    }
  }
  if total == 0 {
    return None
  }
  let table_log = zstd_highbit(total) + 1
  if table_log > 11 {
    return None
  }
  let rest = (1 << table_log) - total
  // rest 必须为 2 的幂（末权重合法性）。
  if rest <= 0 || (rest & (rest - 1)) != 0 {
    return None
  }
  let last_w = zstd_highbit(rest) + 1
  let all : Array[Int] = []
  for w in weights {
    all.push(w)
  }
  all.push(last_w)
  if last_w > max_w {
    max_w = last_w
  }
  let size = 1 << table_log
  let rank_count : Array[Int] = Array::make(max_w + 1, 0)
  for w in all {
    if w > 0 {
      rank_count[w] = rank_count[w] + 1
    }
  }
  let rank_start : Array[Int] = Array::make(max_w + 2, 0)
  let mut cur = 0
  for w in 1..<=max_w {
    rank_start[w] = cur
    cur = cur + (rank_count[w] << (w - 1))
  }
  if cur != size {
    return None
  }
  let symbols : Array[Int] = Array::make(size, 0)
  let lengths : Array[Int] = Array::make(size, 0)
  for s in 0..<all.length() {
    let w = all[s]
    if w > 0 {
      let len = 1 << (w - 1)
      let nb = table_log + 1 - w
      for k in 0..<len {
        symbols[rank_start[w] + k] = s
        lengths[rank_start[w] + k] = nb
      }
      rank_start[w] = rank_start[w] + len
    }
  }
  Some({ table_log, symbols, lengths })
}

///|
/// 解 Huffman 权重（RFC 8878 §4.2.1.3）：头字节 <128 走 FSE 压缩
/// （双状态交替、上限 255 权重），≥128 走 4-bit 直存（headerByte-127 个）。
/// 返回 (weights, 消费字节数含头字节)。
fn huf_read_weights(
  data : Array[Int],
  start : Int,
  end : Int,
) -> (Array[Int], Int)? {
  if start >= end {
    return None
  }
  let header = data[start] & 0xFF
  if header >= 128 {
    let num = header - 127
    let bytes = (num + 1) / 2
    if start + 1 + bytes > end {
      return None
    }
    let weights : Array[Int] = []
    for k in 0..<num {
      let b = data[start + 1 + k / 2] & 0xFF
      weights.push(if k % 2 == 0 { b >> 4 } else { b & 0x0F })
    }
    return Some((weights, 1 + bytes))
  }
  let comp_size = header
  if start + 1 + comp_size > end {
    return None
  }
  let hstart = start + 1
  let hend = hstart + comp_size
  let (norm, al, consumed) = match fse_read_ncount(data, hstart, hend, 255, 6) {
    None => return None
    Some(v) => v
  }
  let table = match fse_build_table(norm, al) {
    None => return None
    Some(t) => t
  }
  let br = match
    zstd_bit_reader(data, hstart + consumed, comp_size - consumed) {
    None => return None
    Some(b) => b
  }
  let mut s1 = br.read(al)
  let mut s2 = br.read(al)
  if br.pos < 0 {
    return None
  }
  let weights : Array[Int] = []
  // 双状态交替解码；overflow 后从另一状态收尾（参考实现语义）。
  let mut done = false
  while !done && weights.length() < 255 {
    let c1 = table.cells[s1]
    weights.push(c1.symbol)
    s1 = c1.baseline + br.read(c1.nb_bits)
    if br.pos < 0 {
      weights.push(table.cells[s2].symbol)
      done = true
    } else if weights.length() < 255 {
      let c2 = table.cells[s2]
      weights.push(c2.symbol)
      s2 = c2.baseline + br.read(c2.nb_bits)
      if br.pos < 0 {
        weights.push(table.cells[s1].symbol)
        done = true
      }
    }
  }
  if !done {
    return None // 255 权重仍未耗尽 → 流损坏。
  }
  Some((weights, 1 + comp_size))
}

///|
/// 用 Huffman 表解单个逆向比特流为恰好 count 个字节；
/// 结束时必须恰好耗尽（pos == 0）。
fn huf_decode_stream(
  table : ZstdHuffTable,
  data : Array[Int],
  start : Int,
  len : Int,
  count : Int,
  out : Array[Int],
) -> Bool {
  let br = match zstd_bit_reader(data, start, len) {
    None => return false
    Some(b) => b
  }
  for _k in 0..<count {
    let idx = br.peek(table.table_log)
    let nb = table.lengths[idx]
    if nb == 0 {
      return false
    }
    br.pos = br.pos - nb
    out.push(table.symbols[idx])
  }
  br.pos == 0
}

///|
/// 帧内跨块解码上下文：Treeless 字面量的 Huffman 表、
/// Repeat 模式的三张 FSE 表、重复偏移 rep1..rep3 历史。
priv struct ZstdBlockCtx {
  mut huff : ZstdHuffTable?
  mut ll : FseTable?
  mut of : FseTable?
  mut ml : FseTable?
  rep : Array[Int]
}

///|
/// 新建帧级上下文（rep 初值 1/4/8，RFC 8878 §3.1.1.5）。
fn zstd_block_ctx() -> ZstdBlockCtx {
  { huff: None, ll: None, of: None, ml: None, rep: [1, 4, 8] }
}

///|
/// LL 码 → (baseline, extra_bits)（RFC 8878 表 §3.1.1.3.2.1.1）。
fn zstd_ll_code(code : Int) -> (Int, Int)? {
  if code < 0 || code > 35 {
    return None
  }
  if code < 16 {
    return Some((code, 0))
  }
  let base = [
    16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096, 8192,
    16384, 32768, 65536,
  ]
  let bits = [1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
  Some((base[code - 16], bits[code - 16]))
}

///|
/// ML 码 → (baseline, extra_bits)（RFC 8878 表 §3.1.1.3.2.1.1）。
fn zstd_ml_code(code : Int) -> (Int, Int)? {
  if code < 0 || code > 52 {
    return None
  }
  if code < 32 {
    return Some((code + 3, 0))
  }
  let base = [
    35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099,
    8195, 16387, 32771, 65539,
  ]
  let bits = [
    1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
  ]
  Some((base[code - 32], bits[code - 32]))
}

///|
/// LL 预定义分布（AL=6，36 符号，RFC 8878 §3.1.1.3.2.2）。
fn zstd_ll_default() -> Array[Int] {
  [
    4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3,
    2, 1, 1, 1, 1, 1, -1, -1, -1, -1,
  ]
}

///|
/// OF 预定义分布（AL=5，29 符号）。
fn zstd_of_default() -> Array[Int] {
  [
    1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1,
    -1, -1, -1,
  ]
}

///|
/// ML 预定义分布（AL=6，53 符号）。
fn zstd_ml_default() -> Array[Int] {
  [
    1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1,
    -1, -1,
  ]
}

///|
/// 按压缩模式（Predefined/RLE/FSE_Compressed/Repeat）取序列 FSE 表；
/// 返回 (table, 新偏移)。Repeat 无历史表时非法。
fn zstd_seq_table(
  data : Array[Int],
  pos : Int,
  end : Int,
  mode : Int,
  default_norm : Array[Int],
  default_al : Int,
  max_symbol : Int,
  max_al : Int,
  prev : FseTable?,
) -> (FseTable, Int)? {
  if mode == 0 {
    match fse_build_table(default_norm, default_al) {
      None => None
      Some(t) => Some((t, pos))
    }
  } else if mode == 1 {
    if pos >= end {
      return None
    }
    let sym = data[pos] & 0xFF
    if sym > max_symbol {
      return None
    }
    Some((fse_rle_table(sym), pos + 1))
  } else if mode == 2 {
    let (norm, al, consumed) = match
      fse_read_ncount(data, pos, end, max_symbol, max_al) {
      None => return None
      Some(v) => v
    }
    match fse_build_table(norm, al) {
      None => None
      Some(t) => Some((t, pos + consumed))
    }
  } else {
    match prev {
      None => None
      Some(t) => Some((t, pos))
    }
  }
}

///|
/// 解 Compressed 块（data[pos..pos+size)）到 out（帧窗口起点
/// frame_start，输出上限 max_out）；成功返回 true。
/// 完整覆盖字面量段（4 类 × 1/4 流）与序列段（4 模式 × 3 表）。
fn zstd_decode_compressed_block(
  data : Array[Int],
  pos : Int,
  size : Int,
  out : Array[Int],
  frame_start : Int,
  max_out : Int,
  ctx : ZstdBlockCtx,
) -> Bool {
  let end = pos + size
  if end > data.length() || size < 2 {
    return false
  }
  // ── 字面量段（§4.2.1）──
  let b0 = data[pos] & 0xFF
  let lit_type = b0 & 3
  let size_format = (b0 >> 2) & 3
  let lits : Array[Int] = []
  let mut cur = pos
  if lit_type == 0 || lit_type == 1 {
    // Raw / RLE 字面量。
    let mut regen = 0
    if size_format == 0 || size_format == 2 {
      regen = b0 >> 3
      cur = cur + 1
    } else if size_format == 1 {
      if cur + 2 > end {
        return false
      }
      regen = (b0 >> 4) | ((data[cur + 1] & 0xFF) << 4)
      cur = cur + 2
    } else {
      if cur + 3 > end {
        return false
      }
      regen = (b0 >> 4) |
        ((data[cur + 1] & 0xFF) << 4) |
        ((data[cur + 2] & 0xFF) << 12)
      cur = cur + 3
    }
    if lit_type == 0 {
      if cur + regen > end {
        return false
      }
      for k in 0..<regen {
        lits.push(data[cur + k] & 0xFF)
      }
      cur = cur + regen
    } else {
      if cur >= end {
        return false
      }
      let b = data[cur] & 0xFF
      cur = cur + 1
      for _k in 0..<regen {
        lits.push(b)
      }
    }
  } else {
    // Compressed / Treeless 字面量（Huffman）。
    let mut regen = 0
    let mut comp = 0
    let mut four_streams = true
    if size_format == 0 || size_format == 1 {
      if cur + 3 > end {
        return false
      }
      let v = b0 |
        ((data[cur + 1] & 0xFF) << 8) |
        ((data[cur + 2] & 0xFF) << 16)
      regen = (v >> 4) & 0x3FF
      comp = (v >> 14) & 0x3FF
      four_streams = size_format == 1
      cur = cur + 3
    } else if size_format == 2 {
      if cur + 4 > end {
        return false
      }
      let v = b0 |
        ((data[cur + 1] & 0xFF) << 8) |
        ((data[cur + 2] & 0xFF) << 16) |
        ((data[cur + 3] & 0xFF) << 24)
      regen = (v >> 4) & 0x3FFF
      comp = (v >> 18) & 0x3FFF
      cur = cur + 4
    } else {
      if cur + 5 > end {
        return false
      }
      // 18+18 位跨 5 字节，用 UInt64 避免符号位。
      let v = (b0 & 0xFF).to_uint64() |
        ((data[cur + 1] & 0xFF).to_uint64() << 8) |
        ((data[cur + 2] & 0xFF).to_uint64() << 16) |
        ((data[cur + 3] & 0xFF).to_uint64() << 24) |
        ((data[cur + 4] & 0xFF).to_uint64() << 32)
      regen = ((v >> 4) & 0x3FFFFUL).to_int()
      comp = ((v >> 22) & 0x3FFFFUL).to_int()
      cur = cur + 5
    }
    if cur + comp > end {
      return false
    }
    let lit_end = cur + comp
    let table = if lit_type == 2 {
      let (weights, consumed) = match huf_read_weights(data, cur, lit_end) {
        None => return false
        Some(v) => v
      }
      cur = cur + consumed
      let t = match huf_build_table(weights) {
        None => return false
        Some(t) => t
      }
      ctx.huff = Some(t)
      t
    } else {
      match ctx.huff {
        None => return false // Treeless 无历史表。
        Some(t) => t
      }
    }
    if four_streams {
      if cur + 6 > lit_end {
        return false
      }
      let s1 = (data[cur] & 0xFF) | ((data[cur + 1] & 0xFF) << 8)
      let s2 = (data[cur + 2] & 0xFF) | ((data[cur + 3] & 0xFF) << 8)
      let s3 = (data[cur + 4] & 0xFF) | ((data[cur + 5] & 0xFF) << 8)
      cur = cur + 6
      let s4 = lit_end - cur - s1 - s2 - s3
      if s4 <= 0 {
        return false
      }
      let c1 = (regen + 3) / 4
      let c4 = regen - 3 * c1
      if c4 < 0 {
        return false
      }
      if !huf_decode_stream(table, data, cur, s1, c1, lits) {
        return false
      }
      if !huf_decode_stream(table, data, cur + s1, s2, c1, lits) {
        return false
      }
      if !huf_decode_stream(table, data, cur + s1 + s2, s3, c1, lits) {
        return false
      }
      if !huf_decode_stream(table, data, cur + s1 + s2 + s3, s4, c4, lits) {
        return false
      }
    } else if !huf_decode_stream(table, data, cur, lit_end - cur, regen, lits) {
      return false
    }
    cur = lit_end
  }
  // ── 序列段（§4.2.2）──
  if cur >= end {
    return false
  }
  let sb0 = data[cur] & 0xFF
  cur = cur + 1
  let mut nb_seq = 0
  if sb0 < 128 {
    nb_seq = sb0
  } else if sb0 < 255 {
    if cur >= end {
      return false
    }
    nb_seq = ((sb0 - 128) << 8) + (data[cur] & 0xFF)
    cur = cur + 1
  } else {
    if cur + 2 > end {
      return false
    }
    nb_seq = (data[cur] & 0xFF) + ((data[cur + 1] & 0xFF) << 8) + 0x7F00
    cur = cur + 2
  }
  if nb_seq == 0 {
    // 纯字面量块。
    if cur != end || out.length() + lits.length() > max_out {
      return false
    }
    for b in lits {
      out.push(b)
    }
    return true
  }
  if cur >= end {
    return false
  }
  let modes = data[cur] & 0xFF
  cur = cur + 1
  if (modes & 3) != 0 {
    return false // 保留位必须为 0。
  }
  let ll_mode = (modes >> 6) & 3
  let of_mode = (modes >> 4) & 3
  let ml_mode = (modes >> 2) & 3
  let (ll_table, p1) = match
    zstd_seq_table(data, cur, end, ll_mode, zstd_ll_default(), 6, 35, 9, ctx.ll) {
    None => return false
    Some(v) => v
  }
  let (of_table, p2) = match
    zstd_seq_table(data, p1, end, of_mode, zstd_of_default(), 5, 31, 8, ctx.of) {
    None => return false
    Some(v) => v
  }
  let (ml_table, p3) = match
    zstd_seq_table(data, p2, end, ml_mode, zstd_ml_default(), 6, 52, 9, ctx.ml) {
    None => return false
    Some(v) => v
  }
  ctx.ll = Some(ll_table)
  ctx.of = Some(of_table)
  ctx.ml = Some(ml_table)
  cur = p3
  let br = match zstd_bit_reader(data, cur, end - cur) {
    None => return false
    Some(b) => b
  }
  // 状态初始化顺序：LL → OF → ML（§4.2.2）。
  let mut ll_state = br.read(ll_table.accuracy_log)
  let mut of_state = br.read(of_table.accuracy_log)
  let mut ml_state = br.read(ml_table.accuracy_log)
  if br.pos < 0 {
    return false
  }
  let mut lit_pos = 0
  for seq_i in 0..<nb_seq {
    let of_code = of_table.cells[of_state].symbol
    let ml_code = ml_table.cells[ml_state].symbol
    let ll_code = ll_table.cells[ll_state].symbol
    // 附加位读取顺序：OF → ML → LL。
    if of_code > 31 {
      return false
    }
    let of_value = (1 << of_code) + br.read(of_code)
    let (ml_base, ml_bits) = match zstd_ml_code(ml_code) {
      None => return false
      Some(v) => v
    }
    let ml = ml_base + br.read(ml_bits)
    let (ll_base, ll_bits) = match zstd_ll_code(ll_code) {
      None => return false
      Some(v) => v
    }
    let ll = ll_base + br.read(ll_bits)
    if br.pos < 0 {
      return false
    }
    // 重复偏移历史（§3.1.1.5）。
    let mut offset = 0
    if of_value > 3 {
      offset = of_value - 3
      ctx.rep[2] = ctx.rep[1]
      ctx.rep[1] = ctx.rep[0]
      ctx.rep[0] = offset
    } else {
      let idx = if ll == 0 { of_value } else { of_value - 1 }
      if idx == 0 {
        offset = ctx.rep[0]
      } else if idx == 3 {
        offset = ctx.rep[0] - 1
        if offset == 0 {
          return false
        }
        ctx.rep[2] = ctx.rep[1]
        ctx.rep[1] = ctx.rep[0]
        ctx.rep[0] = offset
      } else {
        offset = ctx.rep[idx]
        if idx == 2 {
          ctx.rep[2] = ctx.rep[1]
        }
        ctx.rep[1] = ctx.rep[0]
        ctx.rep[0] = offset
      }
    }
    // 序列执行：字面量拷贝 + 自重叠匹配回拷。
    if lit_pos + ll > lits.length() ||
      out.length() + ll + ml > max_out ||
      offset <= 0 {
      return false
    }
    for k in 0..<ll {
      out.push(lits[lit_pos + k])
    }
    lit_pos = lit_pos + ll
    if offset > out.length() - frame_start {
      return false
    }
    for _k in 0..<ml {
      out.push(out[out.length() - offset])
    }
    // 状态更新顺序：LL → ML → OF（最后一条序列不更新）。
    if seq_i < nb_seq - 1 {
      let lc = ll_table.cells[ll_state]
      ll_state = lc.baseline + br.read(lc.nb_bits)
      let mc = ml_table.cells[ml_state]
      ml_state = mc.baseline + br.read(mc.nb_bits)
      let oc = of_table.cells[of_state]
      of_state = oc.baseline + br.read(oc.nb_bits)
      if br.pos < 0 {
        return false
      }
    }
  }
  if br.pos != 0 {
    return false // 逆向流必须恰好耗尽。
  }
  // 尾部剩余字面量。
  let rest = lits.length() - lit_pos
  if out.length() + rest > max_out {
    return false
  }
  for k in lit_pos..<lits.length() {
    out.push(lits[k])
  }
  true
}
