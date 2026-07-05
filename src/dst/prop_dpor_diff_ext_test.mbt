// prop_dpor_diff_ext_test.mbt —— T8.1 DPOR 完备性强化：真实竞态场景差分扩样本。
//
// 既有 Property 10/11 以「恒真/恒假不变量」的独立任务做差分——失败与调度顺序
// 无关。本文件把 oracle 差分推进到**顺序敏感**场景：双领导者竞态广播（任务 0
// 广播 1、任务 1 广播 2），不变量要求全部副本日志逐项一致——是否存在失败交错
// 取决于消息投递交织。对随机种子/规模扩样本断言 `explore_dpor` 与穷举
// `explore_bounded` 对「是否存在失败交错」的结论一致（DPOR 不漏 bug），且
// DPOR 的失败凭据可经 `replay_des` 精确复现失败。

///|
/// 双领导者竞态协议：任务 0 与任务 1 同时向所有节点（含自身）广播各自的值，
/// 副本按收到顺序追加日志——日志顺序由调度交织决定。
fn dual_leader_protocol(replicas : Int, v0 : Int, v1 : Int) -> Protocol {
  Protocol::new(
    fn(_id) { NodeApp::empty() },
    fn(app, msg) {
      let log = app.log.copy()
      log.push(msg.payload)
      ({ log, kv: app.kv }, [])
    },
    fn(id) {
      if id == 0 || id == 1 {
        let v = if id == 0 { v0 } else { v1 }
        let acts : Array[Action] = []
        for j in 0..<replicas {
          acts.push(ActSend(to=j, payload=v, after=1UL))
        }
        acts
      } else {
        []
      }
    },
  )
}

///|
/// 顺序敏感不变量：等长日志必逐项一致（允许长度不同的瞬态，
/// 仅当两副本收齐同量消息却顺序不同时违例）——失败与否取决于投递交织。
fn logs_agree_invariant() -> Invariant {
  Invariant::new("等长日志全序一致", fn(w) {
    let mut ok = true
    for i in 1..<w.nodes.length() {
      let a = w.nodes[0].app.log
      let b = w.nodes[i].app.log
      if a.length() == b.length() {
        for k in 0..<a.length() {
          if a[k] != b[k] {
            ok = false
          }
        }
      }
    }
    ok
  })
}

///|
/// 生成器：随机种子 + 副本数 2..4。
fn t81_gen() -> @infra_pbt.Gen[(UInt64, Int)] {
  @infra_pbt.Gen::new(fn(rng) { (rng.next(), rng.next_range(2, 4)) })
}

///|
/// **Validates: Requirements 6.2–6.6（顺序敏感场景扩样本）**
test "Feature: dst, Property: DPOR agrees with exhaustive oracle on race-sensitive scenarios" {
  let ok = @infra_pbt.holds_for_all(t81_gen(), fn(t) {
    let (seed, n) = t
    let tasks : Array[Task] = []
    for i in 0..<n {
      tasks.push(Task::new(i, "node\{i}"))
    }
    let sc = DesScenario::new(
      tasks,
      [],
      [logs_agree_invariant()],
      dual_leader_protocol(n, 1, 2),
      4 * n + 16,
    )
    let b = explore_bounded(seed, sc, n)
    let d = explore_dpor(seed, sc, n)
    // 结论一致：DPOR 不漏任何穷举可发现的失败，也不虚报。
    let agree = match (b.failing, d.failing) {
      (Some(_), Some(_)) | (None, None) => true
      _ => false
    }
    // DPOR 的失败凭据必可精确重放出失败。
    let replayable = match d.failing {
      Some((s, trace)) => default_fails(replay_des(s, trace))
      None => true
    }
    agree && replayable
  })
  assert_true(ok)
}
