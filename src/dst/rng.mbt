// rng.mbt —— DST_Framework 的种子驱动确定性伪随机源（pseudo-random source）。
//
// 设计依据（design.md §「方向八：DST_Framework」核心类型）：
//
//   pub struct Rng { seed : UInt64; state : UInt64 }
//   pub fn rng_new(seed : UInt64) -> Rng
//   pub fn next(self : Rng) -> UInt64
//
// 关键性质：「同种子 → 同序列」是确定性可重放（deterministic replay）的基石
// （design.md「同种子 → 同执行」为核心价值）。算法采用 xorshift64：状态更新
// 仅由逻辑左移 / 右移与按位异或构成，不含可能因后端整数语义差异而分歧的
// 加法或乘法，从而保证 wasm-gc / native / js 三后端逐位一致。
//
// 与 `@infra_pbt.Rng` 的关系见 moon.pkg 顶部说明：二者共享同一确定性随机源
// 理念（xorshift64），此处为避免运行时耦合而在 dst 内独立定义等价类型。

///|
/// xorshift64 的零不动点回退常数（state 为 0 时序列恒为 0，需回退到非零值）。
///
/// 取自 SplitMix64 的黄金比例常数 `0x9E3779B97F4A7C15`，仅在种子为 0 时启用，
/// 以保证随机序列具备完整周期。
let nonzero_fallback : UInt64 = 0x9E3779B97F4A7C15

///|
/// 种子驱动的确定性伪随机源。
///
///   * `seed`  —— 构造时的原始种子，用于失败重放时回溯到同一序列起点；
///   * `state` —— 推进中的内部状态（就地更新）。
///
/// 对同一初始种子，`next` 的连续调用产生确定性、三后端逐位一致的序列。
pub struct Rng {
  seed : UInt64
  mut state : UInt64
} derive(Eq, Show)

///|
/// 以给定种子构造一个 `Rng`。
///
/// xorshift64 存在零不动点，故当种子为 0 时回退到非零常数 `nonzero_fallback`，
/// 保证序列具备完整周期。`seed` 字段保留原始入参以便重放回溯。
pub fn rng_new(seed : UInt64) -> Rng {
  let state = if seed == 0 { nonzero_fallback } else { seed }
  { seed, state }
}

///|
/// 推进随机源状态并返回下一个 64 位随机字（xorshift64）。
///
/// 就地更新 `state`；对同一初始种子，连续调用产生确定性序列。
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
///
/// 供确定性调度器（任务 13.2）从待运行任务集中选择下一任务使用。
pub fn Rng::next_below(self : Rng, n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    let r = self.next()
    (r % n.to_uint64()).to_int()
  }
}
