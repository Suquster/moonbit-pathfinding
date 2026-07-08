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
/// Package-Merge 长度受限 Huffman（Larmore & Hirschberg 1990）：
/// 频次 → 码长（≤ max_len），Kraft 等式取等（完备码）。
/// 返回每符号码长（0 = 不出现）；不足 2 个符号返回 None。
fn huf_lengths(freq : Array[Int], max_len : Int) -> Array[Int]? {
  let leaves : Array[(Int, Int)] = [] // (freq, symbol)
  for s in 0..<freq.length() {
    if freq[s] > 0 {
      leaves.push((freq[s], s))
    }
  }
  let n = leaves.length()
  if n < 2 {
    return None
  }
  if n > 1 << max_len {
    return None
  }
  leaves.sort_by(fn(a, b) { a.0 - b.0 })
  // 每个条目：权重 + 叶子出现次数向量。
  let mut prev : Array[(Int, Array[Int])] = []
  for _level in 0..<max_len {
    // 上一层打包成对。
    let packaged : Array[(Int, Array[Int])] = []
    let mut i = 0
    while i + 1 < prev.length() {
      let counts : Array[Int] = Array::make(n, 0)
      for k in 0..<n {
        counts[k] = prev[i].1[k] + prev[i + 1].1[k]
      }
      packaged.push((prev[i].0 + prev[i + 1].0, counts))
      i = i + 2
    }
    // 与单叶归并（皆有序）。
    let merged : Array[(Int, Array[Int])] = []
    let mut a = 0
    let mut b = 0
    while a < n || b < packaged.length() {
      let take_leaf = if a >= n {
        false
      } else if b >= packaged.length() {
        true
      } else {
        leaves[a].0 <= packaged[b].0
      }
      if take_leaf {
        let counts : Array[Int] = Array::make(n, 0)
        counts[a] = 1
        merged.push((leaves[a].0, counts))
        a = a + 1
      } else {
        merged.push(packaged[b])
        b = b + 1
      }
    }
    prev = merged
  }
  // 取顶层最便宜的 2n-2 项，叶子出现次数即码长。
  if prev.length() < 2 * n - 2 {
    return None
  }
  let lengths : Array[Int] = Array::make(freq.length(), 0)
  for i in 0..<(2 * n - 2) {
    for k in 0..<n {
      lengths[leaves[k].1] = lengths[leaves[k].1] + prev[i].1[k]
    }
  }
  Some(lengths)
}

///|
/// 由码长派生规范码（与解码表同一布局：rank 起点按权重升序、
/// 同权重按符号自然序）。返回每符号 (code, nb_bits)。
fn huf_assign_codes(lengths : Array[Int], table_log : Int) -> Array[(Int, Int)] {
  let max_w = table_log // 权重上界（len=1 → w=tableLog）。
  let rank_count : Array[Int] = Array::make(max_w + 2, 0)
  for s in 0..<lengths.length() {
    if lengths[s] > 0 {
      let w = table_log + 1 - lengths[s]
      rank_count[w] = rank_count[w] + 1
    }
  }
  let rank_start : Array[Int] = Array::make(max_w + 2, 0)
  let mut cur = 0
  for w in 1..<=(max_w + 1) {
    if w <= max_w && rank_count[w] > 0 {
      rank_start[w] = cur
      cur = cur + (rank_count[w] << (w - 1))
    } else if w <= max_w {
      rank_start[w] = cur
    }
  }
  let codes : Array[(Int, Int)] = Array::make(lengths.length(), (0, 0))
  for s in 0..<lengths.length() {
    if lengths[s] > 0 {
      let w = table_log + 1 - lengths[s]
      let span = 1 << (w - 1)
      codes[s] = (rank_start[w] >> (table_log - lengths[s]), lengths[s])
      rank_start[w] = rank_start[w] + span
    }
  }
  codes
}

///|
/// 用规范码把 lits[from..to) 编成一条逆向 Huffman 流（解码端
/// 先读首字面量 → 编码端逆序写入）。
fn huf_encode_stream(
  lits : Array[Int],
  from : Int,
  to : Int,
  codes : Array[(Int, Int)],
) -> Array[Int] {
  let bw : ZstdBitWriter = { bits: [] }
  let mut i = to - 1
  while i >= from {
    let (code, nb) = codes[lits[i]]
    bw.add(code, nb)
    i = i - 1
  }
  bw.close()
}

