// gaps81_test.mbt —— replay_consistent 拒绝路径收口（第八十一批）。
//
// replay_consistent 的两条 false 分支要求 build 闭包本身非确定：
// 用捕获的外部可变计数器令两次构造产生不同的投递计划。

///|
/// 两次构造投递条数不同 → trace 长度不同 → false。
test "replay_consistent：trace 长度不一致被拒绝" {
  let calls : Ref[Int] = Ref::{ val: 0 }
  let build = fn(s : UInt64) -> ActorSystem[Int, Int] {
    let sys : ActorSystem[Int, Int] = ActorSystem::with_seed(s)
    let a = sys.spawn(0, Behavior::new(fn(_c, st, m) { Updated(st + m) }))
    calls.val = calls.val + 1
    // 第二次构造多投一条消息，处理事件数必然不同。
    let extra = if calls.val >= 2 { 2 } else { 1 }
    for j in 0..<extra {
      a.send(j + 1)
    }
    sys
  }
  assert_false(replay_consistent(7UL, build))
}

///|
/// 两次构造投递条数相同但目标 actor 不同 → 长度相同、逐事件不同 → false。
test "replay_consistent：trace 同长异序被拒绝" {
  let calls : Ref[Int] = Ref::{ val: 0 }
  let build = fn(s : UInt64) -> ActorSystem[Int, Int] {
    let sys : ActorSystem[Int, Int] = ActorSystem::with_seed(s)
    let a = sys.spawn(0, Behavior::new(fn(_c, st, m) { Updated(st + m) }))
    let b = sys.spawn(0, Behavior::new(fn(_c, st, m) { Updated(st + m) }))
    calls.val = calls.val + 1
    // 第一次全投 a，第二次全投 b：事件数相同，actor id 序列不同。
    let target = if calls.val >= 2 { b } else { a }
    for j in 0..<3 {
      target.send(j + 1)
    }
    sys
  }
  assert_false(replay_consistent(7UL, build))
}
