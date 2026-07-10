// 白盒测试：覆盖率审计收口（INFRA 第四十七批）——
// ActorSystem 监督树防御余支：幽灵子 id、缺失 supervisor 单元、
// 缺省 spec 回退、apply_scope Escalate 指令与空子列表、空队列处理。

///|
fn ghost_ref(id : Int) -> ActorRef[Int] {
  { id: { value: id }, mailbox: { items: [], closed: false, head: 0 } }
}

///|
fn idle_behavior() -> Behavior[Int, Int] {
  Behavior::new(fn(_ctx, s, _m) { Updated(s) })
}

///|
test "supervise：children 含未登记 id 时跳过指令覆盖" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys.spawn(0, idle_behavior())
  let spec = SupervisorSpec::new(OneForOne, RestartIntensity::new(10, 5), Stop)
  sys.supervise(sup, spec, [ghost_ref(999)])
  assert_true(sys.children.get(sup.id.value) == Some([999]))
}

///|
test "do_restart：级联子列表含幽灵 id 时安全跳过" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys.spawn(0, idle_behavior())
  sys.children.set(sup.id.value, [999])
  match sys.cell_by_id(sup.id.value) {
    Some(cell) => {
      sys.do_restart(cell, "test")
      assert_eq(cell.restart_total, 1)
    }
    None => assert_true(false)
  }
}

///|
test "apply_scope：无子列表、Escalate 指令与幽灵子 id 余支" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let a = sys.spawn(0, idle_behavior())
  let spec = SupervisorSpec::new(
    OneForOne,
    RestartIntensity::new(10, 5),
    Restart,
  )
  let cell = sys.cell_by_id(a.id.value).unwrap()
  // sup_id 无子列表 → kids=[] 空循环。
  sys.apply_scope(777, cell, spec, Restart, "r")
  assert_eq(cell.restart_total, 0)
  // 子列表含幽灵 id → cell_by_id None 跳过；含真实 id + Escalate 指令 → 无操作。
  sys.children.set(777, [999, a.id.value])
  sys.apply_scope(777, cell, spec, Escalate, "r")
  assert_eq(cell.restart_total, 0)
  assert_true(sys.status_of(a) == Some(Running))
}

///|
test "escalate：parents 指向不存在的 supervisor 单元时停止失败者" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let a = sys.spawn(0, idle_behavior())
  sys.parents.set(888, 999) // 888 的 supervisor 999 无对应单元。
  let cell = sys.cell_by_id(a.id.value).unwrap()
  sys.escalate(888, cell, "boom")
  assert_true(sys.status_of(a) == Some(Stopped))
}

///|
test "on_child_failed：有 parent 无 spec 时回退 default_spec 重启" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let sup = sys.spawn(0, idle_behavior())
  let child = sys.spawn(
    0,
    Behavior::new(fn(_ctx, _s, m : Int) {
      if m < 0 {
        Errored("neg")
      } else {
        Updated(m)
      }
    }),
  )
  // 手工接线 parent 但不登记 supervisors spec → default_spec 回退（Restart）。
  sys.parents.set(child.id.value, sup.id.value)
  sys.children.set(sup.id.value, [child.id.value])
  sys.set_directive(child, Restart)
  child.send(-1)
  sys.run_until_idle()
  assert_true(sys.status_of(child) == Some(Running))
  assert_eq(sys.restart_count(child), 1)
}

///|
test "process_one：空邮箱与空行为栈防御返回" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let a = sys.spawn(0, idle_behavior())
  let cell = sys.cell_by_id(a.id.value).unwrap()
  // 空邮箱：dequeue None → 直接返回。
  sys.process_one(cell)
  assert_eq(sys.trace_of().length(), 0)
  // 空行为栈：dequeue 有消息但栈顶缺失 → 防御返回。
  a.send(1)
  while cell.behaviors.length() > 0 {
    let _ = cell.behaviors.pop()
  }
  sys.process_one(cell)
  assert_eq(sys.trace_of().length(), 0)
}
