// prop_invariant_test.mbt —— Property 12：不变量违反必检出（任务 7.3）。
//
// Feature: dst, Property 12: 不变量违反必检出（必然违反某附加不变量的场景，run_des
// 以 Failed(reason) 终止且 reason 标识被违反不变量名称与发生逻辑时间戳）。
//
// **Validates: Requirements 7.1, 7.2, 7.3, 7.6**

///|
/// 生成器：附「故意违反」恒假不变量的小规模场景（≥1 任务，max_steps ≥ 1）。
fn p12_gen() -> @infra_pbt.Gen[(UInt64, DesScenario)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 4)
    let tasks : Array[Task] = []
    for i in 0..<n {
      tasks.push(Task::new(i, "t\{i}"))
    }
    let inv = Invariant::new("故意违反", fn(_w) { false })
    let ms = rng.next_range(1, n + 5)
    let sc = DesScenario::new(tasks, [], [inv], null_protocol(), ms)
    (rng.next(), sc)
  })
}

///|
/// **Validates: Requirements 7.1, 7.2, 7.3, 7.6**
test "Feature: dst, Property 12: invariant violation is always detected" {
  let ok = @infra_pbt.holds_for_all(p12_gen(), fn(pair) {
    let (seed, sc) = pair
    let r = run_des(seed, sc)
    match r.status {
      Failed(reason~) =>
        tcontains(reason, "故意违反") && tcontains(reason, "逻辑时间")
      Completed => false
    }
  })
  assert_true(ok)
}