///|
/// 尝试把字面量段编成 Compressed(Huffman) 布局（权重 4-bit 直存 +
/// 1 流或 4 流）；无收益或超出直存权重域（max_sym > 128）返回 None。
fn huf_encode_literals(lits : Array[Int]) -> Array[Int]? {
  let regen = lits.length()
  if regen < 16 {
    return None
  }
  let freq : Array[Int] = Array::make(256, 0)
  let mut max_sym = 0
  for b in lits {
    freq[b] = freq[b] + 1
    if b > max_sym {
      max_sym = b
    }
  }
  if max_sym > 128 {
    return None // 直存权重头最多 128 个显式权重。
  }
  let lengths = match huf_lengths(freq, 11) {
    None => return None
    Some(l) => l
  }
  let mut table_log = 0
  for s in 0..<lengths.length() {
    if lengths[s] > table_log {
      table_log = lengths[s]
    }
  }
  let codes = huf_assign_codes(lengths, table_log)
  // 权重头：符号 0..max_sym-1 显式，max_sym 的权重隐式。
  let num_w = max_sym
  let wbytes : Array[Int] = []
  wbytes.push(127 + num_w)
  let mut k = 0
  while k < num_w {
    let w1 = if lengths[k] > 0 { table_log + 1 - lengths[k] } else { 0 }
    let w2 = if k + 1 < num_w {
      if lengths[k + 1] > 0 {
        table_log + 1 - lengths[k + 1]
      } else {
        0
      }
    } else {
      0
    }
    wbytes.push((w1 << 4) | w2)
    k = k + 2
  }
  // 流体：regen < 64 单流（size_format 00），否则 4 流。
  let four = regen >= 64
  let streams : Array[Int] = []
  if four {
    let c1 = (regen + 3) / 4
    let s1 = huf_encode_stream(lits, 0, c1, codes)
    let s2 = huf_encode_stream(lits, c1, 2 * c1, codes)
    let s3 = huf_encode_stream(lits, 2 * c1, 3 * c1, codes)
    let s4 = huf_encode_stream(lits, 3 * c1, regen, codes)
    streams.push(s1.length() & 0xFF)
    streams.push((s1.length() >> 8) & 0xFF)
    streams.push(s2.length() & 0xFF)
    streams.push((s2.length() >> 8) & 0xFF)
    streams.push(s3.length() & 0xFF)
    streams.push((s3.length() >> 8) & 0xFF)
    for st in [s1, s2, s3, s4] {
      for b in st {
        streams.push(b)
      }
    }
    if s1.length() > 65535 || s2.length() > 65535 || s3.length() > 65535 {
      return None
    }
  } else {
    for b in huf_encode_stream(lits, 0, regen, codes) {
      streams.push(b)
    }
  }
  let comp = wbytes.length() + streams.length()
  if comp + 5 >= regen {
    return None // 无收益（含最大头开销），回退 Raw 字面量。
  }
  // 段头：type=2，size_format 按 regen/comp 宽度选择。
  let out : Array[Int] = []
  if !four {
    // size_format 00：10+10 位（regen < 64 必然适配）。
    let v = 2 | (0 << 2) | (regen << 4) | (comp << 14)
    out.push(v & 0xFF)
    out.push((v >> 8) & 0xFF)
    out.push((v >> 16) & 0xFF)
  } else if regen <= 1023 && comp <= 1023 {
    // size_format 01：4 流，10+10 位。
    let v = 2 | (1 << 2) | (regen << 4) | (comp << 14)
    out.push(v & 0xFF)
    out.push((v >> 8) & 0xFF)
    out.push((v >> 16) & 0xFF)
  } else if regen <= 16383 && comp <= 16383 {
    // size_format 10：4 流，14+14 位。
    let v = 2 | (2 << 2) | (regen << 4) | (comp << 18)
    out.push(v & 0xFF)
    out.push((v >> 8) & 0xFF)
    out.push((v >> 16) & 0xFF)
    out.push((v >> 24) & 0xFF)
  } else {
    // size_format 11：4 流，18+18 位（UInt64 防符号位）。
    let v = 2UL |
      (3UL << 2) |
      (regen.to_uint64() << 4) |
      (comp.to_uint64() << 22)
    out.push((v & 0xFFUL).to_int())
    out.push(((v >> 8) & 0xFFUL).to_int())
    out.push(((v >> 16) & 0xFFUL).to_int())
    out.push(((v >> 24) & 0xFFUL).to_int())
    out.push(((v >> 32) & 0xFFUL).to_int())
  }
  for b in wbytes {
    out.push(b)
  }
  for b in streams {
    out.push(b)
  }
  Some(out)
}

