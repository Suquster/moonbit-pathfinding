// demo.mbt —— DST_Framework 旗舰深化：多副本复制端到端 demo（旁路新增，设计 4.12）。
//
// 贯穿「发现—收缩—重放—校验」闭环（R9.1–9.6）：
//   * `replication_protocol` —— 单领导者广播 + 副本追加日志协议（正常达成日志同步）；
//   * `demo_replication_scenario` —— 正常副本复制场景（终态 `Completed`，副本一致）；
//   * `demo_partition_crash_scenario` —— 注入网络分区 + 崩溃的双提议者（split-brain）
//     场景，两副本在分区下各自提交相互冲突的值，**必然违反副本一致性不变量**（R9.2）；
//   * `replica_consistency_invariant` —— 已提交前缀在各存活副本一致（同一下标不得有
//     冲突值，R9.5）。
//
// 闭环：`demo_partition_crash_scenario` 经 `run_des` 产生违反一致性的失败运行 →
// `shrink` 收缩到仍触发同一不变量违反的最小反例 → 以最小反例 `seed`+`trace` 经
// `replay_des` 复现同一失败终态 → 每步校验副本一致性并在违反时报告不变量名与逻辑
// 时间戳。该 demo 同时供 `README.mbt.md` 文档与 `benches/dst_bench` 复用。

///|
/// 副本一致性不变量（R9.5）：任意两存活副本在重叠下标上不得有冲突值（已提交前缀
/// 一致）。容忍「进行中」的长度差异（较短日志为较长日志的前缀即视为一致），仅当
/// 同一下标出现不同值时判违反。
pub fn replica_consistency_invariant() -> Invariant {
  Invariant::new("副本一致性", fn(world) {
    let nodes = world.nodes
    for a in 0..<nodes.length() {
      let na = nodes[a]
      if na.alive {
        for b in (a + 1)..<nodes.length() {
          let nb = nodes[b]
          if nb.alive {
            let la = na.app.log
            let lb = nb.app.log
            let m = if la.length() < lb.length() {
              la.length()
            } else {
              lb.length()
            }
            for i in 0..<m {
              if la[i] != lb[i] {
                return false
              }
            }
          }
        }
      }
    }
    true
  })
}

///|
/// 单领导者复制协议（R9.1）：领导者（id 0）启动时向本地追加值 `100` 并广播给其余
/// 副本；副本收到后追加该值，最终各副本日志一致。
pub fn replication_protocol(replicas : Int) -> Protocol {
  let leader = 0
  let value = 100
  Protocol::new(
    fn(_id) { NodeApp::empty() },
    fn(app, msg) {
      let log = app.log.copy()
      log.push(msg.payload)
      ({ log, kv: app.kv }, [])
    },
    fn(id) {
      if id == leader {
        let acts : Array[Action] = [ActAppend(value~)]
        for j in 1..<replicas {
          acts.push(ActSend(to=j, payload=value, after=1UL))
        }
        acts
      } else {
        []
      }
    },
  )
}

///|
/// 正常副本复制场景（R9.1）：`replicas` 个副本经单领导者广播达成日志同步，无故障，
/// 终态 `Completed` 且副本一致。
pub fn demo_replication_scenario(replicas : Int) -> DesScenario {
  let tasks : Array[Task] = []
  for i in 0..<replicas {
    tasks.push(Task::new(i, "replica\{i}"))
  }
  DesScenario::new(
    tasks,
    [],
    [replica_consistency_invariant()],
    replication_protocol(replicas),
    replicas * 4 + 16,
  )
}

///|
/// 双提议者（split-brain）协议：副本 0 提议值 `100`、副本 3 提议值 `200`，各自向本地
/// 追加并广播；副本采用「先到先写」（first-write-wins）。分区下两提议者无法互相协调，
/// 其本地日志在下标 0 出现冲突值，必然违反副本一致性。
fn dual_proposer_protocol() -> Protocol {
  Protocol::new(
    fn(_id) { NodeApp::empty() },
    fn(app, msg) {
      if app.log.length() == 0 {
        let log = app.log.copy()
        log.push(msg.payload)
        ({ log, kv: app.kv }, [])
      } else {
        (app, [])
      }
    },
    fn(id) {
      if id == 0 {
        [
          ActAppend(value=100),
          ActSend(to=1, payload=100, after=1UL),
          ActSend(to=2, payload=100, after=1UL),
          ActSend(to=3, payload=100, after=1UL),
        ]
      } else if id == 3 {
        [
          ActAppend(value=200),
          ActSend(to=0, payload=200, after=1UL),
          ActSend(to=1, payload=200, after=1UL),
          ActSend(to=2, payload=200, after=1UL),
        ]
      } else {
        []
      }
    },
  )
}

///|
/// 注入网络分区 + 崩溃的失败场景（R9.2）：4 副本，分区为 `{0,1}` 与 `{2,3}` 两组并
/// 对副本 1 注入崩溃；双提议者（0 提议 100、3 提议 200）在分区下各自提交冲突值，
/// `run_des` 必然以违反副本一致性不变量的 `Failed` 终止。
pub fn demo_partition_crash_scenario() -> DesScenario {
  let tasks = [
    Task::new(0, "replica0"),
    Task::new(1, "replica1"),
    Task::new(2, "replica2"),
    Task::new(3, "replica3"),
  ]
  // 分区：副本 0/1 归组 0，副本 2/3 归组 1，生效区间 [0, 16)；并对副本 1 注入崩溃。
  let faults = [
    FaultPolicyEx::new(0, 0, NetFaultKind::Partition(group=0, until_step=16)),
    FaultPolicyEx::new(0, 1, NetFaultKind::Partition(group=0, until_step=16)),
    FaultPolicyEx::new(0, 2, NetFaultKind::Partition(group=1, until_step=16)),
    FaultPolicyEx::new(0, 3, NetFaultKind::Partition(group=1, until_step=16)),
    FaultPolicyEx::new(2, 1, NetFaultKind::Crash),
  ]
  DesScenario::new(
    tasks,
    faults,
    [replica_consistency_invariant()],
    dual_proposer_protocol(),
    40,
  )
}

///|
/// 失败判据：终态为 `Failed` 且失败原因标识副本一致性不变量（用于收缩时锁定「同一
/// 不变量违反」的最小反例，R9.3）。
pub fn violates_consistency(r : DesResult) -> Bool {
  match r.status {
    Failed(reason~) => str_contains(reason, "副本一致性")
    _ => false
  }
}

///|
/// 朴素子串包含判定（避免外部依赖）。
fn str_contains(hay : String, needle : String) -> Bool {
  let h : Array[Char] = []
  for c in hay {
    h.push(c)
  }
  let n : Array[Char] = []
  for c in needle {
    n.push(c)
  }
  if n.length() == 0 {
    return true
  }
  if h.length() < n.length() {
    return false
  }
  for i in 0..<(h.length() - n.length() + 1) {
    let mut ok = true
    for j in 0..<n.length() {
      if h[i + j] != n[j] {
        ok = false
        break
      }
    }
    if ok {
      return true
    }
  }
  false
}
