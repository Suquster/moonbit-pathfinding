// rebuild_test.mbt —— 脏传播与最小重建集单元测试（任务 4.2）。
//
// 覆盖未受影响目标被排除、仅重建集内目标进入调度、脏检查指纹边界
// （R5.3 / R5.4 / R6.1 / R6.2）。

///|
/// 最小重建集仅含脏输入的传递下游（排除上游与无关目标，R5.3）。
test "minimal_rebuild_set includes only downstream of dirty input" {
  let a = Target::new("a")
  let b = Target::new("b")
  let c = Target::new("c")
  let d = Target::new("d")
  let g = BuildGraph::new([a, b, c, d], [(a, b), (b, c)])
  let set = minimal_rebuild_set(g, [b])
  assert_true(list_contains_target(set, b))
  assert_true(list_contains_target(set, c))
  assert_false(list_contains_target(set, a))
  assert_false(list_contains_target(set, d))
}

///|
/// 重建调度仅含重建集内目标且满足拓扑序（R5.4）。
test "rebuild_schedule only schedules rebuild-set targets in topo order" {
  let a = Target::new("a")
  let b = Target::new("b")
  let c = Target::new("c")
  let d = Target::new("d")
  let g = BuildGraph::new([a, b, c, d], [(a, b), (b, c)])
  let batches = rebuild_schedule(g, [b], 0)
  @test.assert_eq(batches.length(), 2)
  assert_true(batches[0][0] == b)
  assert_true(batches[1][0] == c)
}

///|
/// dirty_targets 依 is_dirty 指纹比对识别脏目标（R6.1 / R6.2）。
test "dirty_targets reflects is_dirty fingerprint comparison" {
  let a = Target::new("a")
  let b = Target::new("b")
  let g = BuildGraph::new([a, b], [(a, b)])
  let cache = BuildCache::new()
  cache.observe("a", 1L, "h")
  cache.mark_built("a")
  cache.observe("b", 1L, "h")
  cache.mark_built("b")
  cache.observe("b", 2L, "h2") // b 的当前指纹相对基线变化 → 脏
  let dirty = dirty_targets(g, cache)
  assert_true(list_contains_target(dirty, b))
  assert_false(list_contains_target(dirty, a))
}