///|
/// 频次 → 正规化计数（和恰为 2^AL；稀有符号记 -1）。
/// 分布退化（不足 2 个符号）返回 None。
fn fse_normalize(freq : Array[Int], accuracy_log : Int) -> Array[Int]? {
  let table_size = 1 << accuracy_log
  let mut total = 0
  let mut distinct = 0
  let mut last = -1
  for s in 0..<freq.length() {
    if freq[s] > 0 {
      total = total + freq[s]
      distinct = distinct + 1
      last = s
    }
  }
  if distinct < 2 || total > 0x3FFFFFFF / table_size {
    return None
  }
  let norm : Array[Int] = Array::make(last + 1, 0)
  let mut used = 0
  let mut biggest = 0
  for s in 0..<=last {
    if freq[s] > 0 {
      let scaled = freq[s] * table_size / total
      if scaled == 0 {
        norm[s] = -1
        used = used + 1
      } else {
        norm[s] = scaled
        used = used + scaled
      }
      if freq[s] > freq[biggest] {
        biggest = s
      }
    }
  }
  // 校平：差额记入/扣自最大频次符号（保持 ≥1）。
  let mut diff = table_size - used
  if diff > 0 {
    norm[biggest] = norm[biggest] + diff
  } else {
    while diff < 0 {
      let mut cut = -1
      for s in 0..<=last {
        if norm[s] > 1 && (cut < 0 || norm[s] > norm[cut]) {
          cut = s
        }
      }
      if cut < 0 {
        return None
      }
      norm[cut] = norm[cut] - 1
      diff = diff + 1
    }
  }
  Some(norm)
}

///|
/// 序列化 FSE 计数头（RFC 8878 §4.1.1，正向 LSB-first；
/// 与 fse_read_ncount 严格互逆）。
fn fse_write_ncount(norm : Array[Int], accuracy_log : Int) -> Array[Int] {
  let bits : Array[Int] = []
  fn put(v : Int, n : Int) {
    for j in 0..<n {
      bits.push((v >> j) & 1)
    }
  }

  put(accuracy_log - 5, 4)
  let table_size = 1 << accuracy_log
  let mut remaining = table_size + 1
  let mut threshold = table_size
  let mut nb_bits = accuracy_log + 1
  let mut s = 0
  let mut previous0 = false
  while remaining > 1 && s < norm.length() {
    if previous0 {
      // repeat-zero 链：先数出紧随的零串。
      let mut run = 0
      while s + run < norm.length() && norm[s + run] == 0 {
        run = run + 1
      }
      let mut left = run
      while left >= 3 {
        put(3, 2)
        left = left - 3
      }
      put(left, 2)
      s = s + run
      previous0 = false
      if remaining <= 1 || s >= norm.length() {
        break
      }
    }
    let prob = norm[s]
    let max = 2 * threshold - 1 - remaining
    let mut count = prob + 1 // -1 → 0。
    remaining = remaining - (if prob < 0 { 1 } else { prob })
    if count >= threshold {
      count = count + max
    }
    if count < max {
      put(count, nb_bits - 1)
    } else {
      put(count, nb_bits)
    }
    previous0 = prob == 0
    s = s + 1
    while remaining < threshold && remaining > 1 {
      nb_bits = nb_bits - 1
      threshold = threshold >> 1
    }
  }
  // 打包为字节（尾部补零）。
  while bits.length() % 8 != 0 {
    bits.push(0)
  }
  let out : Array[Int] = []
  let mut i = 0
  while i < bits.length() {
    let mut b = 0
    for j in 0..<8 {
      b = b | (bits[i + j] << j)
    }
    out.push(b)
    i = i + 8
  }
  out
}

///|
/// 一张序列表的编码选择：模式 + 头字节 + 编码表。
priv struct SeqTableChoice {
  mode : Int // 0=Predefined / 1=RLE / 2=FSE_Compressed
  header : Array[Int]
  table : FseEncTable? // RLE 时 None
}

