// dynamic_test.mbt —— 动态依赖单元测试（任务 6.2）。
//
// 覆盖追加引入环时返回承载环节点序列的 Err(Cycle) 并拒绝调度（R8.3），以及
// 不可变追加与无环重调度（R8.1 / R8.2）。

///|
/// 追加引入依赖环 → 返回 Err(Cycle) 并拒绝调度（R8.3）。
test "reschedule_with_dynamic rejects cycle-introducing dynamic dep" {
  let a = Target::new("a")
  let b = Target::new("b")
  // a→b（b 依赖 a）；动态把 b 设为 a 的依赖 → 边 (b, a) → 环 a↔b
  let g = BuildGraph::new([a, b], [(a, b)])
  match reschedule_with_dynamic(g, a, [b], 0) {
    Ok(_) => fail("引入环应拒绝调度")
    Err(cyc) => assert_true(cyc.nodes.length() >= 1)
  }
}

///|
/// 追加登记缺失节点与边，且既有图不变（R8.1，旁路不可变）。
test "add_dynamic_deps appends edge and registers missing node" {
  let a = Target::new("a")
  let b = Target::new("b")
  let g = BuildGraph::new([a, b], [])
  let c = Target::new("c")
  let g2 = add_dynamic_deps(g, b, [c])
  @test.assert_eq(g2.nodes.length(), 3)
  @test.assert_eq(g2.edges.length(), 1)
  let (u, v) = g2.edges[0]
  assert_true(u == c)
  assert_true(v == b)
  // 既有图不变。
  @test.assert_eq(g.nodes.length(), 2)
  @test.assert_eq(g.edges.length(), 0)
}

///|
/// 无环追加后重新调度满足拓扑序（R8.2）。
test "reschedule_with_dynamic schedules acyclic augmented graph" {
  let a = Target::new("a")
  let b = Target::new("b")
  let g = BuildGraph::new([a, b], [])
  // 动态把 a 设为 b 的依赖 → 边 (a, b)
  match reschedule_with_dynamic(g, b, [a], 0) {
    Ok(batches) => {
      @test.assert_eq(batches.length(), 2)
      assert_true(batches[0][0] == a)
      assert_true(batches[1][0] == b)
    }
    Err(_) => fail("无环不应报错")
  }
}
