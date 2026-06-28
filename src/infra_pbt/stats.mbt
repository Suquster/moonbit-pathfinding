// stats.mbt —— 样本分布统计收集（task 2.3）。
//
// 设计依据（design.md §「PBT 框架增强设计」，Requirement 11.5 / AC5，
// Property 11「统计计数与样本分类一致」）：
//
//   pub struct Stats { mut counts : Map[String, Int] }
//   pub fn[T] holds_for_all_stats(
//     Gen[T], (T) -> Bool, (T) -> String, iters? : Int) -> (Bool, Stats)
//
// 设计哲学：
//   * 复用既有 `Gen[T]` / `Rng` / `rng_new` / `default_seed` / `default_iters`
//     （pbt.mbt），不修改任何既有签名（freeze + bypass）。
//   * `holds_for_all_stats` 与既有 `holds_for_all` 迭代语义对齐：同样以
//     `rng_new(default_seed)` 构造确定性随机源、迭代相同次数，仅额外用
//     分类函数对每个样本归类并累加计数，从而可由种子复现（reproducible）。
//   * 与 `holds_for_all` 的差异：即便属性已被某样本证伪，本模板仍**遍历
//     完整的 `iters` 次**以收集完整分布（属性最终结果由「是否出现过失败」
//     聚合得到），使返回的统计能反映整个采样空间的分类占比。
//   * 全函数实现：不使用 `abort()` / `todo!()` / `panic` 占位；不在循环内
//     做字符串 `+`；以命名常量规避 magic number。

///|
/// 占比计算在样本总数为 0（尚未记录任何样本）时返回的安全比值。
///
/// 命名常量以规避 magic number：空统计的任意分类占比定义为 0.0。
let empty_ratio : Double = 0.0

///|
/// 单次记录对目标分类计数的增量步长。
///
/// 每观察到一个属于某分类的样本，其计数 `+1`；以命名常量表达该步长。
let count_increment : Int = 1

///|
/// 样本分布统计（statistics）：按字符串分类键累计样本出现次数。
///
/// `counts` 将「分类标签」映射到「该分类下已记录的样本数」。配合
/// `holds_for_all_stats` 使用，可观察生成器在各分类上的分布是否符合预期
/// （例如 `frequency` 各分支的实际占比是否趋近配置权重）。
///
/// 说明：`Map` 为引用语义容器，全部计数更新均经 `Map::set` 就地完成，
/// 从不重新绑定字段本身，故字段无需 `mut`（保持字段不可重绑定可避免
/// 误用，并满足本包 `unused_mut` 的严格检查）。
pub struct Stats {
  counts : Map[String, Int]
}

///|
/// 构造一个空统计（无任何分类记录）。
pub fn Stats::new() -> Stats {
  { counts: Map([]) }
}

///|
/// 记录一个属于分类 `category` 的样本：将该分类的计数 `+1`。
///
/// 首次出现的分类从 0 起算；已存在的分类在原计数上累加。
pub fn Stats::record(self : Stats, category : String) -> Unit {
  let previous = match self.counts.get(category) {
    Some(n) => n
    None => 0
  }
  self.counts.set(category, previous + count_increment)
}

///|
/// 返回分类 `category` 当前的计数；未出现过的分类返回 0。
pub fn Stats::count(self : Stats, category : String) -> Int {
  match self.counts.get(category) {
    Some(n) => n
    None => 0
  }
}

///|
/// 返回所有分类计数之和（已记录样本总数）。
///
/// 对各分类计数做线性求和；空统计返回 0。
pub fn Stats::total(self : Stats) -> Int {
  let mut sum = 0
  for _, value in self.counts {
    sum += value
  }
  sum
}

///|
/// 返回分类 `category` 占样本总数的比例（`count / total`）。
///
/// 当样本总数为 0 时返回 `empty_ratio`（0.0），从根本上规避除零；否则
/// 以浮点除法给出 `[0.0, 1.0]` 内的占比。
pub fn Stats::ratio(self : Stats, category : String) -> Double {
  let denominator = self.total()
  if denominator == 0 {
    empty_ratio
  } else {
    self.count(category).to_double() / denominator.to_double()
  }
}

///|
/// 带统计收集的不变量断言模板（invariant property template with statistics）。
///
/// 对生成器产出的每个样本：
///   1. 用分类函数 `classify` 归类并在 `Stats` 中 `record`（无论属性成败，
///      均完整记录，以反映整个采样空间的分布）；
///   2. 用谓词 `pred` 校验属性；任一样本使其为假，则整体属性判定为不成立。
///
/// 与既有 `holds_for_all` 迭代语义对齐：同样以 `rng_new(default_seed)`
/// 构造确定性随机源、迭代 `iters`（默认 `default_iters >= 100`）次，差异
/// 仅在于额外收集分类统计且不提前中断采样。
///
/// 返回 `(属性是否全程成立, 分布统计)`。
pub fn[T] holds_for_all_stats(
  g : Gen[T],
  pred : (T) -> Bool,
  classify : (T) -> String,
  iters? : Int = default_iters,
) -> (Bool, Stats) {
  let rng = rng_new(default_seed)
  let stats = Stats::new()
  let mut passed = true
  let mut i = 0
  while i < iters {
    let x = g.generate(rng)
    stats.record(classify(x))
    if !pred(x) {
      passed = false
    }
    i += 1
  }
  (passed, stats)
}

///|
/// 内联烟雾测试：`record` / `count` / `total` 基本计数语义。
test "stats record/count/total smoke" {
  let stats = Stats::new()
  stats.record("a")
  stats.record("a")
  stats.record("b")
  assert_eq(stats.count("a"), 2)
  assert_eq(stats.count("b"), 1)
  assert_eq(stats.count("missing"), 0)
  assert_eq(stats.total(), 3)
}

///|
/// 内联烟雾测试：`ratio` 在空统计返回 0.0、非空时给出正确占比。
test "stats ratio smoke" {
  let empty = Stats::new()
  assert_eq(empty.ratio("x"), 0.0)
  let stats = Stats::new()
  stats.record("x")
  stats.record("x")
  stats.record("y")
  stats.record("y")
  assert_eq(stats.ratio("x"), 0.5)
  assert_eq(stats.ratio("y"), 0.5)
}

///|
/// 内联烟雾测试：`holds_for_all_stats` 计数总和等于迭代次数，且属性结果正确。
test "holds_for_all_stats smoke" {
  let g = gen_int_range(0, 9)
  let (passed, stats) = holds_for_all_stats(
    g,
    fn(n) { n >= 0 },
    fn(n) { if n % 2 == 0 { "even" } else { "odd" } },
    iters=100,
  )
  assert_eq(passed, true)
  // 每次迭代恰好记录一个样本，故总数等于迭代次数。
  assert_eq(stats.total(), 100)
  assert_eq(stats.count("even") + stats.count("odd"), 100)
}
