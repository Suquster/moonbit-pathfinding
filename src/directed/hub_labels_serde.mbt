// hub_labels_serde.mbt —— CompressedHubLabels 的序列化持久化。
//
// 需求：HL 标签构建昂贵（依赖完整 CH 预处理），生产部署应支持
// 「离线构建 → 字节流落盘/传输 → 在线加载直查」。本文件提供无损、
// 自校验的字节流编解码：
//
//   格式（所有整数 LEB128 varint，字节值 0..255）：
//     magic "HLC1" (4B) | n | 前向偏移增量×n | 前向字节流长 + 原始字节
//     | 后向偏移增量×n | 后向字节流长 + 原始字节 | FNV-1a 32 位校验 (4B LE)
//
//   偏移数组单调递增且 off[0]=0，故只需存 n 个增量；标签字节流本身
//   已是 LEB128 差分编码，直接原样嵌入。解码端校验 magic、校验和、
//   偏移单调性、末偏移与流长一致、游标精确落点，任一不符返回 None
//   （拒绝而非崩溃）。

///|
/// 序列化格式 magic 头："HLC1" 的四个字节值。
let hlc_magic : Array[Int] = [72, 76, 67, 49]

///|
/// FNV-1a 32 位校验（对 `bytes[0..<len]`），用于持久化字节流完整性自检。
fn hlc_fnv1a(bytes : Array[Int], len : Int) -> Int64 {
  let mut h = 2166136261L
  for i in 0..<len {
    h = (h ^ bytes[i].to_int64()) & 0xFFFFFFFFL
    h = (h * 16777619L) & 0xFFFFFFFFL
  }
  h
}

///|
/// 有界安全 varint 读取：越界或超出 63 位返回 `None`，否则返回 (值, 新游标)。
fn hlc_get_varint_checked(bytes : Array[Int], pos : Int) -> (Int64, Int)? {
  let mut v = 0L
  let mut shift = 0
  let mut p = pos
  while true {
    if p >= bytes.length() || shift > 56 {
      return None
    }
    let b = bytes[p]
    p = p + 1
    v = v | ((b & 0x7F).to_int64() << shift)
    if b < 0x80 {
      break
    }
    shift = shift + 7
  }
  Some((v, p))
}

///|
/// 将单调偏移数组编码为增量 varint 序列（off[0]=0 隐含，不编码）。
fn hlc_encode_offsets(out : Array[Int], off : Array[Int]) -> Unit {
  for v in 1..<off.length() {
    hlc_put_varint(out, (off[v] - off[v - 1]).to_int64())
  }
}

///|
/// 序列化为自校验字节流（值域 0..255），可无损还原并保持查询语义。
pub fn CompressedHubLabels::to_bytes(self : CompressedHubLabels) -> Array[Int] {
  let out : Array[Int] = []
  for b in hlc_magic {
    out.push(b)
  }
  hlc_put_varint(out, self.n.to_int64())
  hlc_encode_offsets(out, self.f_off)
  hlc_put_varint(out, self.f_bytes.length().to_int64())
  for b in self.f_bytes {
    out.push(b)
  }
  hlc_encode_offsets(out, self.b_off)
  hlc_put_varint(out, self.b_bytes.length().to_int64())
  for b in self.b_bytes {
    out.push(b)
  }
  let h = hlc_fnv1a(out, out.length())
  out.push((h & 0xFFL).to_int())
  out.push(((h >> 8) & 0xFFL).to_int())
  out.push(((h >> 16) & 0xFFL).to_int())
  out.push(((h >> 24) & 0xFFL).to_int())
  out
}

///|
/// 从游标 `pos` 解出一侧（偏移数组 + 标签字节流）；结构非法返回 `None`。
fn hlc_decode_side(
  bytes : Array[Int],
  pos : Int,
  n : Int,
) -> (Array[Int], Array[Int], Int)? {
  let off : Array[Int] = Array::make(n + 1, 0)
  let mut p = pos
  for v in 1..<(n + 1) {
    guard hlc_get_varint_checked(bytes, p) is Some((d, np)) else { return None }
    if d < 0L {
      return None
    }
    off[v] = off[v - 1] + d.to_int()
    p = np
  }
  guard hlc_get_varint_checked(bytes, p) is Some((blen64, np)) else {
    return None
  }
  p = np
  let blen = blen64.to_int()
  if blen < 0 || off[n] != blen || p + blen > bytes.length() {
    return None
  }
  let body : Array[Int] = Array::make(blen, 0)
  for i in 0..<blen {
    let b = bytes[p + i]
    if b < 0 || b > 255 {
      return None
    }
    body[i] = b
  }
  Some((off, body, p + blen))
}

///|
/// 从字节流还原压缩标签。校验 magic、FNV-1a 校验和、偏移单调性、
/// 流长一致与游标精确落点；任一不符（截断/翻位/伪造）返回 `None`。
pub fn CompressedHubLabels::from_bytes(
  bytes : Array[Int],
) -> CompressedHubLabels? {
  if bytes.length() < 9 {
    return None
  }
  for i in 0..<4 {
    if bytes[i] != hlc_magic[i] {
      return None
    }
  }
  let body_len = bytes.length() - 4
  let h = hlc_fnv1a(bytes, body_len)
  let stored = bytes[body_len].to_int64() |
    (bytes[body_len + 1].to_int64() << 8) |
    (bytes[body_len + 2].to_int64() << 16) |
    (bytes[body_len + 3].to_int64() << 24)
  if h != stored {
    return None
  }
  guard hlc_get_varint_checked(bytes, 4) is Some((n64, p0)) else { return None }
  let n = n64.to_int()
  if n < 0 {
    return None
  }
  guard hlc_decode_side(bytes, p0, n) is Some((f_off, f_bytes, p1)) else {
    return None
  }
  guard hlc_decode_side(bytes, p1, n) is Some((b_off, b_bytes, p2)) else {
    return None
  }
  if p2 != body_len {
    return None
  }
  Some({ n, f_off, f_bytes, b_off, b_bytes })
}
