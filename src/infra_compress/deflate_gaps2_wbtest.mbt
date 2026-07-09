// deflate_gaps2_wbtest.mbt —— DEFLATE 解码器深层防御分支收口
// （INFRA 第二十三批）：inflate_block 符号/额外位/距离异常、
// dynamic 头逐分支截断、全零距离表退化、gzip 尾部越界。

///|
/// 把位序列（每元素 0/1）按 LSB-first 打包为字节流（尾部补零）。
fn pack_bits(bits : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  let mut i = 0
  while i < bits.length() {
    let mut b = 0
    for j in 0..<8 {
      if i + j < bits.length() && bits[i + j] != 0 {
        b = b | (1 << j)
      }
    }
    out.push(b)
    i = i + 8
  }
  out
}

///|
/// 向位数组追加 v 的低 n 位（LSB-first）。
fn put_bits(bits : Array[Int], v : Int, n : Int) -> Unit {
  for j in 0..<n {
    bits.push((v >> j) & 1)
  }
}

///|
test "inflate_block：长度符号 >285 拒绝" {
  // literal 表仅含 256（码 0）与 286（码 1），码长均为 1。
  let lens : Array[Int] = Array::make(287, 0)
  lens[256] = 1
  lens[286] = 1
  guard huff_build(lens) is Some(lit)
  guard huff_build(Array::make(30, 5)) is Some(dist)
  // 首位 1 → 符号 286 > 285。
  assert_false(inflate_block(BitReader::new([0x01]), lit, dist, []))
}

///|
test "inflate_block：长度额外位截断拒绝" {
  // 256/265 各 8 位码（0x00/0x01）；265 需 1 个额外位。
  let lens : Array[Int] = Array::make(266, 0)
  lens[256] = 8
  lens[265] = 8
  guard huff_build(lens) is Some(lit)
  guard huff_build(Array::make(30, 5)) is Some(dist)
  // 0x80：LSB-first 读出 0,0,...,1 → 码 1 → 符号 265，随后额外位耗尽。
  assert_false(inflate_block(BitReader::new([0x80]), lit, dist, []))
}

///|
test "inflate_block：距离符号解码失败拒绝" {
  let lens : Array[Int] = Array::make(258, 0)
  lens[256] = 8
  lens[257] = 8
  guard huff_build(lens) is Some(lit)
  guard huff_build(Array::make(30, 5)) is Some(dist)
  // 解出 257（长度 3，无额外位）后距离位流耗尽。
  assert_false(inflate_block(BitReader::new([0x80]), lit, dist, []))
}

///|
test "inflate_block：距离额外位截断拒绝" {
  let lens : Array[Int] = Array::make(258, 0)
  lens[256] = 8
  lens[257] = 8
  guard huff_build(lens) is Some(lit)
  // 距离表仅符号 4（8 位码 0x00），需 1 个额外位。
  let dlens : Array[Int] = Array::make(30, 0)
  dlens[4] = 8
  guard huff_build(dlens) is Some(dist)
  assert_false(inflate_block(BitReader::new([0x80, 0x00]), lit, dist, []))
}

///|
test "inflate_block：回拷距离越过输出起点拒绝" {
  let lens : Array[Int] = Array::make(258, 0)
  lens[256] = 8
  lens[257] = 8
  guard huff_build(lens) is Some(lit)
  // 距离符号 0（基数 1，无额外位）但输出为空 → 距离 1 > 0。
  let dlens : Array[Int] = Array::make(30, 0)
  dlens[0] = 8
  guard huff_build(dlens) is Some(dist)
  assert_false(inflate_block(BitReader::new([0x80, 0x00]), lit, dist, []))
}

///|
/// dynamic 头公共前缀：HLIT=0 / HDIST=0 / HCLEN=0（nclen=4），
/// 四个 3 位码长（顺序 16,17,18,0）。
fn dyn_header4(
  bits : Array[Int],
  l16 : Int,
  l17 : Int,
  l18 : Int,
  l0 : Int,
) -> Unit {
  put_bits(bits, 0, 5)
  put_bits(bits, 0, 5)
  put_bits(bits, 0, 4)
  put_bits(bits, l16, 3)
  put_bits(bits, l17, 3)
  put_bits(bits, l18, 3)
  put_bits(bits, l0, 3)
}

///|
test "inflate_dynamic_tables：码长字段截断拒绝" {
  // 2 字节 = 16 位，头 14 位后第一个 3 位码长读取失败。
  assert_true(inflate_dynamic_tables(BitReader::new([0x00, 0x00])) is None)
}

///|
test "inflate_dynamic_tables：码长符号流耗尽拒绝" {
  // clen 表：sym0 码长 1（码 '0'）；剩余 6 位解出六个 0 后耗尽。
  let bits : Array[Int] = []
  dyn_header4(bits, 0, 0, 0, 1)
  assert_true(inflate_dynamic_tables(BitReader::new(pack_bits(bits))) is None)
}

///|
test "inflate_dynamic_tables：符号 16 无前驱拒绝" {
  // clen 表：sym16 码长 1（码 '0'）、sym0 码长 2（码 '10'）。
  let bits : Array[Int] = []
  dyn_header4(bits, 1, 0, 0, 2)
  put_bits(bits, 0, 1) // sym16，lengths 为空。
  assert_true(inflate_dynamic_tables(BitReader::new(pack_bits(bits))) is None)
}

