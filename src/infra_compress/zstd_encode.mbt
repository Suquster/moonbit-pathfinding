// zstd_encode.mbt —— Zstandard 熵压缩侧（RFC 8878 §4，Compressed 块编码）。
//
// paper-to-code：RFC 8878 + 参考实现 zstd_compress_sequences.c：
// - LZ77 贪心匹配（4 字节哈希链，链长上限）产出 (ll, ml, offset) 序列；
// - 字面量段走 Raw 布局（合法且免表），序列段用三张预定义 FSE 表
//   （LL AL=6 / OF AL=5 / ML AL=6）编码；
// - FSE 编码表按参考实现 symbolTT 构造：deltaNbBits / deltaFindState，
//   nbBits = (state + deltaNbBits) >> 16，次态 = stateTable[(state>>nb)+delta]；
// - 逆向比特流自后向前编码：末序列三状态初始化（ML→OF→LL），
//   末序列附加位（LL→ML→OF），其余序列逆序（符号 OF→ML→LL、
//   附加位 LL→ML→OF），终了冲刷状态 ML→OF→LL，哨兵位收尾；
// - 每块若熵编码不小于 Raw 布局则回退 Raw 块（压缩永不劣化）。
//
// 验证：本包 RFC 解码器 roundtrip PBT + 固定输入快照帧
// （已用 python-zstandard 0.25.0 外部对拍解码一致）。

///|
/// 正向比特写入器（LSB-first）；close 追加哨兵 1 位并补零到字节。
priv struct ZstdBitWriter {
  bits : Array[Int]
}

///|
/// 追加 value 的低 n 位（LSB-first）。
fn ZstdBitWriter::add(self : ZstdBitWriter, value : Int, n : Int) -> Unit {
  for j in 0..<n {
    self.bits.push((value >> j) & 1)
  }
}

///|
/// 哨兵位 + 补零，打包为字节序列。
fn ZstdBitWriter::close(self : ZstdBitWriter) -> Array[Int] {
  self.bits.push(1)
  while self.bits.length() % 8 != 0 {
    self.bits.push(0)
  }
  let out : Array[Int] = []
  let mut i = 0
  while i < self.bits.length() {
    let mut b = 0
    for j in 0..<8 {
      b = b | (self.bits[i + j] << j)
    }
    out.push(b)
    i = i + 8
  }
  out
}

///|
/// FSE 编码表（参考实现 CTable 布局）。
priv struct FseEncTable {
  table_log : Int
  state_table : Array[Int] // 值域 [tableSize, 2*tableSize)
  delta_nb_bits : Array[Int]
  delta_find_state : Array[Int]
}

///|
/// 由正规化计数构建 FSE 编码表（与解码摆表同一螺旋散布）。
fn fse_build_enc_table(norm : Array[Int], accuracy_log : Int) -> FseEncTable {
  let table_size = 1 << accuracy_log
  let syms = norm.length()
  // cumul[s]：符号 s 的状态区间起点。
  let cumul : Array[Int] = Array::make(syms + 1, 0)
  for s in 0..<syms {
    cumul[s + 1] = cumul[s] + (if norm[s] == -1 { 1 } else { norm[s] })
  }
  // 螺旋散布（-1 符号占表尾）。
  let spread : Array[Int] = Array::make(table_size, 0)
  let mut high_threshold = table_size - 1
  for s in 0..<syms {
    if norm[s] == -1 {
      spread[high_threshold] = s
      high_threshold = high_threshold - 1
    }
  }
  let step = (table_size >> 1) + (table_size >> 3) + 3
  let mask = table_size - 1
  let mut position = 0
  for s in 0..<syms {
    if norm[s] > 0 {
      for _k in 0..<norm[s] {
        spread[position] = s
        position = (position + step) & mask
        while position > high_threshold {
          position = (position + step) & mask
        }
      }
    }
  }
  // stateTable[cumul[symbol]++] = tableSize + 表内位置。
  let next : Array[Int] = []
  for s in 0..<syms {
    next.push(cumul[s])
  }
  let state_table : Array[Int] = Array::make(table_size, 0)
  for u in 0..<table_size {
    let s = spread[u]
    state_table[next[s]] = table_size + u
    next[s] = next[s] + 1
  }
  // symbolTT：deltaNbBits / deltaFindState。
  let delta_nb_bits : Array[Int] = Array::make(syms, 0)
  let delta_find_state : Array[Int] = Array::make(syms, 0)
  let mut total = 0
  for s in 0..<syms {
    let p = norm[s]
    if p == 0 {
      delta_nb_bits[s] = ((accuracy_log + 1) << 16) - table_size
      delta_find_state[s] = 0
    } else if p == -1 || p == 1 {
      delta_nb_bits[s] = (accuracy_log << 16) - table_size
      delta_find_state[s] = total - 1
      total = total + 1
    } else {
      let max_bits_out = accuracy_log - zstd_highbit(p - 1)
      let min_state_plus = p << max_bits_out
      delta_nb_bits[s] = (max_bits_out << 16) - min_state_plus
      delta_find_state[s] = total - p
      total = total + p
    }
  }
  { table_log: accuracy_log, state_table, delta_nb_bits, delta_find_state }
}

