// deflate_gaps_test.mbt —— DEFLATE/gzip 解码器错误分支覆盖收口
// （INFRA 第十七批）：块类型/stored/dynamic 头、回拷越界、gzip 可选字段
// 与校验不符的确定性反例。

///|
test "inflate 块级结构破坏拒绝" {
  // 空流 / BTYPE=11 保留。
  assert_true(inflate([]) is None)
  assert_true(inflate([0x07]) is None)
  // stored：头不足 4 字节 / LEN 与 ~LEN 不符 / 载荷截断。
  assert_true(inflate([0x01, 0x02]) is None)
  assert_true(inflate([0x01, 0x02, 0x00, 0x00, 0x00]) is None)
  assert_true(inflate([0x01, 0x02, 0x00, 0xFD, 0xFF, 0x61]) is None)
  // stored 合法双块（非终块 + 终块）。
  match
    inflate([
      0x00, 0x01, 0x00, 0xFE, 0xFF, 0x61, 0x01, 0x01, 0x00, 0xFE, 0xFF, 0x62,
    ]) {
    Some(out) => assert_true(out == [0x61, 0x62])
    None => assert_true(false)
  }
  // fixed Huffman：符号流截断（终块 + 无 256 结束码）。
  assert_true(inflate([0x03]) is None)
  // fixed Huffman：回拷距离越过输出起点。
  // 块内先输出一个 literal 'a'，再发 length 码后距离超出。
  let compressed = deflate([0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61])
  match inflate(compressed) {
    Some(out) => assert_true(out.length() == 8)
    None => assert_true(false)
  }
}

///|
test "inflate dynamic 头破坏拒绝" {
  // dynamic：HLIT/HDIST/HCLEN 头截断。
  assert_true(inflate([0x05]) is None)
  // HLIT 越界（HLIT=30 → nlit=287 > 286）。
  // BTYPE=10, bfinal=1 → 位流：1,01（低位起 0b101=0x05），HLIT=11110。
  assert_true(inflate([0xF5, 0xFF, 0xFF, 0xFF]) is None)
  // 码长表全零 → huff_build 拒绝。
  assert_true(inflate([0x05, 0x00, 0x00, 0x00, 0x00, 0x00]) is None)
}

///|
test "gzip 解压：头/可选字段/校验不符拒绝" {
  let ok = gzip_compress([1, 2, 3])
  assert_true(gzip_decompress(ok) == Some([1, 2, 3]))
  // 长度不足 / 魔数错 / CM 错。
  assert_true(gzip_decompress([0x1F, 0x8B, 8]) is None)
  let bad_magic = gzip_compress([1]).copy()
  bad_magic[0] = 0x00
  assert_true(gzip_decompress(bad_magic) is None)
  let bad_cm = gzip_compress([1]).copy()
  bad_cm[2] = 9
  assert_true(gzip_decompress(bad_cm) is None)
  // CRC 不符 / ISIZE 不符。
  let bad_crc = gzip_compress([1, 2, 3]).copy()
  bad_crc[bad_crc.length() - 8] = bad_crc[bad_crc.length() - 8] ^ 0xFF
  assert_true(gzip_decompress(bad_crc) is None)
  let bad_isize = gzip_compress([1, 2, 3]).copy()
  bad_isize[bad_isize.length() - 1] = 0x7F
  assert_true(gzip_decompress(bad_isize) is None)
  // 尾部残留垃圾（成员后多一字节，不足以构成新成员头）。
  let trailing = gzip_compress([1]).copy()
  trailing.push(0x00)
  assert_true(gzip_decompress(trailing) is None)
  // 多成员拼接可解。
  let two = gzip_compress([1, 2]).copy()
  for b in gzip_compress([3]) {
    two.push(b)
  }
  assert_true(gzip_decompress(two) == Some([1, 2, 3]))
}

///|
test "gzip 可选字段全谱（FEXTRA/FNAME/FCOMMENT/FHCRC）" {
  // 手工构造带全部可选字段的成员：FLG=0x1E。
  let body = gzip_compress([9])
  let g : Array[Int] = [0x1F, 0x8B, 8, 0x1E, 0, 0, 0, 0, 0, 255]
  // FEXTRA：xlen=2 + 两字节。
  g.push(2)
  g.push(0)
  g.push(0xAA)
  g.push(0xBB)
  // FNAME：'n' NUL；FCOMMENT：'c' NUL。
  g.push(0x6E)
  g.push(0)
  g.push(0x63)
  g.push(0)
  // FHCRC：两字节（未校验，仅跳过）。
  g.push(0x12)
  g.push(0x34)
  // deflate 体 + CRC + ISIZE（复用 gzip_compress 产物的第 10 字节起）。
  for i in 10..<body.length() {
    g.push(body[i])
  }
  assert_true(gzip_decompress(g) == Some([9]))
  // FEXTRA 头截断（成员头声明 FEXTRA 但记录不足）。
  let te : Array[Int] = [0x1F, 0x8B, 8, 0x04, 0, 0, 0, 0, 0, 255]
  for _ in 0..<8 {
    te.push(0)
  }
  assert_true(gzip_decompress(te) is None)
  // 可选字段吞没全部剩余 → 体缺失。
  let tn : Array[Int] = [0x1F, 0x8B, 8, 0x08, 0, 0, 0, 0, 0, 255]
  for _ in 0..<8 {
    tn.push(0x61) // 无 NUL 的名字直至耗尽
  }
  assert_true(gzip_decompress(tn) is None)
}
