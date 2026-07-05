// prop_disk_fault_test.mbt —— T8.2 故障注入丰富化：磁盘故障（丢写）建模 +
// 不变量违例最小反例 shrink。
//
// `DiskFault(lose)` 对标 TigerBeetle VOPR 的存储故障注入：目标节点丢失复制
// 日志末尾 `lose` 条已持久条目（torn-write / 丢写）。验证三件事：
//   1. 语义：注入后目标副本日志确实少 `lose` 条，其余副本不受影响；
//   2. 确定性：同种子同场景两次运行的 EvFaulted 序列与终态逐项一致，且
//      trace 经编解码往返无损（DiskFault 参与 R8.1 闭环）；
//   3. shrink：磁盘故障导致的一致性不变量违例可 delta-debugging 收缩到
//      仍失败的最小反例场景。

///|
/// 单领导者复制 + 磁盘故障场景：步 `at` 时副本 `victim` 丢失末尾 1 条日志。
fn disk_fault_scenario(replicas : Int, victim : Int, at : Int) -> DesScenario {
  let tasks : Array[Task] = []
  for i in 0..<replicas {
    tasks.push(Task::new(i, "replica\{i}"))
  }
  DesScenario::new(
    tasks,
    [FaultPolicyEx::new(at, victim, NetFaultKind::DiskFault(lose=1))],
    [],
    replication_protocol(replicas),
    4 * replicas + 16,
  )
}

///|
test "Feature: dst, Fault: DiskFault loses exactly the trailing log entries of the victim" {
  let n = 3
  // 领导者（id 0）在前 n 步唤醒时已本地追加；步 n 对其注入丢写。
  let sc = disk_fault_scenario(n, 0, n)
  let r = run_des(7UL, sc)
  // 受害副本日志比健康副本少 1 条；健康副本之间一致。
  let mut healthy = -1
  let mut victim_len = -1
  for pair in r.finals {
    let (id, app) = pair
    if id == 0 {
      victim_len = app.log.length()
    } else if healthy < 0 {
      healthy = app.log.length()
    } else {
      assert_eq(app.log.length(), healthy)
    }
  }
  assert_true(healthy >= 1)
  assert_eq(victim_len, healthy - 1)
}

///|
test "Feature: dst, Fault: DiskFault runs are deterministic and codec round-trips" {
  let sc = disk_fault_scenario(3, 0, 2)
  let r1 = run_des(11UL, sc)
  let r2 = run_des(11UL, sc)
  assert_true(r1.trace == r2.trace)
  assert_true(r1.finals == r2.finals)
  match deserialize_result(serialize_result(r1)) {
    Ok(back) => {
      assert_true(back.trace == r1.trace)
      assert_true(back.finals == r1.finals)
    }
    Err(_) => fail("含 DiskFault 的运行结果应可编解码往返")
  }
}

///|
test "Feature: dst, Fault: disk-fault-induced invariant violation shrinks to a minimal failing scenario" {
  let n = 3
  let tasks : Array[Task] = []
  for i in 0..<n {
    tasks.push(Task::new(i, "replica\{i}"))
  }
  // 投递收尾步对副本 1 注入丢写 → 「静止态持久性」不变量违例：
  // 无待投递消息时，存活副本不得持有空日志（已确认条目不得丢失）。
  let durability = Invariant::new("静止态持久性", fn(w) {
    if w.queue.is_empty() && w.pending.length() == 0 {
      for nd in w.nodes {
        if nd.alive && nd.app.log.length() == 0 {
          return false
        }
      }
      true
    } else {
      true
    }
  })
  let sc = DesScenario::new(
    tasks,
    [
      FaultPolicyEx::new(n + 1, 1, NetFaultKind::DiskFault(lose=1)),
      FaultPolicyEx::new(2, 2, NetFaultKind::Delay(by=1UL)),
    ],
    [durability],
    replication_protocol(n),
    4 * n + 16,
  )
  let out = shrink(5UL, sc)
  assert_true(out.is_minimal())
  match out.scenario() {
    Some(min_sc) => {
      // 最小反例仍失败，且不大于原场景。
      assert_true(default_fails(run_des(5UL, min_sc)))
      assert_true(min_sc.size() <= sc.size())
    }
    None => fail("应收缩出最小反例")
  }
}
