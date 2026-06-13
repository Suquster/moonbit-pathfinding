// scheduler_test.mbt —— 调度增强单元测试（任务 5.2）。
//
// 覆盖 jobs<=0 整层一批（R7.3）、关键路径长度 == 不限并行批次层数（R7.4）。

///|
/// jobs<=0 视为不限并行度，整层作为一个批次（R7.3）。
test "schedule with jobs<=0 keeps each layer as one batch" {
  let nodes = [
    Target::new("a"),
    Target::new("b"),
    Target::new("c"),
    Target::new("d"),
  ]
  let batches = schedule(BuildGraph::new(nodes, []), 0)
  assert_eq(batches.length(), 1)
  assert_eq(batches[0].length(), 4)
}

///|
/// 链 a→b→c：关键路径长度 == 批次层数 == 3（R7.4）。
test "critical_path_length equals number of layers for a chain" {
  let a = Target::new("a")
  let b = Target::new("b")
  let c = Target::new("c")
  let g = BuildGraph::new([a, b, c], [(a, b), (b, c)])
  assert_eq(critical_path_length(g), 3)
  assert_eq(critical_path_length(g), schedule(g, 0).length())
  assert_eq(min_layers(g), 3)
}

///|
/// 菱形 a→{b,c}→d：关键路径长度 == 3（最长链 a→b→d）。
test "critical_path_length of a diamond is three" {
  let a = Target::new("a")
  let b = Target::new("b")
  let c = Target::new("c")
  let d = Target::new("d")
  let g = BuildGraph::new([a, b, c, d], [(a, b), (a, c), (b, d), (c, d)])
  assert_eq(critical_path_length(g), 3)
  assert_eq(critical_path_length(g), schedule(g, 0).length())
}

///|
/// 空图关键路径长度为 0（边界）。
test "critical_path_length of an empty graph is zero" {
  assert_eq(critical_path_length(BuildGraph::new([], [])), 0)
}
