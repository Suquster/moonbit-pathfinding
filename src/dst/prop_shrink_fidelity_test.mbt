// prop_shrink_fidelity_test.mbt —— Property 7：收缩保真（任务 10.3）。
//
// Feature: dst, Property 7: 收缩保真（对失败场景，shrink 返回 Minimal(s') 且
// run_des(seed, s') 仍以 Failed 终止）。
//
// **Validates: Requirements 4.1, 4.3, 4.6**

///|
/// 生成器：必然失败的场景（附恒假不变量 + ≥1 任务 + max_steps ≥ 1）。
fn p7_gen() -> @infra_pbt.Gen[(UInt64, DesScenario)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 4)
    let tasks : Array[Task] = []
    for i in 0..<n {
      tasks.push(Task::new(i, "t\{i}"))
    }
    let fc = rng.next_range(0, 3)
    let faults : Array[FaultPolicyEx] = []
    for _ in 0..<fc {
      faults.push(
        FaultPolicyEx::new(
          rng.next_range(0, n),
          rng.next_below(n),
          sample_netfault(rng, n),
        ),
      )
    }
    let ms = rng.next_range(1, n + 5)
    let inv = Invariant::new("强制失败", fn(_w) { false })
    let sc = DesScenario::new(tasks, faults, [inv], replication_protocol(n), ms)
    (rng.next(), sc)
  })
}

///|
/// **Validates: Requirements 4.1, 4.3, 4.6**
test "Feature: dst, Property 7: shrink fidelity (minimal still fails)" {
  let ok = @infra_pbt.holds_for_all(p7_gen(), fn(pair) {
    let (seed, sc) = pair
    // 健全性：输入确为失败场景。
    if !default_fails(run_des(seed, sc)) {
      return false
    }
    match shrink(seed, sc).scenario() {
      Some(s2) => default_fails(run_des(seed, s2))
      None => false
    }
  })
  assert_true(ok)
}
