// prop_p04_escalate_tree_test.mbt —— Property 4：监督树升级传递（任务 11.7）。
//
//   Feature: actor, Property 4: 监督树升级传递
//   ------------------------------------------------------------------
//   *对任意* 两层及以上监督树，当下层子以 Escalate 指令失败时，该失败被上抛至其
//   supervisor，并由上层 supervisor 按其自身策略处置。
//
// **Validates: Requirements 1.5, 2.4**
//
// 拓扑：root 监督 mid（mid 亦为 supervisor），mid 监督 leaf；leaf.directive = Escalate。
// leaf 失败 → 升级至 mid → mid 作为 root 的子（directive = Restart）→ root 按 OneForOne
// 重启 mid，并级联重启其子树（leaf）。

///|
/// 单次场景：leaf 失败并升级，断言 root 重启了 mid（restart_count(mid) == 1），
/// 且 leaf 经级联重启（restart_count(leaf) >= 1），系统最终空闲。
fn p04_escalate_tree(rng : @infra_pbt.Rng) -> Bool {
  ignore(rng)
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let root = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let mid = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let leaf = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) {
      if m < 0 {
        Errored("boom")
      } else {
        Updated(s + m)
      }
    }),
  )
  // root 监督 mid（OneForOne, Restart）。
  sys.supervise(
    root,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Restart),
    [mid],
  )
  // mid 监督 leaf（OneForOne），leaf 指令为 Escalate。
  sys.supervise(
    mid,
    SupervisorSpec::new(OneForOne, RestartIntensity::new(100, 1000), Restart),
    [leaf],
  )
  sys.set_directive(leaf, Escalate)
  leaf.send(-1) // 失败 → Escalate 至 mid → mid 升级至 root → root 重启 mid（级联 leaf）。
  sys.run_until_idle()
  // root 重启了 mid。
  if sys.restart_count(mid) != 1 {
    return false
  }
  // leaf 经级联重启。
  if sys.restart_count(leaf) < 1 {
    return false
  }
  // 系统空闲且 mid / leaf 恢复运行。
  sys.is_running(mid) && sys.is_running(leaf)
}

///|
/// Feature: actor, Property 4: 监督树升级传递（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 1.5, 2.4**
test "Feature: actor, Property 4: escalation propagates to the upper supervisor (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { p04_escalate_tree(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
