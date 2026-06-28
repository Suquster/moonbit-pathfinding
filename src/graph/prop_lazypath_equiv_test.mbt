// Feature: championship-v1-upgrade, Property 22: 惰性迭代器与物化路径等价
//
// 本文件以属性测试（property-based test）校验 `LazyPath` 的核心不变量
// （design.md §「方向 4 · 4.3 Lazy_Path_Iterator」/ Requirement 14.1 / 14.2 /
// 14.4）：惰性迭代器逐个产出的节点序列，与调用方一次性物化的完整路径
// **等长且逐元素相等**。
//
//   * Requirement 14.1：`next()` 逐个产出下一个节点，或在耗尽时返回 `None`。
//   * Requirement 14.2：仍有未产出节点时，`next()` 产出底层路径的下一个节点
//     并前移游标——因此「依次推进」所得序列恰为底层路径的顺序遍历。
//   * Requirement 14.4：完整消费 `LazyPath::from_path` 产出的序列，与一次性
//     物化的完整路径逐元素相等且等长。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。迭代次数取 256（远超 ≥100 基线）。

///|
/// 生成一段随机 Int 数组：长度在 `0..=8` 间均匀取样（含空数组以覆盖无解/空
/// 路径边界），元素为 `-100..=100` 的随机整数。
///
/// 既覆盖空数组（长度 0），也覆盖多种非空长度，从而充分检验惰性迭代与物化
/// 路径在各种规模下的等价性。
fn p22_gen_path() -> @infra_pbt.Gen[Array[Int]] {
  @infra_pbt.Gen::new(fn(rng) {
    let len = rng.next_below(9) // 长度 0..8（含空数组）
    let arr = []
    let mut i = 0
    while i < len {
      arr.push(rng.next_range(-100, 100)) // 元素 -100..100
      i = i + 1
    }
    arr
  })
}

///|
/// 反复调用 `next()` 直到返回 `None`，把惰性迭代器产出的节点收集为数组。
///
/// 收集结果即为「完整消费」惰性序列所得的物化序列，用于与底层原始路径比对。
fn p22_drain(it : LazyPath[Int]) -> Array[Int] {
  let out = []
  for ;; {
    match it.next() {
      Some(node) => out.push(node)
      None => break
    }
  }
  out
}

///|
/// Feature: championship-v1-upgrade, Property 22: 惰性迭代器与物化路径等价
///
/// 对任意随机 Int 路径：完整消费 `LazyPath::from_path(path)` 产出的节点序列，
/// 与一次性物化的完整路径 `path` **等长且逐元素相等**；且依次推进时每次
/// `next()` 恰产出底层路径的下一个节点（由顺序收集后逐元素比对保证）。
///
/// 同时以确定性断言固定一个空路径锚点（首次 `next()` 即 `None`，收集为空）。
///
/// **Validates: Requirements 14.1, 14.2, 14.4**
test "Feature: championship-v1-upgrade, Property 22: lazy iterator equivalent to materialized path" {
  // 锚点：空路径的惰性迭代器首次 next() 即返回 None，收集结果为空数组。
  let empty_drained = p22_drain(LazyPath::from_path([]))
  @test.assert_eq(empty_drained.length(), 0)
  // 锚点：empty() 构造的迭代器同样首次即终止。
  @test.assert_eq(p22_drain(LazyPath::empty()).length(), 0)

  // 属性：随机路径上，惰性消费序列与物化路径等长且逐元素相等。迭代 256 次。
  let ok = @infra_pbt.holds_for_all(
    p22_gen_path(),
    fn(path) {
      let it = LazyPath::from_path(path)
      let drained = p22_drain(it)
      // 不变量 1：等长（Requirement 14.4）。
      if drained.length() != path.length() {
        return false
      }
      // 不变量 2：逐元素相等（Requirement 14.2 / 14.4）——「依次推进时每次
      // next() 产出底层路径的下一个节点」等价于顺序收集后逐位相等。
      let mut i = 0
      while i < path.length() {
        if drained[i] != path[i] {
          return false
        }
        i = i + 1
      }
      true
    },
    iters=256,
  )
  assert_true(ok)
}
