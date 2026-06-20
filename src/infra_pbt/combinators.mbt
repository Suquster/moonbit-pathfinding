// combinators.mbt —— PBT 生成器组合子（task 2.1）。
//
// 设计依据（design.md §「PBT 框架增强设计」，Requirement 11.3 / AC3）：
//
//   pub fn[T] one_of(Array[Gen[T]]) -> Gen[T]              // 等概率
//   pub fn[T] frequency(Array[(Int, Gen[T])]) -> Gen[T]    // 按权重
//   pub fn[T] sized((Int) -> Gen[T]) -> Gen[T]             // 按规模
//
// 设计哲学：
//   * 复用既有 `Gen[T]` / `Rng`（pbt.mbt），不修改其签名（freeze + bypass）。
//   * 索引选择一律经 `Rng::next_below`，其在参数 <= 0 时返回 0，从根本上
//     规避「取模除零」与负数索引（见 pbt.mbt 中 `next_below` 实现）。
//   * 组合子在「全部权重非正」等退化输入下有确定的安全回退行为，不使用
//     `abort()` / `todo!()` / `panic` 占位。
//   * `sized` 的规模取自 `Rng`，从而可由种子复现（reproducible）。
//
// 边界约定（空数组）：
//   `one_of` / `frequency` 接受的生成器数组在语义上必须非空——因为对完全
//   泛型的 `T`（无 `Default` 约束）而言，在「零个源生成器」时无法凭空构造
//   任何 `T` 值。这是组合子的**前置条件**（precondition），由本注释明确
//   声明边界（design 任务允许「要求非空 / 在文档中说明边界」）。在该前置
//   条件被满足（数组非空）时，下方实现对一切输入（包括全零/负权重）均为
//   全函数（total）且不会越界。

///|
/// `sized` 在未由调用方约束时为规模参数选取的默认上界（开区间右端）。
///
/// 规模从闭区间 `[0, default_max_size]` 中按 `Rng` 取值，使生成规模既有
/// 足够覆盖范围，又可由种子复现。命名常量以规避 magic number。
let default_max_size : Int = 100

///|
/// 等概率组合子：从给定生成器数组中等概率择一，并以同一 `Rng` 驱动其采样。
///
/// 选择索引经 `rng.next_below(n)` 得到 `[0, n)` 内的下标；当 `n > 0` 时该
/// 下标恒为合法下标，故采样不会越界。
///
/// 前置条件：`gens` 必须非空。空数组属契约违反（无法为泛型 `T` 构造值），
/// 详见文件头「边界约定」。
pub fn[T] one_of(gens : Array[Gen[T]]) -> Gen[T] {
  Gen::new(fn(rng) {
    // next_below 在 n<=0 时返回 0，从而规避除零；n>0 时下标必合法。
    let idx = rng.next_below(gens.length())
    gens[idx].generate(rng)
  })
}

///|
/// 按权重组合子：以整数权重对各生成器分配采样概率。
///
/// 语义：所有**正权重**之和构成区间总长 `total`，在 `[0, total)` 上均匀取
/// 一个落点 `point`，落点所处的权重区间对应被选中的生成器。
///
/// 退化输入的安全行为：
///   * 非正权重项（权重 `<= 0`）被跳过/忽略，既不计入 `total` 也不可能被
///     选中——从而避免负权重导致的区间错乱。
///   * 当所有项权重均非正（`total <= 0`）时，退化为在现存生成器上**等概率**
///     择一（数组非空时安全），而非除零或越界。
///
/// 前置条件：`weighted` 必须非空，理由同 `one_of`（详见文件头「边界约定」）。
pub fn[T] frequency(weighted : Array[(Int, Gen[T])]) -> Gen[T] {
  Gen::new(fn(rng) {
    // 第一遍：累计所有正权重，得到区间总长。
    let mut total = 0
    for pair in weighted {
      let weight = pair.0
      if weight > 0 {
        total += weight
      }
    }
    // 退化：无任何正权重时等概率回退到现存生成器（非空时安全）。
    if total <= 0 {
      let idx = rng.next_below(weighted.length())
      return weighted[idx].1.generate(rng)
    }
    // 在 [0, total) 上取落点，再按正权重区间定位被选中的生成器。
    let mut point = rng.next_below(total)
    for pair in weighted {
      let weight = pair.0
      if weight > 0 {
        if point < weight {
          return pair.1.generate(rng)
        }
        point -= weight
      }
    }
    // 理论不可达：point < total 必落入某个正权重区间。此处兜底取首个正
    // 权重项以保持全函数性（不使用 abort/panic 占位）。
    for pair in weighted {
      if pair.0 > 0 {
        return pair.1.generate(rng)
      }
    }
    // 同样不可达（total>0 蕴含至少一个正权重项）；退回首项保持总函数性。
    weighted[0].1.generate(rng)
  })
}

///|
/// 按规模组合子：先由 `Rng` 派生一个有界规模 `size`，再以该规模实例化生成器。
///
/// 规模取自闭区间 `[0, default_max_size]`（`rng.next_range`），故 `size`
/// 完全由种子决定、可复现；随后调用 `make(size)` 得到该规模下的生成器并以
/// 同一 `rng` 采样。该组合子对任意 `make` 均为全函数，无退化边界。
pub fn[T] sized(make : (Int) -> Gen[T]) -> Gen[T] {
  Gen::new(fn(rng) {
    let size = rng.next_range(0, default_max_size)
    make(size).generate(rng)
  })
}