///|
/// 按估算比特成本为一列符号码选表：RLE（列恒定）优先，
/// 否则比较预定义分布与自适应 FSE_Compressed 分布。
fn zstd_pick_seq_table(
  codes : Array[Int],
  default_norm : Array[Int],
  default_al : Int,
  max_al : Int,
) -> SeqTableChoice {
  let n = codes.length()
  let mut constant = true
  for c in codes {
    if c != codes[0] {
      constant = false
      break
    }
  }
  if constant {
    return { mode: 1, header: [codes[0]], table: None }
  }
  let mut max_code = 0
  let freq : Array[Int] = Array::make(default_norm.length(), 0)
  for c in codes {
    freq[c] = freq[c] + 1
    if c > max_code {
      max_code = c
    }
  }
  // 估算：bits(s) ≈ AL - highbit(norm_s)（FSE 上界）。
  fn est_bits(norm : Array[Int], al : Int) -> Int {
    let mut sum = 0
    for s in 0..<norm.length() {
      if freq.length() > s && freq[s] > 0 {
        let m = if norm[s] <= 0 { 1 } else { norm[s] }
        sum = sum + freq[s] * (al - zstd_highbit(m))
      }
    }
    sum
  }

  let pre_cost = est_bits(default_norm, default_al)
  let mut al = 5
  while 1 << al < n && al < max_al {
    al = al + 1
  }
  match fse_normalize(freq, al) {
    None => { mode: 0, header: [], table: None }
    Some(norm) => {
      let header = fse_write_ncount(norm, al)
      let custom_cost = est_bits(norm, al) + 8 * header.length()
      if custom_cost < pre_cost {
        { mode: 2, header, table: Some(fse_build_enc_table(norm, al)) }
      } else {
        { mode: 0, header: [], table: None }
      }
    }
  }
}

///|
/// 单条 LZ77 序列。
priv struct ZstdSeq {
  ll : Int
  ml : Int
  offset : Int // 真实偏移（编码时优先尝试重复偏移历史）
}

