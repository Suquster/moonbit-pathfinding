// metrics.mbt —— 指标派生（任务 11.1 / 11.3）。
//
// 设计依据：design.md §4.9「指标派生」（Requirement 8.*）。从事件流派生确定性
// 聚合度量：按级别计数与数值字段直方图。
//
//   * `count_by_level(events)` —— 返回长度 5 的非负计数定长数组（下标 =
//     `Level::rank`，Trace=0..Error=4）。用定长数组而非 `Map[Level,_]` 规避三
//     后端 Map 迭代顺序差异（Requirement 8.1 / 13.1）；
//   * `level_count(counts, level)` —— 取某级别计数；
//   * `histogram(events, field, boundaries)` —— 按升序边界把某数值字段二分入桶，
//     缺该字段或字段非数值的事件跳过不计（Requirement 8.2 / 8.3）。
//
// 两个派生均为纯函数，对同一输入两次派生逐桶相等（Requirement 8.5 / Property 14）。

///|
/// 级别数（`Level` 变体数）：定长计数数组长度。
let level_cardinality : Int = 5

///|
/// 按级别派生计数（Requirement 8.1）。
///
/// 返回长度 5 的非负计数数组，下标 = `Level::rank()`。各级别计数之和等于
/// 输入事件总数（计数守恒，Property 13）。
pub fn count_by_level(events : Array[Event]) -> Array[Int] {
  let counts = Array::make(level_cardinality, 0)
  for e in events {
    let r = e.level.rank()
    counts[r] = counts[r] + 1
  }
  counts
}

///|
/// 从计数数组取某级别计数（下标 = `Level::rank`）。
pub fn level_count(counts : Array[Int], level : Level) -> Int {
  counts[level.rank()]
}

///|
/// 直方图（Requirement 8.2）：升序边界 + 各桶计数。
///
/// 桶数 = `len(boundaries) + 1`（含上溢桶）。桶 `i` 计入满足
/// `boundaries[i-1] <= x < boundaries[i]` 的数值（桶 0 为 `x < boundaries[0]`，
/// 末桶为 `x >= boundaries[last]`）。
pub(all) struct Histogram {
  boundaries : Array[Double]
  buckets : Array[Int]
} derive(Eq, Debug)

///|
/// 对事件流就某数值字段按升序边界派生直方图（Requirement 8.2 / 8.3）。
///
/// 每条该字段为数值取值（`VInt` / `VFloat`）的事件计入其对应桶；缺该字段或
/// 字段非数值（`VStr` / `VBool` / `VMap` / `VList`）的事件被跳过，不计入任何桶。
pub fn histogram(
  events : Array[Event],
  field : String,
  boundaries : Array[Double],
) -> Histogram {
  let nbuckets = boundaries.length() + 1
  let buckets = Array::make(nbuckets, 0)
  for e in events {
    match e.fields.get(field) {
      Some(VInt(i)) => {
        let idx = bucket_index(boundaries, i.to_double())
        buckets[idx] = buckets[idx] + 1
      }
      Some(VFloat(f)) => {
        let idx = bucket_index(boundaries, f)
        buckets[idx] = buckets[idx] + 1
      }
      _ => () // 缺字段或非数值取值：跳过不计（Requirement 8.3）。
    }
  }
  { boundaries, buckets }
}

///|
/// 在升序 `boundaries` 上二分求桶下标 = 满足 `boundaries[i] <= x` 的边界数。
///
/// 返回值落在 `[0, len(boundaries)]`，即桶下标（末值为上溢桶）。纯整型 /
/// 浮点比较，三后端一致。
fn bucket_index(boundaries : Array[Double], x : Double) -> Int {
  let mut lo = 0
  let mut hi = boundaries.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if boundaries[mid] <= x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}