///|
/// 首符号状态初始化（参考实现 FSE_initCState2）。
fn FseEncTable::init_state(self : FseEncTable, symbol : Int) -> Int {
  let nb = (self.delta_nb_bits[symbol] + (1 << 15)) >> 16
  let value = (nb << 16) - self.delta_nb_bits[symbol]
  self.state_table[(value >> nb) + self.delta_find_state[symbol]]
}

///|
/// 编码一个符号：写 nbBits 位旧状态低位，返回次态。
fn FseEncTable::encode(
  self : FseEncTable,
  bw : ZstdBitWriter,
  state : Int,
  symbol : Int,
) -> Int {
  let nb = (state + self.delta_nb_bits[symbol]) >> 16
  bw.add(state, nb)
  self.state_table[(state >> nb) + self.delta_find_state[symbol]]
}

///|
/// LL 值 → (code, extra_bits, extra_value)。
fn zstd_ll_encode(ll : Int) -> (Int, Int, Int) {
  if ll < 16 {
    return (ll, 0, 0)
  }
  let mut code = 35
  while code >= 16 {
    match zstd_ll_code(code) {
      Some((base, bits)) => if ll >= base { return (code, bits, ll - base) }
      None => ()
    }
    code = code - 1
  }
  (0, 0, 0) // 不可达（ll ≥ 16 必落入某档）。
}

///|
/// ML 值 → (code, extra_bits, extra_value)。
fn zstd_ml_encode(ml : Int) -> (Int, Int, Int) {
  if ml < 35 {
    return (ml - 3, 0, 0)
  }
  let mut code = 52
  while code >= 32 {
    match zstd_ml_code(code) {
      Some((base, bits)) => if ml >= base { return (code, bits, ml - base) }
      None => ()
    }
    code = code - 1
  }
  (0, 0, 0) // 不可达（ml ≥ 35 必落入某档）。
}

///|
/// 单条 LZ77 序列。
priv struct ZstdSeq {
  ll : Int
  ml : Int
  offset : Int // 真实偏移（编码为 offset+3，不用重复偏移历史）
}

