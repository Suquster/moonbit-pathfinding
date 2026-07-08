// zstd.mbt —— Zstandard 帧格式（RFC 8878 §3）。
//
// paper-to-code：Collet & Kucherawy *RFC 8878 Zstandard Compression*：
// - 帧 = 魔数 0xFD2FB528（小端）+ 帧头（FHD 描述符 / Window_Descriptor /
//   Dictionary_ID / Frame_Content_Size）+ 块序列 + 可选 XXH64 低 32 位校验；
// - 块头 3 字节小端：bit0 Last_Block、bit1-2 Block_Type（0 Raw / 1 RLE /
//   2 Compressed / 3 Reserved）、bit3-23 Block_Size；
// - RLE 块内容 1 字节、Block_Size 为再生长度；
// - 跳过帧：魔数 0x184D2A50..0x184D2A5F + 4 字节小端长度，解码器直接跳过。
//
// 范围声明（诚实边界）：本实现覆盖帧格式全链 + Raw/RLE 块 + XXH64 校验 +
// 跳过帧 + 多帧级联；Compressed 块（FSE/Huffman 熵编码，RFC 8878 §4）
// 不在本层范围，遇到显式返回 None（不静默出错数据）。压缩侧输出为
// Raw/RLE 块的合法 zstd 帧，任何符合 RFC 8878 的解码器（含参考 zstd
// CLI / python-zstandard）均可无损还原，已作外部互通对拍。
//
// 测试：roundtrip PBT + python-zstandard 黄金帧解码 + 畸形拒绝 +
// 解压炸弹上限 + 跳过帧/多帧级联。

///|
/// zstd 帧魔数 0xFD2FB528 的四个小端字节。
fn zstd_magic() -> Array[Int] {
  [0x28, 0xB5, 0x2F, 0xFD]
}

///|
/// 读小端无符号整数（width ∈ 1..8，返回 UInt64）；越界返回 None。
fn zstd_read_le(data : Array[Int], pos : Int, width : Int) -> UInt64? {
  if pos + width > data.length() {
    return None
  }
  let mut v = 0UL
  for k in 0..<width {
    v = v | ((data[pos + k] & 0xFF).to_uint64() << (8 * k))
  }
  Some(v)
}

///|
/// 写 3 字节小端块头（Last_Block / Block_Type / Block_Size）。
fn zstd_write_block_header(
  out : Array[Int],
  last : Bool,
  block_type : Int,
  size : Int,
) -> Unit {
  let header = (if last { 1 } else { 0 }) | (block_type << 1) | (size << 3)
  out.push(header & 0xFF)
  out.push((header >> 8) & 0xFF)
  out.push((header >> 16) & 0xFF)
}

