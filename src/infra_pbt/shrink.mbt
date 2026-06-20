// shrink.mbt —— 反例收缩（shrink）机制（task 2.2）。
//
// 设计依据（design.md §「PBT 框架增强设计」，Requirement 11.1 / 11.2，
// Property 11「收缩产物仍使被测属性失败」）：
//
//   pub struct Shrinkable[T] { value : T; shrinks : () -> Array[T] }
//   pub fn shrink_int(Int) -> Array[Int]
//   pub fn[T] shrink_array(Array[T], (T) -> Array[T]) -> Array[Array[T]]
//   pub fn[T] check_with_shrink(
//     Gen[T], (T) -> Bool, (T) -> Array[T], iters? : Int) -> CheckResult[T]
//   pub struct CheckResult[T] { passed : Bool; counterexample : T? }
//
// 设计哲学：
//   * 复用既有 `Gen[T]` / `Rng` / `rng_new` / `default_seed` / `default_iters`
//     （pbt.mbt），不修改任何既有签名（freeze + bypass）。
//   * 收缩朝「更小 / 更简单」方向单调推进：`shrink_int` 朝 0 收缩、
//     `shrink_array` 通过删元素与递归收缩元素缩小结构，保证贪心收缩循环
//     必然终止（候选严格比当前更小）。
//   * 关键不变量（Property 11 / AC2）：贪心收缩在每一步只接受「仍使属性
//     失败」的候选，故最终返回的最小反例仍使属性失败。
//   * 全函数实现：不使用 `abort()` / `todo!()` / `panic` 占位；不在循环内
//     做字符串 `+`；以命名常量规避 magic number。

///|
/// 整数收缩时的「减半因子」。
///
/// `shrink_int` 以 `value - value / SHRINK_HALVING_DIVISOR^k` 形式构造由 0
/// 逐步逼近原值的候选序列；将除数命名为常量以规避 magic number。
let shrink_halving_divisor : Int = 2

///|
/// 可收缩值（shrinkable value）：携带一个值及其惰性候选收缩集。
///
/// `value` 为当前值；`shrinks` 为一个惰性函数，调用后返回比 `value`「更小 /
/// 更简单」的候选数组（不含 `value` 自身）。该结构便于将「值 + 收缩策略」
/// 作为一等公民在生成器之间传递与组合。
pub struct Shrinkable[T] {
  value : T
  shrinks : () -> Array[T]
}

///|
/// 构造一个 `Shrinkable[T]`。
pub fn[T] Shrinkable::new(value : T, shrinks : () -> Array[T]) -> Shrinkable[T] {
  { value, shrinks }
}

///|
/// 求取候选收缩集（对惰性 `shrinks` 求值）。
pub fn[T] Shrinkable::candidates(self : Shrinkable[T]) -> Array[T] {
  (self.shrinks)()
}

///|
/// 属性检查结果（check result）。
///
/// `passed` 为真表示在全部迭代中属性恒成立、无反例；为假时
/// `counterexample` 携带经收缩后的最小失败反例。
pub struct CheckResult[T] {
  passed : Bool
  counterexample : T?
}

///|
/// 内部工具：判断整型数组是否已包含某元素（用于候选去重）。
fn contains_int(xs : Array[Int], target : Int) -> Bool {
  for x in xs {
    if x == target {
      return true
    }
  }
  false
}

///|
/// 整数收缩：朝 0 方向产出更接近 0 的候选，不含原值本身，且已去重。
///
/// 候选构造（参考 QuickCheck 的整数收缩序列）：
///   * 首项恒为 `0`——绝对值最小的终极目标，给出最大跳跃，利于贪心收缩
///     快速逼近；
///   * 其后为 `value - value/2`、`value - value/4`、…（除数按
///     `shrink_halving_divisor` 逐次倍增），这些候选始终比 `value` 更接近
///     0，且绝对值递增地排列在 0 与 `value` 之间；序列末项自然包含「朝 0
///     退一步」的 `value-1`（正）/ `value+1`（负）。
///
/// 对 `value == 0` 返回空数组（已是最小，无可收缩）。所有候选均严格比
/// `value` 更接近 0，故不含原值；重复候选经 `contains_int` 去重。
pub fn shrink_int(value : Int) -> Array[Int] {
  let candidates : Array[Int] = []
  if value == 0 {
    return candidates
  }
  // 0 是终极收缩目标（绝对值最小），置于首位以获得最大收缩跳跃。
  candidates.push(0)
  // 以 value - (value / 2^k) 由 0 逐步逼近 value，产出更接近 0 的候选。
  let mut step = value / shrink_halving_divisor
  while step != 0 {
    let candidate = value - step
    // candidate 始终比 value 更接近 0，故不会等于 value；仅需去重。
    if !contains_int(candidates, candidate) {
      candidates.push(candidate)
    }
    step = step / shrink_halving_divisor
  }
  candidates
}