///|
/// 贪心 LZ77 匹配（4 字节哈希链，链长 ≤ 32，最小匹配 4）：
/// 返回 (sequences, 尾部字面量起点)；字面量即 data[..] 中未被
/// 序列覆盖的区段，由调用方按 ll 切分。
fn zstd_find_sequences(
  data : Array[Int],
  start : Int,
  len : Int,
) -> (Array[ZstdSeq], Array[Int]) {
  let seqs : Array[ZstdSeq] = []
  let lits : Array[Int] = []
  let heads : Map[Int, Array[Int]] = Map([])
  fn hash4(p : Int) -> Int {
    (data[start + p] & 0xFF) |
    ((data[start + p + 1] & 0xFF) << 8) |
    ((data[start + p + 2] & 0xFF) << 16) |
    ((data[start + p + 3] & 0xFF) << 24)
  }

  let mut pos = 0
  let mut lit_run = 0
  while pos + 4 <= len {
    let h = hash4(pos)
    let mut best_len = 0
    let mut best_off = 0
    match heads.get(h) {
      Some(chain) => {
        let mut tried = 0
        let mut ci = chain.length() - 1
        while ci >= 0 && tried < 32 {
          let cand = chain[ci]
          let mut m = 0
          while pos + m < len && data[start + cand + m] == data[start + pos + m] {
            m = m + 1
          }
          if m >= 4 && m > best_len {
            best_len = m
            best_off = pos - cand
          }
          ci = ci - 1
          tried = tried + 1
        }
        chain.push(pos)
      }
      None => heads.set(h, [pos])
    }
    if best_len >= 4 {
      seqs.push({ ll: lit_run, ml: best_len, offset: best_off })
      lit_run = 0
      // 跳过匹配区（不为区内位置建链，贪心足够）。
      pos = pos + best_len
    } else {
      lits.push(data[start + pos] & 0xFF)
      lit_run = lit_run + 1
      pos = pos + 1
    }
  }
  // 尾部不足 4 字节的散字面量。
  while pos < len {
    lits.push(data[start + pos] & 0xFF)
    lit_run = lit_run + 1
    pos = pos + 1
  }
  // lit_run 尾部字面量不属于任何序列（解码时按剩余字面量追加）。
  (seqs, lits)
}

///|
/// 编码一个 Compressed 块内容（Raw 字面量 + 预定义 FSE 序列）；
/// 无收益（序列为空或产物不小于 Raw）返回 None。
fn zstd_encode_block(data : Array[Int], start : Int, len : Int) -> Array[Int]? {
  let (seqs, lits) = zstd_find_sequences(data, start, len)
  if seqs.length() == 0 || seqs.length() >= 0x7F00 {
    return None
  }
  let out : Array[Int] = []
  // ── 字面量段：Raw 布局 ──
  let regen = lits.length()
  if regen < 32 {
    out.push((regen << 3) | 0) // size_format 00，5 位。
  } else if regen < 4096 {
    out.push(((regen & 0x0F) << 4) | (1 << 2) | 0) // size_format 01，12 位。
    out.push((regen >> 4) & 0xFF)
  } else {
    out.push(((regen & 0x0F) << 4) | (3 << 2) | 0) // size_format 11，20 位。
    out.push((regen >> 4) & 0xFF)
    out.push((regen >> 12) & 0xFF)
  }
  for b in lits {
    out.push(b)
  }
  // ── 序列段：预定义三表 ──
  let nb_seq = seqs.length()
  if nb_seq < 128 {
    out.push(nb_seq)
  } else {
    out.push(128 + (nb_seq >> 8))
    out.push(nb_seq & 0xFF)
  }
  out.push(0x00) // 三表全 Predefined。
  let ll_t = fse_build_enc_table(zstd_ll_default(), 6)
  let of_t = fse_build_enc_table(zstd_of_default(), 5)
  let ml_t = fse_build_enc_table(zstd_ml_default(), 6)
  let bw : ZstdBitWriter = { bits: [] }
  // 预计算每序列码与附加位。
  let codes : Array[(Int, Int, Int, Int, Int, Int, Int, Int, Int)] = []
  for sq in seqs {
    let (llc, llb, llv) = zstd_ll_encode(sq.ll)
    let (mlc, mlb, mlv) = zstd_ml_encode(sq.ml)
    let ofv = sq.offset + 3
    let ofc = zstd_highbit(ofv)
    let ofx = ofv - (1 << ofc)
    if ofc > 28 {
      return None // 超出预定义 OF 表符号域（块 ≤64KB 不会发生）。
    }
    codes.push((llc, llb, llv, mlc, mlb, mlv, ofc, ofc, ofx))
  }
  // 末序列：状态初始化 ML → OF → LL，附加位 LL → ML → OF。
  let (llc, llb, llv, mlc, mlb, mlv, ofc, ofbits, ofx) = codes[nb_seq - 1]
  let mut ml_state = ml_t.init_state(mlc)
  let mut of_state = of_t.init_state(ofc)
  let mut ll_state = ll_t.init_state(llc)
  bw.add(llv, llb)
  bw.add(mlv, mlb)
  bw.add(ofx, ofbits)
  // 其余序列逆序：符号 OF → ML → LL，附加位 LL → ML → OF。
  let mut n = nb_seq - 2
  while n >= 0 {
    let (llc, llb, llv, mlc, mlb, mlv, ofc, ofbits, ofx) = codes[n]
    of_state = of_t.encode(bw, of_state, ofc)
    ml_state = ml_t.encode(bw, ml_state, mlc)
    ll_state = ll_t.encode(bw, ll_state, llc)
    bw.add(llv, llb)
    bw.add(mlv, mlb)
    bw.add(ofx, ofbits)
    n = n - 1
  }
  // 冲刷状态 ML → OF → LL（解码端 LL → OF → ML 先读）。
  bw.add(ml_state, ml_t.table_log)
  bw.add(of_state, of_t.table_log)
  bw.add(ll_state, ll_t.table_log)
  for b in bw.close() {
    out.push(b)
  }
  if out.length() >= len {
    return None // 无收益，回退 Raw。
  }
  Some(out)
}

