// demo_test.mbt —— 旗舰端到端 demo 单元测试（任务 9.2）。
//
// 断言 parse_rules(demo_rules()) 与 demo_graph() 一致、detect_cycle 返回 None、
// schedule 满足拓扑 + 批内独立、单源变更下 minimal_rebuild_set 仅含该源下游且
// 相对全量目标数缩减（R10.2 – R10.5）。

///|
/// demo 规则解析为期望构建图（R10.2）。
test "demo_rules parses to demo_graph" {
  match parse_rules(demo_rules()) {
    Ok(g) => {
      let expected = demo_graph()
      assert_true(targets_eq(g.nodes, expected.nodes))
      assert_true(edges_eq(g.edges, expected.edges))
    }
    Err(_) => fail("demo 规则不应解析失败")
  }
}

///|
/// demo 工程图无依赖环（R10.3）。
test "demo graph is acyclic" {
  assert_true(detect_cycle(demo_graph()) is None)
}

///|
/// demo 调度满足拓扑不变量与批内独立（R10.4）。
test "demo schedule respects topology and intra-batch independence" {
  let g = demo_graph()
  let batches = schedule(g, 0)
  let pos = position_map(batches)
  let bi = batch_index_map(batches)
  assert_eq(flatten_order(batches).length(), g.nodes.length())
  for edge in g.edges {
    let (u, v) = edge
    assert_true(pos.get(u).unwrap() < pos.get(v).unwrap())
    assert_true(bi.get(u).unwrap() != bi.get(v).unwrap())
  }
}

///|
/// 单源变更下最小重建集仅含该源传递下游，相对全量目标数缩减（R10.5）。
test "demo single-source change yields a reduced rebuild set" {
  let g = demo_graph()
  let set = minimal_rebuild_set(g, [Target::new("util_a.c")])
  // util_a.c → util_a.o → libutil.a → app（4 个，相对 10 个全量目标缩减）
  assert_eq(set.length(), 4)
  assert_true(set.length() < g.nodes.length())
  assert_true(list_contains_target(set, Target::new("util_a.c")))
  assert_true(list_contains_target(set, Target::new("util_a.o")))
  assert_true(list_contains_target(set, Target::new("libutil.a")))
  assert_true(list_contains_target(set, Target::new("app")))
  assert_false(list_contains_target(set, Target::new("core_a.o")))
}
