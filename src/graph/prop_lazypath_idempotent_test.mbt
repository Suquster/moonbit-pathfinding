// Feature: championship-v1-upgrade, Property 23: 惰性迭代器耗尽后幂等
//
// 本文件以属性测试（property-based test）校验惰性路径迭代器 `@graph.LazyPath`
// 的「幂等终止」不变量（design.md §「方向 4 · Lazy_Path_Iterator」/
// Requirement 14.3 / 14.7）：
//
//   * Requirement 14.3：已无未产出节点时，`next()` 返回不含节点的终止值 `None`。
//   * Requirement 14.7：耗尽后重复调用 `next()` 恒返回 `None` 且不再推进游标、
//     不再产出任何节点（幂等终止）。
//
// 属性内容：对任意路径（含空路径 / 无解），将迭代器完整耗尽（持续 `next()`
// 直到首次返回 `None`）后，再连续调用 `next()` 若干次（5~20 次），断言全部
// 返回 `None`，不再产出任何节点。对 `empty()` 构造的迭代器单独断言其首次及
// 后续 `next()` 均为 `None`。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。迭代次数取 256（远超 ≥100 基线）。

///|
/// 生成一段长度 0..16 的随机 `Int` 数组（含空数组），作为底层路径节点序列。
///
/// 元素取自 [-1000, 1000] 区间，覆盖正负与零；长度从 0 起，确保「空路径 /
/// 无解」这一关键边界也在取样空间内。
fn p23_gen_path(rng : @infra_pbt.Rng) -> Array[Int] {
  let len = rng.next_below(17) // 路径长度 0..16（含空数组）
  let path = []
  let mut i = 0
  while i < len {
    path.push(rng.next_range(-1000, 1000))
    i = i + 1
  }
  path
}

///|
/// 将迭代器完整耗尽：持续调用 `next()` 直到首次返回 `None`，返回已产出节点数。
///
/// 为防御潜在的「不终止」缺陷（若 `next()` 永不返回 `None`），以路径长度加一
/// 个宽裕余量作为硬上限；正确实现下绝不会触及该上限。
fn p23_drain(it : LazyPath[Int], cap : Int) -> Int {
  let mut produced = 0
  let mut steps = 0
  while steps <= cap {
    match it.next() {
      Some(_) => produced = produced + 1
      None => return produced
    }
    steps = steps + 1
  }
  produced
}

///|
/// Feature: championship-v1-upgrade, Property 23: 惰性迭代器耗尽后幂等
///
/// 对任意随机路径（含空路径）：
///   * 完整耗尽后再连续调用 `next()`（5~20 次）恒返回 `None`；
///   * 由 `empty()` 构造的迭代器，其首次及后续多次 `next()` 均为 `None`。
///
/// 同时以确定性断言固定校验 `empty()` 与单元素路径两个锚点，作为属性基准。
///
/// **Validates: Requirements 14.3, 14.7**
test "Feature: championship-v1-upgrade, Property 23: lazy path iterator idempotent after exhaustion" {
  // 锚点 1：empty() 构造的迭代器，首次及后续多次 next() 均为 None。
  let empty_it : LazyPath[Int] = LazyPath::empty()
  let mut e = 0
  while e < 10 {
    assert_true(empty_it.next() is None)
    e = e + 1
  }
  // 锚点 2：单元素路径耗尽后再次 next() 仍为 None（不再产出节点）。
  let single = LazyPath::from_path([42])
  assert_true(single.next() is Some(42))
  let mut s = 0
  while s < 8 {
    assert_true(single.next() is None)
    s = s + 1
  }
  // 属性：随机路径耗尽后连续多次 next() 恒为 None。迭代 256 次（≥100 基线）。
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.Gen::new(p23_gen_path),
    fn(path) {
      let it = LazyPath::from_path(path)
      // 先完整耗尽：产出的节点数必须等于路径长度（Requirement 14.3 终止界限）。
      let produced = p23_drain(it, path.length() + 1)
      if produced != path.length() {
        return false
      }
      // 再连续调用 next() 5~20 次，全部必须为 None（Requirement 14.7 幂等终止）。
      let repeat = 5 + path.length() % 16 // 重复次数落在 5..20
      let mut k = 0
      while k < repeat {
        match it.next() {
          None => ()
          Some(_) => return false // 耗尽后又产出节点：违反幂等终止
        }
        k = k + 1
      }
      true
    },
    iters=256,
  )
  assert_true(ok)
}
