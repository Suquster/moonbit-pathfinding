// ddsketch.mbt —— E5 DDSketch 分位数 sketch（相对误差保证）。
//
// paper-to-code：Masson, Rim & Lee. *DDSketch: A Fast and Fully-Mergeable
// Quantile Sketch with Relative-Error Guarantees.* VLDB 2019。
//
// 对数桶映射：γ = (1+α)/(1-α)，正值 x 落入桶 i = ⌈log_γ(x)⌉，桶代表值取
// 几何中点 2γ^i/(γ+1)——任意分位查询的**相对误差 ≤ α**（论文定理 1）。
// 插入 O(1)、任意两 sketch 可合并（桶计数逐位相加）且合并保持误差界。
// 零值单独计数；本实现面向延迟/耗时等非负度量。
//
// 对外 API：new / count / add / quantile / merge_with。

///|
/// DDSketch：稀疏桶存储（有序桶索引 + 计数，二分定位）。
pub struct DDSketch {
  alpha : Double
  gamma : Double
  /// ln(γ)，桶映射 i = ⌈ln(x)/ln(γ)⌉。
  ln_gamma : Double
  /// 有序的桶索引（可为负）。
  keys : Array[Int]
  counts : Array[Int]
  mut zero_count : Int
  mut total : Int
}

///|
/// 相对误差目标 α ∈ (0,1)（如 0.01 即 1% 相对误差）的空 sketch。
pub fn DDSketch::new(alpha : Double) -> DDSketch {
  let a = if alpha <= 0.0 || alpha >= 1.0 { 0.01 } else { alpha }
  let gamma = (1.0 + a) / (1.0 - a)
  {
    alpha: a,
    gamma,
    ln_gamma: @math.ln(gamma),
    keys: [],
    counts: [],
    zero_count: 0,
    total: 0,
  }
}

///|
/// 误差参数 α。
pub fn DDSketch::error_bound(self : DDSketch) -> Double {
  self.alpha
}

///|
/// 样本总数。
pub fn DDSketch::count(self : DDSketch) -> Int {
  self.total
}

///|
/// keys 中第一个 ≥ key 的下标（二分下界）。
fn DDSketch::lower_bound(self : DDSketch, key : Int) -> Int {
  let mut lo = 0
  let mut hi = self.keys.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if self.keys[mid] < key {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// 向桶 key 加 n 个计数。
fn DDSketch::bump(self : DDSketch, key : Int, n : Int) -> Unit {
  let pos = self.lower_bound(key)
  if pos < self.keys.length() && self.keys[pos] == key {
    self.counts[pos] = self.counts[pos] + n
  } else {
    self.keys.insert(pos, key)
    self.counts.insert(pos, n)
  }
}

///|
/// 记录一个非负样本（负值按 0 处理）。
pub fn DDSketch::add(self : DDSketch, x : Double) -> Unit {
  self.total = self.total + 1
  if x <= 0.0 {
    self.zero_count = self.zero_count + 1
    return
  }
  let key = @math.ceil(@math.ln(x) / self.ln_gamma).to_int()
  self.bump(key, 1)
}

///|
/// 分位查询 q ∈ [0,1]；空 sketch 返回 None。返回值与真实分位的相对误差 ≤ α。
pub fn DDSketch::quantile(self : DDSketch, q : Double) -> Double? {
  if self.total == 0 {
    return None
  }
  let qq = if q < 0.0 { 0.0 } else if q > 1.0 { 1.0 } else { q }
  // rank ∈ [1, total]。
  let rank_f = qq * (self.total - 1).to_double() + 1.0
  let rank = @math.floor(rank_f).to_int()
  if rank <= self.zero_count {
    return Some(0.0)
  }
  let mut cum = self.zero_count
  for i in 0..<self.keys.length() {
    cum = cum + self.counts[i]
    if cum >= rank {
      // 桶 i 的代表值：几何中点 2γ^k/(γ+1)。
      let k = self.keys[i]
      let v = 2.0 *
        @math.exp(k.to_double() * self.ln_gamma) /
        (self.gamma + 1.0)
      return Some(v)
    }
  }
  // 数值兜底：返回最大桶代表值。
  let k = self.keys[self.keys.length() - 1]
  Some(2.0 * @math.exp(k.to_double() * self.ln_gamma) / (self.gamma + 1.0))
}

///|
/// 合并另一 sketch（要求同 α；桶计数逐位相加，合并保持误差界）。
pub fn DDSketch::merge_with(self : DDSketch, other : DDSketch) -> Unit {
  for i in 0..<other.keys.length() {
    self.bump(other.keys[i], other.counts[i])
  }
  self.zero_count = self.zero_count + other.zero_count
  self.total = self.total + other.total
}
