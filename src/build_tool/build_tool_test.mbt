// build_tool_test.mbt —— Build_Tool 的单元测试（任务 9.1 + 9.2）。
//
// 在小型确定性夹具上校验：核心类型可构造、规则解析、拓扑序复用、环检测、
// 并行批次调度，以及基于 mtime + 内容哈希的增量空操作脏检查。拓扑不变量
// 与环检测 / 增量幂等的属性测试由后续任务 9.3 / 9.4 单独承载。
//
// 说明：对 `Option` / `Array` / `Target` 等复合类型的等值校验采用
// `assert_true(x == y)`（走 `Eq`），以避免触发 `Show`-用于-debug 的弃用
// 告警，保持本包零告警。

///|
/// parse_rules 解析「目标 : 依赖」规则为节点与依赖边（去重、保序）。
test "parse_rules parses targets and dependency edges" {
  match parse_rules("app: main.o util.o") {
    Ok(g) => {
      // 节点：app、main.o、util.o（按首次出现）。
      assert_eq(g.nodes.length(), 3)
      assert_true(g.nodes[0] == Target::new("app"))
      // 边：(main.o → app)、(util.o → app)。
      assert_eq(g.edges.length(), 2)
      let (d0, t0) = g.edges[0]
      assert_true(d0 == Target::new("main.o"))
      assert_true(t0 == Target::new("app"))
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}

///|
/// parse_rules 跳过空行与注释行，并跨规则去重共享节点。
test "parse_rules skips comments and dedups shared nodes" {
  let src = "# 顶层产物\napp: a.o b.o\n\na.o: common.h\nb.o: common.h\n"
  match parse_rules(src) {
    Ok(g) => {
      // 节点：app、a.o、b.o、common.h —— common.h 仅登记一次。
      assert_eq(g.nodes.length(), 4)
      // 边：(a.o→app)、(b.o→app)、(common.h→a.o)、(common.h→b.o)。
      assert_eq(g.edges.length(), 4)
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}

///|
/// parse_rules 对缺少 ':' 分隔符的行返回带行号的解析错误。
test "parse_rules reports missing colon with line number" {
  match parse_rules("app: a.o\nthis line has no colon\n") {
    Ok(_) => fail("非法规则应解析失败")
    Err(e) => assert_eq(e.line, 2)
  }
}

///|
/// topo_order 复用 @directed 在线性依赖 a→b→c 上给出正确拓扑序。
test "topo_order reuses directed for linear dependency" {
  let a = Target::new("a")
  let b = Target::new("b")
  let c = Target::new("c")
  // 依赖边 (u, v) 表示 u 必须在 v 之前：a→b、b→c。
  let g = BuildGraph::new([a, b, c], [(a, b), (b, c)])
  match topo_order(g) {
    Ok(order) => {
      assert_eq(order.length(), 3)
      assert_true(order[0] == a)
      assert_true(order[2] == c)
    }
    Err(_) => fail("无环图不应报告环")
  }
}

///|
/// topo_order 在空图上成功并返回空序列（边界）。
test "topo_order on empty graph returns empty order" {
  match topo_order(BuildGraph::new([], [])) {
    Ok(order) => assert_eq(order.length(), 0)
    Err(_) => fail("空图不应报告环")
  }
}

///|
/// schedule 把无相互依赖的目标放入同一批次（整层一批）。
test "schedule groups independent targets into one batch" {
  let a = Target::new("a")
  let b = Target::new("b")
  let batches = schedule(BuildGraph::new([a, b], []), 4)
  assert_eq(batches.length(), 1)
  assert_eq(batches[0].length(), 2)
}

///|
/// schedule 按拓扑分层：a→b→c 产出三个单元素批次且顺序正确。
test "schedule produces topological layers for a linear chain" {
  let a = Target::new("a")
  let b = Target::new("b")
  let c = Target::new("c")
  // a 在 b 之前、b 在 c 之前。
  let batches = schedule(BuildGraph::new([a, b, c], [(a, b), (b, c)]), 4)
  assert_eq(batches.length(), 3)
  assert_true(batches[0][0] == a)
  assert_true(batches[1][0] == b)
  assert_true(batches[2][0] == c)
}

///|
/// schedule 在 jobs 受限时把宽层切分为多个批宽不超过 jobs 的批次。
test "schedule splits a wide layer by the jobs limit" {
  let nodes = [
    Target::new("a"),
    Target::new("b"),
    Target::new("c"),
    Target::new("d"),
    Target::new("e"),
  ]
  // 五个相互无依赖的目标，并行度上限 2 → 切为 2 + 2 + 1 三批。
  let batches = schedule(BuildGraph::new(nodes, []), 2)
  assert_eq(batches.length(), 3)
  assert_eq(batches[0].length(), 2)
  assert_eq(batches[1].length(), 2)
  assert_eq(batches[2].length(), 1)
}

///|
/// is_dirty 对空缓存（无当前指纹）保守判定为需重建。
test "is_dirty conservatively reports dirty without fingerprints" {
  assert_true(is_dirty(Target::new("x"), BuildCache::new()))
}

///|
/// is_dirty：当前指纹与基线一致 → 干净（增量空操作的基础）。
test "is_dirty is clean when current matches recorded fingerprint" {
  let cache = BuildCache::new()
  cache.observe("app", 100L, "h1")
  cache.mark_built("app") // 固化基线：基线 == 当前
  assert_false(is_dirty(Target::new("app"), cache))
}

///|
/// is_dirty：mtime 变化 → 脏；内容哈希变化 → 脏。
test "is_dirty detects mtime and content hash changes" {
  // mtime 变化。
  let c1 = BuildCache::new()
  c1.observe("app", 100L, "h1")
  c1.mark_built("app")
  c1.observe("app", 200L, "h1") // 仅 mtime 变
  assert_true(is_dirty(Target::new("app"), c1))
  // 内容哈希变化。
  let c2 = BuildCache::new()
  c2.observe("app", 100L, "h1")
  c2.mark_built("app")
  c2.observe("app", 100L, "h2") // 仅哈希变
  assert_true(is_dirty(Target::new("app"), c2))
}

///|
/// 增量空操作：一次成功构建后输入未变，则全部目标判为干净（零重建）。
test "incremental no-op: nothing dirty after a build with no changes" {
  let g = match parse_rules("app: a.o b.o\na.o: common.h\nb.o: common.h\n") {
    Ok(graph) => graph
    Err(_) => {
      fail("夹具规则不应解析失败")
      BuildGraph::new([], [])
    }
  }
  let cache = BuildCache::new()
  // 观测全部目标输入指纹并标记为已构建。
  for n in g.nodes {
    cache.observe(n.name, 1L, "hash-" + n.name)
    cache.mark_built(n.name)
  }
  // 输入未变：再次构建对所有目标零重建。
  let mut rebuilt = 0
  for n in g.nodes {
    if is_dirty(n, cache) {
      rebuilt += 1
    }
  }
  assert_eq(rebuilt, 0)
}

///|
/// detect_cycle 对无环图返回 None。
test "detect_cycle returns none for an acyclic graph" {
  let g = BuildGraph::new([Target::new("a")], [])
  assert_true(detect_cycle(g) is None)
}

///|
/// detect_cycle 报告构成环的目标序列（a→b→a）。
test "detect_cycle reports the nodes of a dependency cycle" {
  let a = Target::new("a")
  let b = Target::new("b")
  let g = BuildGraph::new([a, b], [(a, b), (b, a)])
  match detect_cycle(g) {
    Some(cyc) => assert_eq(cyc.length(), 2)
    None => fail("应检出 a↔b 依赖环")
  }
}

///|
/// detect_cycle 识别自环（目标依赖自身）。
test "detect_cycle detects a self-loop" {
  let a = Target::new("a")
  let g = BuildGraph::new([a], [(a, a)])
  match detect_cycle(g) {
    Some(cyc) => {
      assert_eq(cyc.length(), 1)
      assert_true(cyc[0] == a)
    }
    None => fail("应检出自环")
  }
}

///|
/// topo_order 在存在环时返回含具体环节点序列的 Cycle。
test "topo_order returns a cycle with node sequence on cyclic graph" {
  let a = Target::new("a")
  let b = Target::new("b")
  match topo_order(BuildGraph::new([a, b], [(a, b), (b, a)])) {
    Ok(_) => fail("有环图不应给出拓扑序")
    Err(cyc) => assert_eq(cyc.nodes.length(), 2)
  }
}
