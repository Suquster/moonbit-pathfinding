// lz4.mbt —— LZ4 块格式（lz4.org Block Format 规范）。
//
// paper-to-code：Collet *LZ4 Block Format Description*（v1.9 文档）：
// - 序列 = token（高 4 位 literal 长 / 低 4 位 match 长-4）+ literals +
//   2 字节小端 offset + 可选长度扩展字节（255 级联）；
// - match 最短 4 字节（MINMATCH）；块末尾必须是纯 literal 序列，
//   且末 5 字节不得作为 match 起点（end-of-block 约束，压缩器侧遵守）；
// - offset ∈ [1, 65535]，支持 overlap copy（offset < match 长，
//   RLE 式逐字节复制语义）；
// - 压缩器用 4 字节哈希表贪心匹配（参考实现 LZ4_compress_default 同族）。
//
// 测试：roundtrip + overlap copy + python-lz4 `lz4.block` 黄金向量 + PBT。

///|
/// LZ4 块解压（Block Format 规范）：`max_out` 为输出上限（防解压炸弹）。
/// 畸形输入（越界 offset、截断序列、超限输出）返回 None。
pub fn lz4_decompress(data : Array[Int], max_out : Int) -> Array[Int]? {
  let out : Array[Int] = []
  if lz4_decompress_into(data, out, max_out) {
    Some(out)
  } else {
    None
  }
}

///|
/// LZ4 块解压到既有输出缓冲（`out` 中已有内容充当匹配历史，
/// 供帧格式 block-linked 模式使用）。成功返回 true。
fn lz4_decompress_into(
  data : Array[Int],
  out : Array[Int],
  max_out : Int,
) -> Bool {
  let n = data.length()
  let mut i = 0
  if n == 0 {
    return true
  }
  while i < n {
    let token = data[i] & 0xFF
    i = i + 1
    // literal 长度（15 级联 255 扩展）。
    let mut lit_len = token >> 4
    if lit_len == 15 {
      while i < n {
        let b = data[i] & 0xFF
        i = i + 1
        lit_len = lit_len + b
        if b != 255 {
          break
        }
      }
    }
    if i + lit_len > n || out.length() + lit_len > max_out {
      return false
    }
    for k in 0..<lit_len {
      out.push(data[i + k] & 0xFF)
    }
    i = i + lit_len
    // 块末纯 literal 序列：无 offset。
    if i >= n {
      break
    }
    if i + 2 > n {
      return false
    }
    let offset = (data[i] & 0xFF) | ((data[i + 1] & 0xFF) << 8)
    i = i + 2
    if offset == 0 || offset > out.length() {
      return false
    }
    let mut match_len = (token & 0x0F) + 4
    if (token & 0x0F) == 15 {
      while i < n {
        let b = data[i] & 0xFF
        i = i + 1
        match_len = match_len + b
        if b != 255 {
          break
        }
      }
    }
    if out.length() + match_len > max_out {
      return false
    }
    // overlap copy 语义：逐字节自引用复制。
    let base = out.length() - offset
    for k in 0..<match_len {
      out.push(out[base + k])
    }
  }
  true
}

///|
/// 4 字节序列哈希（LZ4 参考实现同款乘数 2654435761 = Knuth 黄金比）。
fn lz4_hash(data : Array[Int], i : Int) -> Int {
  let seq = (data[i] & 0xFF).reinterpret_as_uint() |
    ((data[i + 1] & 0xFF).reinterpret_as_uint() << 8) |
    ((data[i + 2] & 0xFF).reinterpret_as_uint() << 16) |
    ((data[i + 3] & 0xFF).reinterpret_as_uint() << 24)
  ((seq * 2654435761U) >> 20).reinterpret_as_int() & 0xFFF
}

///|
/// 写 LZ4 级联长度扩展（15/255 级联）。
fn lz4_write_len(out : Array[Int], len : Int) -> Unit {
  let mut rest = len
  while rest >= 255 {
    out.push(255)
    rest = rest - 255
  }
  out.push(rest)
}

///|
/// 输出一个 LZ4 序列（token + literals + offset + matchlen 扩展）。
fn lz4_emit(
  out : Array[Int],
  data : Array[Int],
  lit_start : Int,
  lit_len : Int,
  offset : Int,
  match_len : Int,
) -> Unit {
  let lit_tok = if lit_len >= 15 { 15 } else { lit_len }
  if match_len >= 0 {
    let m = match_len - 4
    let m_tok = if m >= 15 { 15 } else { m }
    out.push((lit_tok << 4) | m_tok)
  } else {
    out.push(lit_tok << 4)
  }
  if lit_len >= 15 {
    lz4_write_len(out, lit_len - 15)
  }
  for k in 0..<lit_len {
    out.push(data[lit_start + k] & 0xFF)
  }
  if match_len >= 0 {
    out.push(offset & 0xFF)
    out.push((offset >> 8) & 0xFF)
    if match_len - 4 >= 15 {
      lz4_write_len(out, match_len - 4 - 15)
    }
  }
}

///|
/// LZ4 块压缩（贪心 + 4KiB 哈希表，LZ4_compress_default 同族策略）：
/// 遵守 end-of-block 约束（末 5 字节纯 literal、match 不越 mflimit）。
/// 输出可由 `lz4_decompress` 无损还原。
pub fn lz4_compress(data : Array[Int]) -> Array[Int] {
  let n = data.length()
  let out : Array[Int] = []
  if n == 0 {
    return out
  }
  // 短输入直接纯 literal（规范最短匹配收益门槛）。
  if n < 13 {
    lz4_emit(out, data, 0, n, 0, -1)
    return out
  }
  let table : Array[Int] = Array::make(4096, -1)
  let mflimit = n - 12 // match 起点上限（参考实现 MFLIMIT）
  let mut anchor = 0
  let mut i = 0
  while i < mflimit {
    let h = lz4_hash(data, i)
    let cand = table[h]
    table[h] = i
    if cand >= 0 &&
      i - cand <= 65535 &&
      data[cand] == data[i] &&
      data[cand + 1] == data[i + 1] &&
      data[cand + 2] == data[i + 2] &&
      data[cand + 3] == data[i + 3] {
      // 扩展匹配（不越过 n-5 的 end-of-block 约束）。
      let limit = n - 5
      let mut match_len = 4
      while i + match_len < limit &&
            data[cand + match_len] == data[i + match_len] {
        match_len = match_len + 1
      }
      lz4_emit(out, data, anchor, i - anchor, i - cand, match_len)
      i = i + match_len
      anchor = i
    } else {
      i = i + 1
    }
  }
  // 末尾纯 literal 序列。
  lz4_emit(out, data, anchor, n - anchor, 0, -1)
  out
}