///|
test "inflate_dynamic_tables：符号 16 重复计数截断拒绝" {
  let bits : Array[Int] = []
  dyn_header4(bits, 1, 0, 0, 2)
  // sym0('10') ×2 填充 4 位，sym16('0') 后仅剩 1 位 < 2。
  put_bits(bits, 1, 1)
  put_bits(bits, 0, 1)
  put_bits(bits, 1, 1)
  put_bits(bits, 0, 1)
  put_bits(bits, 0, 1)
  assert_true(inflate_dynamic_tables(BitReader::new(pack_bits(bits))) is None)
}

///|
test "inflate_dynamic_tables：符号 17 重复计数截断拒绝" {
  // clen 表：sym17 码长 1、sym0 码长 2。
  let bits : Array[Int] = []
  dyn_header4(bits, 0, 1, 0, 2)
  put_bits(bits, 1, 1)
  put_bits(bits, 0, 1)
  put_bits(bits, 1, 1)
  put_bits(bits, 0, 1)
  put_bits(bits, 0, 1) // sym17 后仅剩 1 位 < 3。
  assert_true(inflate_dynamic_tables(BitReader::new(pack_bits(bits))) is None)
}

///|
test "inflate_dynamic_tables：符号 18 重复计数截断拒绝" {
  // clen 表：sym18 码长 1、sym0 码长 2。
  let bits : Array[Int] = []
  dyn_header4(bits, 0, 0, 1, 2)
  put_bits(bits, 1, 1)
  put_bits(bits, 0, 1)
  put_bits(bits, 1, 1)
  put_bits(bits, 0, 1)
  put_bits(bits, 0, 1) // sym18 后仅剩 1 位 < 7。
  assert_true(inflate_dynamic_tables(BitReader::new(pack_bits(bits))) is None)
}

///|
test "inflate_dynamic_tables：重复串越过总长拒绝" {
  // 仅 sym18 码长 1；两次 130 零重复 → 260 > 258。
  let bits : Array[Int] = []
  dyn_header4(bits, 0, 0, 1, 0)
  put_bits(bits, 0, 1)
  put_bits(bits, 119, 7) // 130 个零。
  put_bits(bits, 0, 1)
  put_bits(bits, 119, 7) // 再 130 个 → 260。
  assert_true(inflate_dynamic_tables(BitReader::new(pack_bits(bits))) is None)
}

///|
/// 构造 dynamic 块位流：literal 表仅 sym0 与 sym256（码长 1），
/// 距离码长全零（触发退化占位表），块体由调用方追加。
fn dyn_all_zero_dist_prefix() -> Array[Int] {
  let bits : Array[Int] = []
  put_bits(bits, 1, 1) // bfinal=1
  put_bits(bits, 2, 2) // btype=10 dynamic
  put_bits(bits, 0, 5) // HLIT=0 → nlit=257
  put_bits(bits, 0, 5) // HDIST=0 → ndist=1
  put_bits(bits, 14, 4) // HCLEN=14 → nclen=18（覆盖 sym1）
  // 码长表：sym18→1，sym0→2，sym1→2，其余 0。
  for i in 0..<18 {
    let v = if i == 2 { 1 } else if i == 3 || i == 17 { 2 } else { 0 }
    put_bits(bits, v, 3)
  }
  // 码长序列：sym1（lit0 码长 1）、255 个零（138+117）、
  // sym1（lit256 码长 1）、sym0（dist 码长 0）。
  put_bits(bits, 1, 1)
  put_bits(bits, 1, 1) // sym1='11'
  put_bits(bits, 0, 1)
  put_bits(bits, 127, 7) // sym18 rep 127 → 138 零
  put_bits(bits, 0, 1)
  put_bits(bits, 106, 7) // sym18 rep 106 → 117 零
  put_bits(bits, 1, 1)
  put_bits(bits, 1, 1) // sym1
  put_bits(bits, 1, 1)
  put_bits(bits, 0, 1) // sym0='10'
  bits
}

///|
test "inflate：全零距离表退化占位（纯 literal 块）" {
  let bits = dyn_all_zero_dist_prefix()
  put_bits(bits, 1, 1) // 块体：直接发 256 结束码。
  match inflate(pack_bits(bits)) {
    Some(out) => assert_eq(out.length(), 0)
    None => assert_true(false)
  }
}

///|
test "inflate：dynamic 表合法但块体损坏拒绝" {
  let bits = dyn_all_zero_dist_prefix()
  put_bits(bits, 0, 1) // 块体：literal 0，随后位流耗尽（无 256）。
  assert_true(inflate(pack_bits(bits)) is None)
}

///|
test "gzip_decompress：deflate 体吞入尾部导致校验区越界拒绝" {
  // stored 块 body_end=16，body_end+8=24 > n=19。
  let data : Array[Int] = [
    0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 0, // 头 10 字节
     0x01, 0x01, 0x00, 0xFE, 0xFF, 0x61, // stored 终块，1 字节载荷
     0, 0, 0, // 不足 8 字节尾部
  ]
  assert_true(gzip_decompress(data) is None)
}
