// lz4_frame_gaps_wbtest.mbt —— LZ4 帧格式防御分支收口
// （INFRA 第二十三批）：不可压块原样存储、帧头/块级畸形拒绝、
// 块校验和（B.Checksum）通路。

///|
/// 生成不可压伪随机字节串（线性同余）。
fn lz4_incompressible(n : Int) -> Array[Int] {
  let out : Array[Int] = []
  let mut x = 12345
  for _ in 0..<n {
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    out.push((x >> 16) & 0xFF)
  }
  out
}

///|
test "lz4_frame：不可压数据走原样块并回环" {
  let data = lz4_incompressible(128)
  let framed = lz4_frame_compress(data)
  match lz4_frame_decompress(framed, 1024) {
    Some(out) => assert_true(out == data)
    None => assert_true(false)
  }
}

///|
test "lz4_frame_decompress：帧头畸形逐分支拒绝" {
  // 长度不足 7。
  assert_true(lz4_frame_decompress([0x04, 0x22, 0x4D], 16) is None)
  // FLG 版本位错误。
  assert_true(
    lz4_frame_decompress([0x04, 0x22, 0x4D, 0x18, 0x00, 0x40, 0x00], 16) is None,
  )
  // BD 块大小档非法。
  assert_true(
    lz4_frame_decompress([0x04, 0x22, 0x4D, 0x18, 0x60, 0x00, 0x00], 16) is None,
  )
  // 含 content-size 的描述符长度不足。
  assert_true(
    lz4_frame_decompress([0x04, 0x22, 0x4D, 0x18, 0x68, 0x40, 0x00], 16) is None,
  )
}

///|
/// 构造最小帧头（FLG 可指定），返回含正确头校验的字节数组。
fn lz4_header(flg : Int) -> Array[Int] {
  let desc : Array[Int] = [flg, 0x40]
  let hc = ((@infra_hash.xxhash32(desc, 0U) >> 8) & 0xFFU).reinterpret_as_int()
  let out : Array[Int] = [0x04, 0x22, 0x4D, 0x18]
  for b in desc {
    out.push(b)
  }
  out.push(hc)
  out
}

///|
test "lz4_frame_decompress：块体截断与块数据越界拒绝" {
  // 块头声明 5 字节但仅 2 字节数据。
  let d = lz4_header(0x60)
  for b in [0x05, 0x00, 0x00, 0x80, 0x61, 0x62] {
    d.push(b)
  }
  assert_true(lz4_frame_decompress(d, 64) is None)
}

///|
test "lz4_frame_decompress：块校验和通路（正确/错误/截断）" {
  // FLG=0x70：B.Indep + B.Checksum。
  let base = lz4_header(0x70)
  let cks = @infra_hash.xxhash32([0x61], 0U)
  // 正确校验和 + EndMark → 成功。
  let good = base.copy()
  for b in [0x01, 0x00, 0x00, 0x80, 0x61] {
    good.push(b)
  }
  for k in 0..<4 {
    good.push(((cks >> (8 * k)) & 0xFFU).reinterpret_as_int())
  }
  for b in [0x00, 0x00, 0x00, 0x00] {
    good.push(b)
  }
  match lz4_frame_decompress(good, 16) {
    Some(out) => assert_true(out == [0x61])
    None => assert_true(false)
  }
  // 校验和错误 → 拒绝。
  let bad = base.copy()
  for b in [0x01, 0x00, 0x00, 0x80, 0x61, 0xDE, 0xAD, 0xBE, 0xEF] {
    bad.push(b)
  }
  assert_true(lz4_frame_decompress(bad, 16) is None)
  // 校验和区截断 → 拒绝。
  let cut = base.copy()
  for b in [0x01, 0x00, 0x00, 0x80, 0x61, 0x00] {
    cut.push(b)
  }
  assert_true(lz4_frame_decompress(cut, 16) is None)
}

///|
test "lz4_frame_decompress：原样块超出输出上限拒绝" {
  let d = lz4_header(0x60)
  for b in [0x02, 0x00, 0x00, 0x80, 0x61, 0x62, 0x00, 0x00, 0x00, 0x00] {
    d.push(b)
  }
  assert_true(lz4_frame_decompress(d, 1) is None)
}

///|
test "lz4_frame_decompress：压缩块体损坏拒绝" {
  // 声明压缩块但 LZ4 序列非法（token 引用不存在的历史）。
  let d = lz4_header(0x60)
  for b in [0x01, 0x00, 0x00, 0x00, 0xF0, 0x00, 0x00, 0x00, 0x00] {
    d.push(b)
  }
  assert_true(lz4_frame_decompress(d, 16) is None)
}
