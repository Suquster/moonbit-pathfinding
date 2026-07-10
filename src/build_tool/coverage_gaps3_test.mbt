// coverage_gaps3_test.mbt —— 覆盖率审计收口（INFRA 第四十六批）：
// 规则解析防御、无基线脏判定、未登记边忽略、Show 渲染、DFS 重访、
// 循环图调度余支、mark_built 无操作、工作区悬空依赖终止。

///|
test "parse_rules：空目标名拒绝" {
  assert_true(@build_tool.parse_rules(" : dep") is Err(_))
}

///|
test "is_dirty：有当前指纹但无构建基线视为脏" {
  let c = @build_tool.BuildCache::new()
  c.observe("a.o", 1L, "h1")
  assert_true(@build_tool.is_dirty(@build_tool.Target::new("a.o"), c))
}

///|
test "schedule：指向未登记节点的边被忽略" {
  let a = @build_tool.Target::new("a")
  let ghost = @build_tool.Target::new("ghost")
  let g = @build_tool.BuildGraph::new([a], [(a, ghost)])
  let batches = @build_tool.schedule(g, 0)
  assert_eq(batches.length(), 1)
  assert_eq(batches[0].length(), 1)
  assert_eq(batches[0][0].name, "a")
}

///|
test "deserialize_cache：当前 mtime 段非法数值拒绝" {
  assert_true(@build_tool.deserialize_cache("m a.o xx") is Err(_))
}

///|
test "Show：Target / Action / ActionResult 文本渲染" {
  assert_eq(@build_tool.Target::new("t").to_string(), "t")
  let act : @build_tool.Action = {
    id: "a",
    inputs: ["i"],
    outputs: ["o"],
    command: "cc",
  }
  assert_eq(
    act.to_string(),
    "Action(id=a, command=cc, inputs=[i], outputs=[o])",
  )
  assert_eq(
    @build_tool.ActionResult::Executed(output_hash="h").to_string(),
    "Executed(output_hash=h)",
  )
  assert_eq(@build_tool.ActionResult::Skipped.to_string(), "Skipped")
}

///|
test "propagate_dirty：脏输入不在节点集时仍纳入结果" {
  let a = @build_tool.Target::new("a")
  let z = @build_tool.Target::new("z")
  let g = @build_tool.BuildGraph::new([a], [])
  let out = @build_tool.propagate_dirty(g, [z])
  assert_eq(out.length(), 1)
  assert_eq(out[0].name, "z")
}

///|
test "write_conflicts：菱形依赖下可达性 DFS 重访不重复展开" {
  let a : @build_tool.Action = {
    id: "a",
    inputs: [],
    outputs: ["o"],
    command: "a",
  }
  let b : @build_tool.Action = {
    id: "b",
    inputs: [],
    outputs: ["b.o"],
    command: "b",
  }
  let c : @build_tool.Action = {
    id: "c",
    inputs: [],
    outputs: ["c.o"],
    command: "c",
  }
  let d : @build_tool.Action = {
    id: "d",
    inputs: [],
    outputs: ["d.o"],
    command: "d",
  }
  let e : @build_tool.Action = {
    id: "e",
    inputs: [],
    outputs: ["o"],
    command: "e",
  }
  let edges = [("a", "b"), ("a", "c"), ("b", "d"), ("c", "d")]
  let conflicts = @build_tool.write_conflicts([a, b, c, d, e], edges)
  assert_eq(conflicts.length(), 1)
  let (x, y, out) = conflicts[0]
  assert_eq(out, "o")
  assert_true((x == "a" && y == "e") || (x == "e" && y == "a"))
}

///|
test "critical_path_length / schedule_critical_path：循环图与未登记边余支" {
  let a = @build_tool.Target::new("a")
  let b = @build_tool.Target::new("b")
  let cyc = @build_tool.BuildGraph::new([a, b], [(a, b), (b, a)])
  assert_eq(@build_tool.critical_path_length(cyc), 0)
  // 循环图：无入度为 0 的就绪目标，调度批次为空。
  assert_eq(@build_tool.schedule_critical_path(cyc, 1).length(), 0)
  // 指向未登记节点的边被忽略，单节点独立成波。
  let ghost = @build_tool.Target::new("ghost")
  let g = @build_tool.BuildGraph::new([a], [(a, ghost)])
  let batches = @build_tool.schedule_critical_path(g, 1)
  assert_eq(batches.length(), 1)
  assert_eq(batches[0].length(), 1)
  assert_eq(batches[0][0].name, "a")
}

///|
test "mark_built：无当前观测指纹时为无操作" {
  let c = @build_tool.BuildCache::new()
  c.mark_built("ghost")
  assert_true(@build_tool.is_dirty(@build_tool.Target::new("ghost"), c))
}

///|
test "transitive_deps：依赖未登记包时正常终止" {
  let ws = @build_tool.Workspace::new([
    @build_tool.WorkspacePackage::new("a", ["b"]),
  ])
  let deps = ws.transitive_deps("a")
  assert_eq(deps.length(), 1)
  assert_eq(deps[0], "b")
}
