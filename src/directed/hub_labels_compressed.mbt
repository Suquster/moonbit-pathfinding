// hub_labels_compressed.mbt —— Hub Labeling 标签内存压缩（前沿项：
// HL label memory compression）。
//
// 思路：标签按 hub 升序存放，hub 列单调递增 → 相邻差分小整数；
// dist 在路网权域下也偏小。将每条标签编码为
//   varint(hub_delta) + varint(dist)
// 的 LEB128 字节流（每节点一段，CSR 偏移定位），把 64 位打包条目
// （8 字节/条）压到通常 2–4 字节/条。查询沿两条字节流做流式归并
// （解码即弃，零物化），语义与 `HubLabels::query` 完全一致。

///|
/// 压缩后的 Hub Labeling（LEB128 差分字节流 + CSR 偏移）。
pub struct CompressedHubLabels {
  n : Int
  /// 前向标签字节流偏移：f_off[v]..f_off[v+1]。
  f_off : Array[Int]
  f_bytes : Array[Int]
  /// 后向标签字节流偏移：b_off[v]..b_off[v+1]。
  b_off : Array[Int]
  b_bytes : Array[Int]
}

///|
/// LEB128 追加（值须非负）。
fn hlc_put_varint(out : Array[Int], value : Int64) -> Unit {
  let mut v = value
  while v >= 0x80L {
    out.push(((v & 0x7FL) | 0x80L).to_int())
    v = v >> 7
  }
  out.push(v.to_int())
}

///|
/// LEB128 读取：返回 (值, 新游标)。
fn hlc_get_varint(bytes : Array[Int], pos : Int) -> (Int64, Int) {
  let mut v = 0L
  let mut shift = 0
  let mut p = pos
  while true {
    let b = bytes[p]
    p = p + 1
    v = v | ((b & 0x7F).to_int64() << shift)
    if b < 0x80 {
      break
    }
    shift = shift + 7
  }
  (v, p)
}

///|
/// 把一段打包标签（(hub<<42)|dist，hub 升序）编入字节流。
fn hlc_encode_side(
  packed : Array[Int64],
  lo : Array[Int],
  n : Int,
) -> (Array[Int], Array[Int]) {
  let dmask = (1L << HL_HUB_SHIFT) - 1L
  let off : Array[Int] = Array::make(n + 1, 0)
  let bytes : Array[Int] = []
  for v in 0..<n {
    let mut prev_hub = 0L
    for i in lo[v]..<lo[v + 1] {
      let hub = packed[i] >> HL_HUB_SHIFT
      hlc_put_varint(bytes, hub - prev_hub)
      hlc_put_varint(bytes, packed[i] & dmask)
      prev_hub = hub
    }
    off[v + 1] = bytes.length()
  }
  (off, bytes)
}

///|
/// 由未压缩 Hub Labeling 生成压缩标签（无损；查询语义不变）。
pub fn HubLabels::compress(self : HubLabels) -> CompressedHubLabels {
  let (f_off, f_bytes) = hlc_encode_side(self.fla, self.flo, self.n)
  let (b_off, b_bytes) = hlc_encode_side(self.bla, self.blo, self.n)
  { n: self.n, f_off, f_bytes, b_off, b_bytes }
}

///|
/// 标签体字节数（压缩后，偏移数组另计；诊断/对比用）。
pub fn CompressedHubLabels::label_bytes(self : CompressedHubLabels) -> Int {
  self.f_bytes.length() + self.b_bytes.length()
}

///|
/// 点对点最短距离：沿两条差分字节流流式归并取最小和，
/// 与 `HubLabels::query` 结果逐点一致。不可达返回 None。
pub fn CompressedHubLabels::query(
  self : CompressedHubLabels,
  s : Int,
  t : Int,
) -> Int64? {
  guard s >= 0 && s < self.n && t >= 0 && t < self.n else { None }
  let mut i = self.f_off[s]
  let i_end = self.f_off[s + 1]
  let mut j = self.b_off[t]
  let j_end = self.b_off[t + 1]
  let mut best = INF_DIST
  let mut ha = 0L
  let mut da = 0L
  let mut hb = 0L
  let mut db = 0L
  let mut have_a = false
  let mut have_b = false
  while true {
    if !have_a {
      if i >= i_end {
        break
      }
      let (dh, p1) = hlc_get_varint(self.f_bytes, i)
      let (d, p2) = hlc_get_varint(self.f_bytes, p1)
      ha = ha + dh
      da = d
      i = p2
      have_a = true
    }
    if !have_b {
      if j >= j_end {
        break
      }
      let (dh, p1) = hlc_get_varint(self.b_bytes, j)
      let (d, p2) = hlc_get_varint(self.b_bytes, p1)
      hb = hb + dh
      db = d
      j = p2
      have_b = true
    }
    if ha < hb {
      have_a = false
    } else if ha > hb {
      have_b = false
    } else {
      let sum = da + db
      if sum < best {
        best = sum
      }
      have_a = false
      have_b = false
    }
  }
  if best >= INF_DIST {
    None
  } else {
    Some(best)
  }
}