///|
/// Zstandard 压缩（RFC 8878 帧格式，Raw/RLE 块）：
/// 单段帧（Single_Segment_Flag=1，帧内容长度即窗口），
/// 全同字节分片走 RLE 块，其余走 Raw 块；`with_checksum`
/// 追加 XXH64(content, 0) 低 32 位小端校验。
/// 输出为任何 RFC 8878 解码器可还原的合法 zstd 帧。
pub fn zstd_compress(data : Array[Int], with_checksum : Bool) -> Array[Int] {
  let n = data.length()
  let out : Array[Int] = []
  for b in zstd_magic() {
    out.push(b)
  }
  // FHD：FCS_flag(bit7-6) | Single_Segment(bit5) | Checksum(bit2) | Dict(bit1-0)=0
  let fcs_flag = if n <= 255 { 0 } else if n - 256 <= 65535 { 1 } else { 2 }
  let checksum_bit = if with_checksum { 4 } else { 0 }
  out.push((fcs_flag << 6) | 0x20 | checksum_bit)
  // Single_Segment：无 Window_Descriptor，FCS 必须出现（flag 0 → 1 字节）。
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
  // 块序列：分片 ≤ 64 KiB（≤ Block_Maximum_Size），全同字节走 RLE。
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
        zstd_write_block_header(out, last, 0, len)
        for k in 0..<len {
          out.push(data[pos + k] & 0xFF)
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

///|
/// 解单个 zstd 帧的块序列到 out；返回帧内容结束后的偏移，畸形返回 None。
fn zstd_decode_blocks(
  data : Array[Int],
  start : Int,
  out : Array[Int],
  max_out : Int,
) -> Int? {
  let n = data.length()
  let mut pos = start
  let mut last = false
  while !last {
    match zstd_read_le(data, pos, 3) {
      None => return None
      Some(h) => {
        let header = h.to_int()
        pos = pos + 3
        last = (header & 1) == 1
        let block_type = (header >> 1) & 3
        let size = header >> 3
        if block_type == 0 {
          // Raw 块：原样拷贝。
          if pos + size > n || out.length() + size > max_out {
            return None
          }
          for k in 0..<size {
            out.push(data[pos + k] & 0xFF)
          }
          pos = pos + size
        } else if block_type == 1 {
          // RLE 块：1 字节重复 size 次。
          if pos >= n || out.length() + size > max_out {
            return None
          }
          let b = data[pos] & 0xFF
          pos = pos + 1
          for _k in 0..<size {
            out.push(b)
          }
        } else {
          // Compressed（范围外）与 Reserved 一律显式拒绝。
          return None
        }
      }
    }
  }
  Some(pos)
}

///|
/// Zstandard 解压（RFC 8878 帧格式，Raw/RLE 块）：支持多帧级联与
/// 跳过帧，校验帧存在时验证 XXH64 低 32 位；`max_out` 为输出上限
/// （防解压炸弹）。Compressed/Reserved 块、字典帧、保留位、
/// FCS 不符、校验失败、截断输入一律返回 None。
pub fn zstd_decompress(data : Array[Int], max_out : Int) -> Array[Int]? {
  let n = data.length()
  let out : Array[Int] = []
  let mut pos = 0
  while pos < n {
    let magic = match zstd_read_le(data, pos, 4) {
      None => return None
      Some(v) => v
    }
    pos = pos + 4
    // 跳过帧：0x184D2A50..0x184D2A5F。
    if magic >= 0x184D2A50UL && magic <= 0x184D2A5FUL {
      let size = match zstd_read_le(data, pos, 4) {
        None => return None
        Some(v) => v.to_int()
      }
      pos = pos + 4
      if pos + size > n {
        return None
      }
      pos = pos + size
      continue
    }
    if magic != 0xFD2FB528UL {
      return None
    }
    if pos >= n {
      return None
    }
    let fhd = data[pos] & 0xFF
    pos = pos + 1
    let fcs_flag = fhd >> 6
    let single_segment = (fhd & 0x20) != 0
    let checksum = (fhd & 0x04) != 0
    let dict_flag = fhd & 0x03
    if (fhd & 0x08) != 0 {
      // Reserved bit 必须为 0（RFC 8878 §3.1.1.1.1）。
      return None
    }
    if !single_segment {
      // Window_Descriptor 1 字节（仅取帧合法性，Raw/RLE 解码无需窗口）。
      if pos >= n {
        return None
      }
      pos = pos + 1
    }
    if dict_flag != 0 {
      // 字典帧不在范围内，显式拒绝。
      return None
    }
    // FCS 字段宽度：flag 0 → 单段 1 字节 / 非单段缺省；1→2；2→4；3→8。
    let fcs_width = if fcs_flag == 0 {
      if single_segment {
        1
      } else {
        0
      }
    } else if fcs_flag == 1 {
      2
    } else if fcs_flag == 2 {
      4
    } else {
      8
    }
    let mut expect : Int = -1
    if fcs_width > 0 {
      match zstd_read_le(data, pos, fcs_width) {
        None => return None
        Some(v) => {
          let base = if fcs_width == 2 { 256UL } else { 0UL }
          let total = v + base
          if total > max_out.to_uint64() {
            return None
          }
          expect = total.to_int()
        }
      }
      pos = pos + fcs_width
    }
    let frame_start = out.length()
    match zstd_decode_blocks(data, pos, out, max_out) {
      None => return None
      Some(next) => pos = next
    }
    if expect >= 0 && out.length() - frame_start != expect {
      return None
    }
    if checksum {
      let stored = match zstd_read_le(data, pos, 4) {
        None => return None
        Some(v) => v
      }
      pos = pos + 4
      let frame_content : Array[Int] = []
      for k in frame_start..<out.length() {
        frame_content.push(out[k])
      }
      let h = @infra_hash.xxhash64(frame_content, 0) & 0xFFFFFFFFUL
      if h != stored {
        return None
      }
    }
  }
  Some(out)
}
