// des_helpers_test.mbt —— DST 旗舰深化测试的共享辅助（仅测试期，包内可见）。
//
// 这些 `fn` 定义在 `_test.mbt` 中，仅参与测试可执行体编译，不进入运行时产物；
// 供同包各测试文件复用（提取调度投影、统计投递、读取节点日志、协议构造等）。

///|
/// 提取 DES 轨迹中 `EvScheduled` 的任务 id 序列（调度投影）。
fn des_scheduled_ids(trace : Array[SimEvent]) -> Array[Int] {
  let out : Array[Int] = []
  for e in trace {
    match e {
      EvScheduled(task_id~, ..) => out.push(task_id)
      _ => ()
    }
  }
  out
}

///|
/// 提取既有 `Event` 轨迹中 `Scheduled` 的任务 id 序列（既有 `run` 的调度投影）。
fn legacy_scheduled_ids(trace : Array[Event]) -> Array[Int] {
  let out : Array[Int] = []
  for e in trace {
    match e {
      Scheduled(task_id~, ..) => out.push(task_id)
      _ => ()
    }
  }
  out
}

///|
/// 统计轨迹中投递事件总数。
fn count_deliveries(trace : Array[SimEvent]) -> Int {
  let mut n = 0
  for e in trace {
    match e {
      EvDeliver(..) => n = n + 1
      _ => ()
    }
  }
  n
}

///|
/// 统计投递到目标节点 `target` 的事件数。
fn count_deliveries_to(trace : Array[SimEvent], target : Int) -> Int {
  let mut n = 0
  for e in trace {
    match e {
      EvDeliver(to~, ..) => if to == target { n = n + 1 }
      _ => ()
    }
  }
  n
}

///|
/// 从仿真结果终态读取节点 `id` 的日志（不存在返回空）。
fn node_log_from_finals(finals : Array[(Int, NodeApp)], id : Int) -> Array[Int] {
  for pair in finals {
    let (i, app) = pair
    if i == id {
      return app.log
    }
  }
  []
}

///|
/// 测试协议：节点 0 向节点 1 发送一条负载为 7 的消息；节点收到即追加该负载。
fn one_send_protocol() -> Protocol {
  Protocol::new(fn(_id) { NodeApp::empty() }, fn(app, msg) {
    let log = app.log.copy()
    log.push(msg.payload)
    ({ log, kv: app.kv }, [])
  }, fn(id) { if id == 0 { [ActSend(to=1, payload=7, after=1UL)] } else { [] } })
}

///|
/// 测试协议：节点 0 向节点 1 连续发送负载 7、8 两条消息；节点收到即追加。
fn double_send_protocol() -> Protocol {
  Protocol::new(fn(_id) { NodeApp::empty() }, fn(app, msg) {
    let log = app.log.copy()
    log.push(msg.payload)
    ({ log, kv: app.kv }, [])
  }, fn(id) {
    if id == 0 {
      [ActSend(to=1, payload=7, after=1UL), ActSend(to=1, payload=8, after=1UL)]
    } else {
      []
    }
  })
}


///|
/// 朴素子串包含判定（测试期辅助；主源 `str_contains` 为包私有不跨黑盒测试边界）。
fn tcontains(hay : String, needle : String) -> Bool {
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


///|
/// 阶乘（供有界穷尽探索完整性属性以参考计数）。
fn factorial(n : Int) -> Int {
  let mut acc = 1
  let mut i = 2
  while i <= n {
    acc = acc * i
    i = i + 1
  }
  acc
}

///|
/// 过滤出轨迹中的 EvFaulted 事件子序列。
fn faulted_events(trace : Array[SimEvent]) -> Array[SimEvent] {
  let out : Array[SimEvent] = []
  for e in trace {
    match e {
      EvFaulted(..) => out.push(e)
      _ => ()
    }
  }
  out
}


///|
/// 采样一个扩展故障类型（覆盖全部 NetFaultKind 变体，供故障 / 时序属性使用）。
fn sample_netfault(rng : @infra_pbt.Rng, _n : Int) -> NetFaultKind {
  match rng.next_below(7) {
    0 => NetFaultKind::Crash
    1 => NetFaultKind::Delay(by=rng.next_range(1, 3).to_uint64())
    2 => NetFaultKind::Drop
    3 =>
      NetFaultKind::Partition(group=rng.next_below(2), until_step=rng.next_range(2, 30))
    4 => NetFaultKind::Reorder
    5 => NetFaultKind::Duplicate
    _ => NetFaultKind::ClockSkew(offset=(rng.next_range(0, 6) - 3).to_int64())
  }
}