///|
/// Zstandard 熵压缩（RFC 8878 Compressed 块：LZ77 + 预定义 FSE 序列 +
/// Raw 字面量）：帧结构与 `zstd_compress` 一致（单段帧、64KB 分块、
/// 可选 XXH64 校验）；逐块择优——熵编码无收益时回退 Raw/RLE，
/// 产物永不劣于 `zstd_compress`。任何 RFC 8878 解码器可无损还原
/// （已与 python-zstandard 外部对拍）。
pub fn zstd_compress_entropy(
  data : Array[Int],
  with_checksum : Bool,
) -> Array[Int] {
  let n = data.length()
  let out : Array[Int] = []
  for b in zstd_magic() {
    out.push(b)
  }
  let fcs_flag = if n <= 255 { 0 } else if n - 256 <= 65535 { 1 } else { 2 }
  let checksum_bit = if with_checksum { 4 } else { 0 }
  out.push((fcs_flag << 6) | 0x20 | checksum_bit)
  if fcs_flag == 0 {
    out.push(n & 0xFF)
  } else if fcs_flag == 1 {
    let v = n - 256
    out.push(v & 0xFF)
    out.push((v >> 8) & 0xFF)
  } else {
    out.push(n & 0xFF)
    out.push((n >> 8) & 0xFF)
    out.push((n >> 16) & 0xFF)
    out.push((n >> 24) & 0xFF)
  }
  if n == 0 {
    zstd_write_block_header(out, true, 0, 0)
  } else {
    let chunk = 65536
    let mut pos = 0
    while pos < n {
      let len = if n - pos < chunk { n - pos } else { chunk }
      let last = pos + len >= n
      let mut all_same = len >= 4
      for k in 1..<len {
        if data[pos + k] != data[pos] {
          all_same = false
          break
        }
      }
      if all_same {
        zstd_write_block_header(out, last, 1, len)
        out.push(data[pos] & 0xFF)
      } else {
        match zstd_encode_block(data, pos, len) {
          Some(blk) => {
            zstd_write_block_header(out, last, 2, blk.length())
            for b in blk {
              out.push(b)
            }
          }
          None => {
            zstd_write_block_header(out, last, 0, len)
            for k in 0..<len {
              out.push(data[pos + k] & 0xFF)
            }
          }
        }
      }
      pos = pos + len
    }
  }
  if with_checksum {
    let h = @infra_hash.xxhash64(data, 0)
    out.push((h & 0xFFUL).to_int())
    out.push(((h >> 8) & 0xFFUL).to_int())
    out.push(((h >> 16) & 0xFFUL).to_int())
    out.push(((h >> 24) & 0xFFUL).to_int())
  }
  out
}
