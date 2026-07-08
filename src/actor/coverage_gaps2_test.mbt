// 黑盒测试：actor 系统 spawn 有界邮箱 / 同一监督者多子注册分支。

///|
test "spawn：有界邮箱参数与同一监督者的多子注册" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys.spawn(0, Behavior::new(fn(_c, s, m) { Updated(s + m) }))
  // 第一个子：children 表新建；第二个子：push 既有列表分支。
  let c1 = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) { Updated(s + m) }),
    supervisor=sup,
    bounded=(2, DropNewest),
  )
  let c2 = sys.spawn(
    0,
    Behavior::new(fn(_c, s, m) { Updated(s + m) }),
    supervisor=sup,
    bounded=(1, Reject),
  )
  c1.send(1)
  c2.send(2)
  sys.run_until_idle()
  assert_true(sys.state_of(c1) == Some(1))
  assert_true(sys.state_of(c2) == Some(2))
  assert_true(sys.is_running(sup))
}
