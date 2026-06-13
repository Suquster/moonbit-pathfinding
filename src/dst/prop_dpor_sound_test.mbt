// prop_dpor_sound_test.mbt —— Property 10：DPOR 可靠性（任务 12.3）。
//
// Feature: dst, Property 10: DPOR 可靠性（explore_dpor 与 explore_bounded 报告相同的
// 「是否存在失败交错」结论，DPOR 对每个等价类至少探索一个代表、绝不漏报任一可被穷尽
// 探索发现的失败）。
//
// **Validates: Requirements 6.2, 6.3, 6.4, 6.5**
//
// 差分对照：以 explore_bounded 为 oracle。

///|
/// 生成器：随机种子 + 小规模任务数 + 是否注入恒假不变量（制造确定失败）。
fn p10_gen() -> @infra_pbt.Gen[(UInt64, Int, Bool)] {
  @infra_pbt.Gen::new(fn(rng) {
    (rng.next(), rng.next_range(2, 4), rng.next_bool())
  })
}

///|
/// 构造小规模独立任务场景：恒假不变量 → 必失败；恒真不变量 → 必通过。
fn p10_scenario(n : Int, fail : Bool) -> DesScenario {
  let tasks : Array[Task] = []
  for i in 0..<n {
    tasks.push(Task::new(i, "t\{i}"))
  }
  let inv = if fail {
    Invariant::new("bad", fn(_w) { false })
  } else {
    Invariant::new("ok", fn(_w) { true })
  }
  DesScenario::new(tasks, [], [inv], null_protocol(), n + 4)
}

///|
/// 判定探索报告是否发现失败交错。
fn report_has_failure(rep : ExploreReport) -> Bool {
  match rep.failing {
    Some(_) => true
    None => false
  }
}

///|
/// **Validates: Requirements 6.2, 6.3, 6.4, 6.5**
test "Feature: dst, Property 10: DPOR agrees with bounded on failure existence" {
  let ok = @infra_pbt.holds_for_all(p10_gen(), fn(t) {
    let (seed, n, fail) = t
    let sc = p10_scenario(n, fail)
    let b = explore_bounded(seed, sc, n)
    let d = explore_dpor(seed, sc, n)
    report_has_failure(b) == report_has_failure(d)
  })
  assert_true(ok)
}
