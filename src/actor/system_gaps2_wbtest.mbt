// system_gaps2_wbtest.mbt —— ActorSystem 内部 id 定位防御分支收口
// （INFRA 第二十四批）：O(1) 错位回退扫描、不存在 id 的各内部通路。

///|
test "cell_by_id：O(1) 错位时回退线性扫描仍可命中" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let _a = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  let _b = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  // 人为倒置 cells 顺序，破坏 cells[id-1] 假设 → 走回退扫描。
  let c0 = sys.cells[0]
  sys.cells[0] = sys.cells[1]
  sys.cells[1] = c0
  match sys.cell_by_id(1) {
    Some(cell) => assert_eq(cell.id.value, 1)
    None => assert_true(false)
  }
  match sys.cell_by_id(2) {
    Some(cell) => assert_eq(cell.id.value, 2)
    None => assert_true(false)
  }
  assert_true(sys.cell_by_id(99) is None)
}

///|
test "内部通路：不存在的目标 id 安全忽略" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let _a = sys.spawn(0, Behavior::new(fn(_c, s, _m) { Updated(s) }))
  // enqueue_msg：目标不存在 → 无操作、不置脏。
  sys.enqueue_msg(999, 42)
  assert_false(sys.cross_dirty)
  // reason_of_terminated：未知 id → None。
  assert_true(sys.reason_of_terminated(999) is None)
}
