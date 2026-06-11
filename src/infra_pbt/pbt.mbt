// pbt.mbt —— 统一 PBT 生成器与往返/不变量断言模板。
//
// 设计依据（design.md §「组件与接口 → 共享基础设施组件 → infra_pbt」与
// §「数据模型 → 共享随机源模型」）：
//
//   pub struct Gen[T] { sample : (Rng) -> T }
//   pub fn[T : Eq] round_trip(g, encode, decode) -> Bool
//   pub fn[T] holds_for_all(g, pred, iters~ : Int = 100) -> Bool
//   pub struct Rng { seed : UInt64; state : UInt64 }  // 三后端逐位一致
//
// 设计哲学：
//   * `Rng` 采用 xorshift64，仅使用移位与异或（无加法/乘法），因此在
//     `wasm-gc` / `native` / `js` 三后端上对同一种子产生逐位一致的序列
//     （Requirement 11.1 三后端一致性的基石）。
//   * 模板内部使用确定性默认种子，使属性测试可重放（reproducible）。
//   * 断言模板默认迭代次数为 100（Requirement 11.3）。

///|
/// 属性测试模板的默认迭代次数。
///
/// 对应 Requirement 11.3 的质量门禁基线：每条属性测试最少 100 次迭代。
pub let default_iters : Int = 100

///|
/// 模板内部确定性采样所用的默认种子。
///
/// 取自 SplitMix64 的黄金比例常数 `0x9E3779B97F4A7C15`，仅用于在模板未
/// 显式提供种子时保证采样的可重放性（同一次构建多次运行结果一致）。
let default_seed : UInt64 = 0x9E3779B97F4A7C15

///|
/// 种子驱动的确定性伪随机源（pseudo-random source）。
///
/// 采用 xorshift64 算法：状态更新仅由逻辑左移 / 右移与按位异或构成，
/// 不含可能因后端整数语义差异而分歧的加法或乘法，从而保证
/// `wasm-gc` / `native` / `js` 三后端逐位一致（design.md「共享随机源模型」）。
///
/// 与 DST_Framework（方向八）共享同一确定性随机源理念：同种子 → 同序列。
pub struct Rng {
  seed : UInt64
  mut state : UInt64
}

///|
/// 以给定种子构造一个 `Rng`。
///
/// xorshift64 存在零不动点（state 为 0 时序列恒为 0），故当种子为 0 时
/// 回退到非零的默认常数，保证序列具备完整周期。
pub fn rng_new(seed : UInt64) -> Rng {
  let state = if seed == 0 { default_seed } else { seed }
  { seed, state }
}

///|
/// 推进随机源状态并返回下一个 64 位随机字（xorshift64）。
///
/// 该方法会就地更新 `state`；对同一初始种子，连续调用产生确定性序列。
pub fn Rng::next(self : Rng) -> UInt64 {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  self.state = x
  x
}

///|
/// 返回区间 `[0, n)` 内的非负整数；当 `n <= 0` 时返回 0。
pub fn Rng::next_below(self : Rng, n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    let r = self.next()
    (r % n.to_uint64()).to_int()
  }
}

///|
/// 返回闭区间 `[lo, hi]` 内的整数；当 `lo >= hi` 时返回 `lo`。
pub fn Rng::next_range(self : Rng, lo : Int, hi : Int) -> Int {
  if lo >= hi {
    lo
  } else {
    lo + self.next_below(hi - lo + 1)
  }
}

///|
/// 返回一个随机布尔值。
pub fn Rng::next_bool(self : Rng) -> Bool {
  (self.next() & 1) == 1
}

///|
/// 生成器：以确定性随机源 `Rng` 产生某类型 `T` 的随机实例。
///
/// 与 design.md 接口签名保持一致：`sample : (Rng) -> T`。各方向通过组合
/// 生成器构造领域类型的随机实例，再交由下方断言模板校验。
pub struct Gen[T] {
  sample : (Rng) -> T
}

///|
/// 从一个采样函数构造生成器。
pub fn[T] Gen::new(sample : (Rng) -> T) -> Gen[T] {
  { sample, }
}

///|
/// 使用给定随机源产生一个 `T` 实例。
pub fn[T] Gen::generate(self : Gen[T], rng : Rng) -> T {
  (self.sample)(rng)
}

///|
/// 内置生成器：闭区间 `[lo, hi]` 内的整数。
pub fn gen_int_range(lo : Int, hi : Int) -> Gen[Int] {
  Gen::new(fn(rng) { rng.next_range(lo, hi) })
}

///|
/// 内置生成器：布尔值。
pub fn gen_bool() -> Gen[Bool] {
  Gen::new(fn(rng) { rng.next_bool() })
}

///|
/// 往返断言模板（round-trip property template）。
///
/// 对生成器产出的每个实例 `x`，校验 `decode(encode(x))` 与 `x` 等价，
/// 即 `parse(print(x)) ≡ x` / `decode(encode(x)) ≡ x`。任一实例往返失败
/// （解码为 `None` 或解码结果不相等）即返回 `false`。
///
/// 迭代 `default_iters`（默认 100）次，满足 Requirement 11.3 基线。
pub fn[T : Eq] round_trip(
  g : Gen[T],
  encode : (T) -> Bytes,
  decode : (Bytes) -> T?,
) -> Bool {
  let rng = rng_new(default_seed)
  let mut i = 0
  while i < default_iters {
    let x = g.generate(rng)
    match decode(encode(x)) {
      Some(y) => if x != y { return false }
      None => return false
    }
    i += 1
  }
  true
}

///|
/// 不变量断言模板（invariant property template）。
///
/// 对生成器产出的每个实例校验布尔谓词 `pred`；任一实例使谓词为假即
/// 返回 `false`。默认迭代 100 次（Requirement 11.3）。
pub fn[T] holds_for_all(
  g : Gen[T],
  pred : (T) -> Bool,
  iters? : Int = 100,
) -> Bool {
  let rng = rng_new(default_seed)
  let mut i = 0
  while i < iters {
    if !pred(g.generate(rng)) {
      return false
    }
    i += 1
  }
  true
}
