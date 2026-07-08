// lz4_frame.mbt —— LZ4 Frame Format（lz4.org Frame Format v1.6.x 规范）。
//
// 在块格式（lz4.mbt）之上补齐容器层，达成与 `lz4` CLI /
// python-lz4 `lz4.frame` 的双向互操作：
// - 魔数 0x184D2204（小端）；
// - 帧描述符 FLG（version=01、B.Indep、可选 B.Checksum/C.Size/
//   C.Checksum）+ BD（块上限档位）+ HC 头校验字节
//   （xxh32(descriptor)>>8 & 0xFF）；
// - 数据块：4 字节小端长度（最高位 1 表示未压缩原样块）+ 数据 +
//   可选 4 字节 XXH32 块校验；
// - EndMark 0x00000000 + 可选 4 字节 XXH32 内容校验（seed 0）。
//
// 测试：roundtrip PBT + python-lz4 双向黄金对拍 + 畸形输入拒绝。

///|
/// LZ4 帧压缩：64KB 独立块 + 内容校验（C.Checksum）+ 内容长度
/// （C.Size）。逐块择优：压缩无收益时存未压缩原样块，产物可被
/// 任何符合 Frame Format 的解码器还原。
pub fn lz4_frame_compress(data : Array[Int]) -> Array[Int] {
  let out : Array[Int] = [0x04, 0x22, 0x4D, 0x18]
  // FLG: version=01, B.Indep=1, C.Size=1, C.Checksum=1；BD: 64KB 档（4）。
  let desc : Array[Int] = [0x6C, 0x40]
  let n = data.length()
  for k in 0..<8 {
    // Int 移位按 mod 32 环绕，高 4 字节须显式置 0。
    desc.push(if k < 4 { (n >> (8 * k)) & 0xFF } else { 0 })
  }
  let hc = ((@infra_hash.xxhash32(desc, 0U) >> 8) & 0xFFU).reinterpret_as_int()
  for b in desc {
    out.push(b)
  }
  out.push(hc)
  let chunk = 65536
  let mut pos = 0
  while pos < n {
    let len = if n - pos < chunk { n - pos } else { chunk }
    let piece : Array[Int] = []
    for k in 0..<len {
      piece.push(data[pos + k])
    }
    let comp = lz4_compress(piece)
    if comp.length() < len {
      let sz = comp.length()
      out.push(sz & 0xFF)
      out.push((sz >> 8) & 0xFF)
      out.push((sz >> 16) & 0xFF)
      out.push((sz >> 24) & 0x7F)
      for b in comp {
        out.push(b)
      }
    } else {
      out.push(len & 0xFF)
      out.push((len >> 8) & 0xFF)
      out.push((len >> 16) & 0xFF)
      out.push(((len >> 24) & 0x7F) | 0x80)
      for b in piece {
        out.push(b)
      }
    }
    pos = pos + len
  }
  // EndMark + 内容校验。
  for _ in 0..<4 {
    out.push(0)
  }
  let cksum = @infra_hash.xxhash32(data, 0U)
  for k in 0..<4 {
    out.push(((cksum >> (8 * k)) & 0xFFU).reinterpret_as_int())
  }
  out
}

///|
/// LZ4 帧解压：校验魔数、HC 头校验、块/内容 XXH32；`max_out`
/// 为输出上限（防解压炸弹）。畸形输入（坏魔数、校验不符、
/// 截断、保留位非零、超限输出）返回 None。
pub fn lz4_frame_decompress(data : Array[Int], max_out : Int) -> Array[Int]? {
  let n = data.length()
  guard n >= 7 else { return None }
  guard data[0] == 0x04 && data[1] == 0x22 && data[2] == 0x4D && data[3] == 0x18 else {
    None
  }
  let flg = data[4]
  guard flg >> 6 == 1 && (flg & 0x02) == 0 else { return None } // 版本 + 保留位。
  let block_indep = (flg & 0x20) != 0
  let block_checksum = (flg & 0x10) != 0
  let content_size = (flg & 0x08) != 0
  let content_checksum = (flg & 0x04) != 0
  let dict_id = (flg & 0x01) != 0
  let bd = data[5]
  guard (bd & 0x8F) == 0 && bd >> 4 >= 4 && bd >> 4 <= 7 else { return None }
  let desc_len = 2 +
    (if content_size { 8 } else { 0 }) +
    (if dict_id { 4 } else { 0 })
  guard n >= 4 + desc_len + 1 else { return None }
  let desc : Array[Int] = []
  for k in 0..<desc_len {
    desc.push(data[4 + k])
  }
  let hc = ((@infra_hash.xxhash32(desc, 0U) >> 8) & 0xFFU).reinterpret_as_int()
  guard data[4 + desc_len] == hc else { return None }
  let mut expect = -1
  if content_size {
    let mut v = 0
    for k in 0..<4 {
      v = v | (data[6 + k] << (8 * k))
    }
    // 高 4 字节须为 0（本实现输出上限受 max_out 约束）。
    for k in 4..<8 {
      guard data[6 + k] == 0 else { return None }
    }
    expect = v
    guard expect >= 0 && expect <= max_out else { return None }
  }
  let out : Array[Int] = []
  let mut i = 4 + desc_len + 1
  while true {
    guard i + 4 <= n else { return None }
    let uncompressed = (data[i + 3] & 0x80) != 0
    let sz = data[i] |
      (data[i + 1] << 8) |
      (data[i + 2] << 16) |
      ((data[i + 3] & 0x7F) << 24)
    i = i + 4
    if sz == 0 && !uncompressed {
      break // EndMark。
    }
    guard i + sz <= n else { return None }
    let piece : Array[Int] = []
    for k in 0..<sz {
      piece.push(data[i + k])
    }
    i = i + sz
    if block_checksum {
      guard i + 4 <= n else { return None }
      let want = @infra_hash.xxhash32(piece, 0U)
      let mut got = 0U
      for k in 0..<4 {
        got = got | (data[i + k].reinterpret_as_uint() << (8 * k))
      }
      guard got == want else { return None }
      i = i + 4
    }
    if uncompressed {
      guard out.length() + sz <= max_out else { return None }
      for b in piece {
        out.push(b)
      }
    } else if block_indep {
      match lz4_decompress(piece, max_out - out.length()) {
        None => return None
        Some(dec) =>
          for b in dec {
            out.push(b)
          }
      }
    } else {
      // block-linked：既有输出充当匹配历史。
      guard lz4_decompress_into(piece, out, max_out) else { return None }
    }
  }
  if content_checksum {
    guard i + 4 <= n else { return None }
    let want = @infra_hash.xxhash32(out, 0U)
    let mut got = 0U
    for k in 0..<4 {
      got = got | (data[i + k].reinterpret_as_uint() << (8 * k))
    }
    guard got == want else { return None }
  }
  if expect >= 0 {
    guard out.length() == expect else { return None }
  }
  Some(out)
}
