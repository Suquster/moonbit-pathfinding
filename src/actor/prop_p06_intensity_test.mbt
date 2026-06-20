// prop_p06_intensity_test.mbt —— Property 6：重启强度上界（任务 3.5）。
//
//   Feature: actor, Property 6: 重启强度上界
//   ------------------------------------------------------------------
//   *对任意* 失败序列与重启强度配置 (max_restarts, window)，在任意 window 长度的
//   逻辑时钟窗口内，对单个 actor 触发的重启次数不超过 max_restarts；超过阈值的
//   失败被升级或停止。
//
// **Validates: Requirements 2.5, 2.6, 2.7**
//
// 建模方式：以 `within_intensity` 作为「是否仍可重启」的判定，模拟一串在不同
// 逻辑时钟到达的失败：仅当判定允许时记入一次重启时刻。断言任意 window 窗口内
// 实际重启次数 ≤ max_restarts。

///|
/// 给定重启时刻序列，统计落在窗口 (t-window, t] 内的最大重启次数。
fn p06_max_in_window(times : Array[Int], window : Int) -> Int {
  let mut max_count = 0
  for anchor in times {
    let mut count = 0
    for t in times {
      if t <= anchor && (window <= 0 || t > anchor - window) {
        count = count + 1
      }
    }
    if count > max_count {
      max_count = count
    }
  }
  max_count
}

///|
/// 单次场景：在随机逻辑时钟序列上施加 within_intensity 守门，记录实际重启时刻；
/// 断言任意 window 窗口内重启次数 ≤ max_restarts。
fn p06_intensity_bound(rng : @infra_pbt.Rng) -> Bool {
  let max_restarts = rng.next_range(1, 5)
  let window = rng.next_range(1, 10)
  let restart_times : Array[Int] = []
  // 模拟一串失败到达的逻辑时钟（单调不减）。
  let mut clock = 0
  let failures = rng.next_range(0, 40)
  for _i in 0..<failures {
    clock = clock + rng.next_range(0, 3)
    // 守门：仅当窗口内历史重启次数 < max_restarts 才记入一次重启。
    if within_intensity(restart_times, clock, window, max_restarts) {
      restart_times.push(clock)
    }
    // else：超限 —— 升级或停止，不记入重启（上界保证）。
  }
  // 断言：任意 window 窗口内重启次数 ≤ max_restarts。
  p06_max_in_window(restart_times, window) <= max_restarts
}

///|
/// Feature: actor, Property 6: 重启强度上界（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 2.5, 2.6, 2.7**
test "Feature: actor, Property 6: restarts within any window never exceed max_restarts (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p06_intensity_bound(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