///|
/// 贪心 + 一步惰性 LZ77 匹配（4 字节哈希链，链长 ≤ 32，最小匹配 4；
/// 若 pos+1 处存在更长匹配则先放行一个字面量）：
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

  fn probe(p : Int) -> (Int, Int) {
    let mut best_len = 0
    let mut best_off = 0
    match heads.get(hash4(p)) {
      Some(chain) => {
        let mut tried = 0
        let mut ci = chain.length() - 1
        while ci >= 0 && tried < 32 {
          let cand = chain[ci]
          let mut m = 0
          while p + m < len && data[start + cand + m] == data[start + p + m] {
            m = m + 1
          }
          if m >= 4 && m > best_len {
            best_len = m
            best_off = p - cand
          }
          ci = ci - 1
          tried = tried + 1
        }
      }
      None => ()
    }
    (best_len, best_off)
  }

  fn insert(p : Int) {
    let h = hash4(p)
    match heads.get(h) {
      Some(chain) => chain.push(p)
      None => heads.set(h, [p])
    }
  }

  let mut pos = 0
  let mut lit_run = 0
  while pos + 4 <= len {
    let (best_len, best_off) = probe(pos)
    insert(pos)
    if best_len >= 4 {
      // 一步惰性：下一位若有严格更长匹配，先放行当前字节。
      if pos + 5 <= len {
        let (next_len, _) = probe(pos + 1)
        if next_len > best_len + 1 {
          lits.push(data[start + pos] & 0xFF)
          lit_run = lit_run + 1
          pos = pos + 1
          continue
        }
      }
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
/// 编码一个 Compressed 块内容（Huffman/Raw 字面量 + FSE 序列，
/// 重复偏移历史 rep 帧内跨块延续）；无收益（产物不小于 Raw 块）
/// 返回 None 且不动 rep。
fn zstd_encode_block(
  data : Array[Int],
  start : Int,
  len : Int,
  rep : Array[Int],
) -> Array[Int]? {
  let (seqs, lits) = zstd_find_sequences(data, start, len)
  if seqs.length() >= 0x7F00 {
    return None
  }
  let out : Array[Int] = []
  // ── 字面量段：Huffman 优先，无收益回退 Raw 布局 ──
  let regen = lits.length()
  match huf_encode_literals(lits) {
    Some(sec) =>
      for b in sec {
        out.push(b)
      }
    None => {
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
    }
  }
  // ── 序列段：预定义三表（序列为空时仅写 nbSeq=0）──
  let nb_seq = seqs.length()
  if nb_seq == 0 {
    out.push(0)
    if out.length() >= len {
      return None
    }
    return Some(out)
  }
  if nb_seq < 128 {
    out.push(nb_seq)
  } else {
    out.push(128 + (nb_seq >> 8))
    out.push(nb_seq & 0xFF)
  }
  // 预计算每序列码与附加位。
  let codes : Array[(Int, Int, Int, Int, Int, Int, Int, Int, Int)] = []
  let ll_col : Array[Int] = []
  let of_col : Array[Int] = []
  let ml_col : Array[Int] = []
  // 重复偏移历史（§3.1.1.5，编码端与解码端同步演算；提交前用本地副本）。
  let mut r0 = rep[0]
  let mut r1 = rep[1]
  let mut r2 = rep[2]
  for sq in seqs {
    let (llc, llb, llv) = zstd_ll_encode(sq.ll)
    let (mlc, mlb, mlv) = zstd_ml_encode(sq.ml)
    let off = sq.offset
    let ofv = if sq.ll != 0 {
      if off == r0 {
        1
      } else if off == r1 {
        2
      } else if off == r2 {
        3
      } else {
        off + 3
      }
    } else if off == r1 {
      1
    } else if off == r2 {
      2
    } else if off == r0 - 1 && off > 0 {
      3
    } else {
      off + 3
    }
    // 历史更新（与解码端逐条一致）。
    if ofv > 3 {
      r2 = r1
      r1 = r0
      r0 = off
    } else {
      let idx = if sq.ll == 0 { ofv } else { ofv - 1 }
      if idx == 1 {
        r1 = r0
        r0 = off
      } else if idx >= 2 {
        r2 = r1
        r1 = r0
        r0 = off
      }
      // idx == 0：rep1 复用，历史不变。
    }
    let ofc = zstd_highbit(ofv)
    let ofx = ofv - (1 << ofc)
    if ofc > 28 {
      return None // 超出预定义 OF 表符号域（块 ≤64KB 不会发生）。
    }
    codes.push((llc, llb, llv, mlc, mlb, mlv, ofc, ofc, ofx))
    ll_col.push(llc)
    of_col.push(ofc)
    ml_col.push(mlc)
  }
  // 每列独立选模式：Predefined / RLE / FSE_Compressed。
  let ll_pick = zstd_pick_seq_table(ll_col, zstd_ll_default(), 6, 9)
  let of_pick = zstd_pick_seq_table(of_col, zstd_of_default(), 5, 8)
  let ml_pick = zstd_pick_seq_table(ml_col, zstd_ml_default(), 6, 9)
  out.push((ll_pick.mode << 6) | (of_pick.mode << 4) | (ml_pick.mode << 2))
  for pick in [ll_pick, of_pick, ml_pick] {
    if pick.mode != 0 {
      for b in pick.header {
        out.push(b)
      }
    }
  }
  fn resolve(
    pick : SeqTableChoice,
    default_t : () -> FseEncTable,
  ) -> FseEncTable {
    match pick.table {
      Some(t) => t
      None =>
        if pick.mode == 1 {
          // RLE：AL=0 退化表（零比特初始化/迁移/冲刷）。
          {
            table_log: 0,
            state_table: [0],
            delta_nb_bits: Array::make(64, 0),
            delta_find_state: Array::make(64, 0),
          }
        } else {
          default_t()
        }
    }
  }

  let ll_t = resolve(ll_pick, fn() { fse_build_enc_table(zstd_ll_default(), 6) })
  let of_t = resolve(of_pick, fn() { fse_build_enc_table(zstd_of_default(), 5) })
  let ml_t = resolve(ml_pick, fn() { fse_build_enc_table(zstd_ml_default(), 6) })
  let bw : ZstdBitWriter = { bits: [] }
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
  rep[0] = r0
  rep[1] = r1
  rep[2] = r2
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
    let rep : Array[Int] = [1, 4, 8] // 帧级重复偏移历史（跨块延续）。
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
        match zstd_encode_block(data, pos, len, rep) {
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
