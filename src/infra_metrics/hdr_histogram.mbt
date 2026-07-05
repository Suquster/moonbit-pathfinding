// hdr_histogram.mbt —— E5 批次 2：HdrHistogram 风格定精度直方图。
//
// paper-to-code：Gene Tene. *HdrHistogram: A High Dynamic Range Histogram.*
// （hdrhistogram.org；延迟测量事实标准，Cassandra/Elasticsearch 内核采用）。
// 值域按最高有效位分段（指数段），段内 2^p 个线性子桶——任意记录值的
// 桶代表值相对误差 ≤ 2^-p（p 为精度位数）；record/percentile 均无浮点
// 对数运算，纯位运算索引，固定内存。
//
// 对外 API：new(precision_bits) / record / count / value_at_percentile /
// max_value / merge_with。

///|
/// 定精度直方图（非负 Int64 值域，位运算索引）。
pub struct HdrHistogram {
  /// 段内线性子桶精度位数 p（相对误差 ≤ 2^-p）。
  precision_bits : Int
  /// 每段子桶数 = 2^p。
  sub_bucket_count : Int
  /// counts[segment * sub_bucket_count + sub]。
  counts : Array[Int]
  mut total : Int
  mut max_seen : Int64
}

///|
/// 最高有效位位置（0 值返回 0）。
fn hdr_msb(v : Int64) -> Int {
  let mut x = v.reinterpret_as_uint64()
  let mut r = 0
  while x > 1UL {
    x = x >> 1
    r = r + 1
  }
  r
}

///|
/// 精度位数 p ∈ [1, 12]（默认夹取）：相对误差 ≤ 2^-p。
pub fn HdrHistogram::new(precision_bits : Int) -> HdrHistogram {
  let p = if precision_bits < 1 {
    1
  } else if precision_bits > 12 {
    12
  } else {
    precision_bits
  }
  let sub = 1 << p
  // 63 个指数段覆盖整个非负 Int64 值域。
  {
    precision_bits: p,
    sub_bucket_count: sub,
    counts: Array::make(64 * sub, 0),
    total: 0,
    max_seen: 0L,
  }
}

///|
/// 值 → 桶下标（纯位运算，无浮点）。
fn HdrHistogram::index_of(self : HdrHistogram, v : Int64) -> Int {
  let p = self.precision_bits
  let msb = hdr_msb(v)
  if msb < p {
    // 低值段：直接线性索引（精确）。
    v.to_int()
  } else {
    let segment = msb - p + 1
    let sub = (v >> (segment - 1)).to_int() & (self.sub_bucket_count - 1)
    segment * self.sub_bucket_count + sub
  }
}

///|
/// 桶下标 → 代表值（桶内上界，保证 percentile 单调不低估计数覆盖）。
fn HdrHistogram::value_of(self : HdrHistogram, index : Int) -> Int64 {
  let p = self.precision_bits
  if index < self.sub_bucket_count {
    index.to_int64()
  } else {
    let segment = index / self.sub_bucket_count
    let sub = index % self.sub_bucket_count
    let base = 1L << (segment + p - 1)
    let width = 1L << (segment - 1)
    base + sub.to_int64() * width + width - 1L
  }
}

///|
/// 记录一个非负值（负值按 0 处理），O(1) 位运算。
pub fn HdrHistogram::record(self : HdrHistogram, v : Int64) -> Unit {
  let x = if v < 0L { 0L } else { v }
  let idx = self.index_of(x)
  self.counts[idx] = self.counts[idx] + 1
  self.total = self.total + 1
  if x > self.max_seen {
    self.max_seen = x
  }
}

///|
/// 样本总数。
pub fn HdrHistogram::count(self : HdrHistogram) -> Int {
  self.total
}

///|
/// 已见最大值（精确）。
pub fn HdrHistogram::max_value(self : HdrHistogram) -> Int64 {
  self.max_seen
}

///|
/// 分位查询 percentile ∈ [0,100]；空直方图返回 None。
/// 返回覆盖该分位 rank 的桶代表值，相对误差 ≤ 2^-p。
pub fn HdrHistogram::value_at_percentile(
  self : HdrHistogram,
  percentile : Double,
) -> Int64? {
  if self.total == 0 {
    return None
  }
  let pct = if percentile < 0.0 {
    0.0
  } else if percentile > 100.0 {
    100.0
  } else {
    percentile
  }
  let mut rank = (pct / 100.0 * self.total.to_double() + 0.5).to_int()
  if rank < 1 {
    rank = 1
  }
  if rank > self.total {
    rank = self.total
  }
  let mut cum = 0
  for i in 0..<self.counts.length() {
    cum = cum + self.counts[i]
    if cum >= rank {
      let v = self.value_of(i)
      return Some(if v > self.max_seen { self.max_seen } else { v })
    }
  }
  Some(self.max_seen)
}

///|
/// 合并另一直方图（要求同精度；桶计数逐位相加）。
pub fn HdrHistogram::merge_with(
  self : HdrHistogram,
  other : HdrHistogram,
) -> Unit {
  if other.precision_bits != self.precision_bits {
    // 精度不同：逐桶按代表值重记录（保守降级路径）。
    for i in 0..<other.counts.length() {
      let c = other.counts[i]
      if c > 0 {
        let v = other.value_of(i)
        for _ in 0..<c {
          self.record(v)
        }
      }
    }
    return
  }
  for i in 0..<other.counts.length() {
    self.counts[i] = self.counts[i] + other.counts[i]
  }
  self.total = self.total + other.total
  if other.max_seen > self.max_seen {
    self.max_seen = other.max_seen
  }
}