///|
/// 数组收缩：通过两类策略产出更小的候选数组。
///
///   * 策略一「删除单个元素」：依次删去第 `i` 个元素，得到长度 `n-1` 的
///     候选（结构更小，置于前部以优先尝试大幅收缩）。
///   * 策略二「递归收缩单个元素」：对第 `k` 个元素调用 `shrink_elem` 得到
///     其更小候选，逐一替换该位置，长度保持 `n`（在不缩短长度时简化元素）。
///
/// 两类策略都使候选「不大于」原数组，从而保证贪心收缩单调推进、必然终止。
/// 空数组无可删除、无元素可收缩，返回空候选集。
pub fn[T] shrink_array(
  arr : Array[T],
  shrink_elem : (T) -> Array[T],
) -> Array[Array[T]] {
  let results : Array[Array[T]] = []
  let n = arr.length()
  // 策略一：删除单个元素（长度 n-1）。
  let mut i = 0
  while i < n {
    let reduced : Array[T] = []
    let mut j = 0
    while j < n {
      if j != i {
        reduced.push(arr[j])
      }
      j += 1
    }
    results.push(reduced)
    i += 1
  }
  // 策略二：对单个元素递归收缩并就地替换（长度不变）。
  let mut k = 0
  while k < n {
    for sv in shrink_elem(arr[k]) {
      let replaced : Array[T] = []
      let mut j = 0
      while j < n {
        if j == k {
          replaced.push(sv)
        } else {
          replaced.push(arr[j])
        }
        j += 1
      }
      results.push(replaced)
    }
    k += 1
  }
  results
}

///|
/// 内部工具：从一个已知失败的反例出发，贪心收缩到「仍使属性失败」的最小反例。
///
/// 循环不变量（Property 11 / AC2）：`current` 在每轮迭代开始时都使
/// `pred(current) == false`。每轮在候选集中取**第一个**仍使属性失败的候选
/// 作为新的 `current`，若本轮无任何失败候选则停止。由于候选严格比 `current`
/// 更小（`shrink_int` 朝 0、`shrink_array` 缩小结构），循环必然终止；终止时
/// 返回的 `current` 即为该收缩策略可达的最小失败反例。
fn[T] greedy_shrink(
  start : T,
  pred : (T) -> Bool,
  shrink : (T) -> Array[T],
) -> T {
  let mut current = start
  let mut improved = true
  while improved {
    improved = false
    let candidates = shrink(current)
    let mut idx = 0
    while idx < candidates.length() {
      let candidate = candidates[idx]
      if !pred(candidate) {
        // 命中仍失败的更小候选：采纳并重新从它出发继续收缩。
        current = candidate
        improved = true
        break
      }
      idx += 1
    }
  }
  current
}

///|
/// 带收缩的属性检查：运行属性 `iters` 次，发现反例后收缩到最小失败反例。
///
/// 流程：
///   1. 以 `default_seed` 构造确定性随机源，迭代 `iters`（默认
///      `default_iters >= 100`）次采样并校验谓词 `pred`；
///   2. 一旦发现使 `pred` 为假的反例 `x`，调用 `greedy_shrink` 以 `shrink`
///      策略将其贪心收缩为「仍使属性失败」的最小反例并返回；
///   3. 若全部迭代均通过，返回 `passed = true`、无反例。
///
/// 关键不变量：返回的 `counterexample` 必满足 `pred(c) == false`
/// （Property 11、AC2）——收缩过程只接受仍失败的候选。
pub fn[T] check_with_shrink(
  g : Gen[T],
  pred : (T) -> Bool,
  shrink : (T) -> Array[T],
  iters? : Int = default_iters,
) -> CheckResult[T] {
  let rng = rng_new(default_seed)
  let mut i = 0
  while i < iters {
    let x = g.generate(rng)
    if !pred(x) {
      let minimal = greedy_shrink(x, pred, shrink)
      return { passed: false, counterexample: Some(minimal) }
    }
    i += 1
  }
  { passed: true, counterexample: None }
}
