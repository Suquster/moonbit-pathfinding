// benches/build_tool_bench — Build_Tool 旗舰深化性能基准与回归 guard。
//
// 对应 design.md §4.9（R11）。参数化 DAG（链 / 扇出 / 分层网格）上对四类工作
// 负载计时：拓扑排序（`@bt.topo_order`）、并行调度（`@bt.schedule`）、脏检查
// （`@bt.dirty_targets` / `is_dirty`）、最小重建集（`@bt.minimal_rebuild_set`）。
//
// 回归 guard（R11.3）：拓扑层数 / 关键路径长度 / 重建集规模对内联基线精确比较，
// 偏离给出可审计失败报告。冒烟 guard 在大规模图上校验核心不变量。
//
// 运行（R11.4 / R11.5）：
//   moon test  -p Suquster/moonbit-pathfinding/benches/build_tool_bench --target wasm-gc
//   moon bench -p Suquster/moonbit-pathfinding/benches/build_tool_bench --target native
// native 运行前须先：export LIBRARY_PATH=/usr/lib64:/usr/lib
//
// _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

// ---------------------------------------------------------------------------
// 参数化 DAG 生成
// ---------------------------------------------------------------------------

///|
/// 链图：`n` 节点 `n0 → n1 → … → n{n-1}`（n-1 条边，关键路径 = n）。
fn chain_graph(n : Int) -> @bt.BuildGraph {
  let nodes : Array[@bt.Target] = []
  for i in 0..<n {
    nodes.push(@bt.Target::new("n" + i.to_string()))
  }
  let edges : Array[(@bt.Target, @bt.Target)] = []
  for i in 0..<(n - 1) {
    edges.push((nodes[i], nodes[i + 1]))
  }
  @bt.BuildGraph::new(nodes, edges)
}

///|
/// 扇出图：单源 `src` → `width` 个叶子（width 条边，2 个调度批次）。
fn fanout_graph(width : Int) -> @bt.BuildGraph {
  let src = @bt.Target::new("src")
  let nodes : Array[@bt.Target] = [src]
  let edges : Array[(@bt.Target, @bt.Target)] = []
  for i in 0..<width {
    let leaf = @bt.Target::new("leaf" + i.to_string())
    nodes.push(leaf)
    edges.push((src, leaf))
  }
  @bt.BuildGraph::new(nodes, edges)
}

///|
/// 分层网格：`layers` 层 × `width` 宽，相邻层全二部连接（节点 layers×width，
/// 边 (layers-1)×width²，关键路径 = layers，每层调度批宽 = width）。
fn layered_grid(layers : Int, width : Int) -> @bt.BuildGraph {
  let nodes : Array[@bt.Target] = []
  for l in 0..<layers {
    for w in 0..<width {
      nodes.push(@bt.Target::new("L" + l.to_string() + "_W" + w.to_string()))
    }
  }
  let edges : Array[(@bt.Target, @bt.Target)] = []
  for l in 0..<(layers - 1) {
    for w1 in 0..<width {
      for w2 in 0..<width {
        edges.push((
          @bt.Target::new("L" + l.to_string() + "_W" + w1.to_string()),
          @bt.Target::new("L" + (l + 1).to_string() + "_W" + w2.to_string()),
        ))
      }
    }
  }
  @bt.BuildGraph::new(nodes, edges)
}

///|
/// 为图构造「全部目标已构建」的干净缓存（基线 == 当前）。
fn build_clean_cache(g : @bt.BuildGraph) -> @bt.BuildCache {
  let c = @bt.BuildCache::new()
  for n in g.nodes {
    c.observe(n.name, 1L, "h")
    c.mark_built(n.name)
  }
  c
}

///|
/// 每隔 `stride` 个节点令其当前指纹相对基线变化（制造脏目标）。
fn dirty_every(c : @bt.BuildCache, g : @bt.BuildGraph, stride : Int) -> Unit {
  let mut i = 0
  for n in g.nodes {
    if i % stride == 0 {
      c.observe(n.name, 2L, "h2")
    }
    i = i + 1
  }
}

// ---------------------------------------------------------------------------
// 冒烟 guard（correctness）：大规模图核心不变量
// ---------------------------------------------------------------------------

///|
/// Smoke: 1000 节点链的拓扑序完整且首尾正确（R11.1）。
test "smoke: topo_order on a 1000-node chain is fully ordered" {
  let g = chain_graph(1000)
  match @bt.topo_order(g) {
    Ok(order) => {
      assert_eq(order.length(), 1000)
      assert_true(order[0] == @bt.Target::new("n0"))
      assert_true(order[999] == @bt.Target::new("n999"))
    }
    Err(_) => fail("链图不应含环")
  }
}

///|
/// Smoke: 扇出图调度为 2 批（源层 + 叶子层），叶子层批宽 = width。
test "smoke: fanout graph schedules into source then leaves" {
  let width = 256
  let g = fanout_graph(width)
  let batches = @bt.schedule(g, 0)
  assert_eq(batches.length(), 2)
  assert_eq(batches[0].length(), 1)
  assert_eq(batches[1].length(), width)
}

// ---------------------------------------------------------------------------
// 回归 guard（R11.3）：拓扑层数 / 关键路径 / 重建集规模内联基线
// ---------------------------------------------------------------------------

///|
/// Guard: 分层网格调度层数 == 关键路径长度 == 层数，且每批批宽 == 宽度。
test "guard: layered-grid schedule layers match critical path" {
  let layers = 20
  let width = 16
  let g = layered_grid(layers, width)
  let batches = @bt.schedule(g, 0)
  if batches.length() != layers {
    fail(
      "BUILD-TOOL-BENCH GUARD FAIL [layers]: schedule 层数 " +
      batches.length().to_string() +
      " 偏离基线 " +
      layers.to_string() +
      "（节点 " +
      (layers * width).to_string() +
      "）。",
    )
  }
  if @bt.critical_path_length(g) != layers {
    fail(
      "BUILD-TOOL-BENCH GUARD FAIL [critical-path]: critical_path_length " +
      @bt.critical_path_length(g).to_string() +
      " 偏离基线 " +
      layers.to_string() +
      "。",
    )
  }
  for b in batches {
    if b.length() != width {
      fail(
        "BUILD-TOOL-BENCH GUARD FAIL [batch-width]: 批宽 " +
        b.length().to_string() +
        " 偏离基线 " +
        width.to_string() +
        "。",
      )
    }
  }
}

///|
/// Guard: 单源变更下最小重建集规模 == 1 + (layers-1)×width（精确下游闭包）。
test "guard: minimal rebuild set size matches downstream closure" {
  let layers = 10
  let width = 8
  let g = layered_grid(layers, width)
  let set = @bt.minimal_rebuild_set(g, [@bt.Target::new("L0_W0")])
  let expected = 1 + (layers - 1) * width
  if set.length() != expected {
    fail(
      "BUILD-TOOL-BENCH GUARD FAIL [rebuild-set]: 重建集规模 " +
      set.length().to_string() +
      " 偏离基线 " +
      expected.to_string() +
      "（节点 " +
      (layers * width).to_string() +
      "）。",
    )
  }
}

///|
/// Guard: 1000 节点链调度产出 1000 个单元素批次（拓扑链退化基线）。
test "guard: chain schedule produces one batch per node" {
  let n = 1000
  let g = chain_graph(n)
  let batches = @bt.schedule(g, 0)
  if batches.length() != n {
    fail(
      "BUILD-TOOL-BENCH GUARD FAIL [chain-layers]: 链调度批数 " +
      batches.length().to_string() +
      " 偏离基线 " +
      n.to_string() +
      "。",
    )
  }
}

// ---------------------------------------------------------------------------
// 原生基准（@bench.T）：四类工作负载（moon bench 下执行）
// ---------------------------------------------------------------------------

///|
/// 拓扑排序：800 节点分层网格（40×20，约 1.56 万边）。
test "bench: topo_order on a large layered grid" (b : @bench.T) {
  let g = layered_grid(40, 20)
  b.bench(name="bt_topo_order_800", fn() { b.keep(@bt.topo_order(g)) })
}

///|
/// 并行调度：800 节点分层网格，受限与不限并行度两种。
test "bench: schedule on a large layered grid" (b : @bench.T) {
  let g = layered_grid(40, 20)
  b.bench(name="bt_schedule_800_j8", fn() { b.keep(@bt.schedule(g, 8)) })
  b.bench(name="bt_schedule_800_unbounded", fn() { b.keep(@bt.schedule(g, 0)) })
}

///|
/// 脏检查：800 节点大缓存（每 4 个目标 1 个脏）。
test "bench: dirty_targets on a large cache" (b : @bench.T) {
  let g = layered_grid(40, 20)
  let cache = build_clean_cache(g)
  dirty_every(cache, g, 4)
  b.bench(name="bt_dirty_targets_800", fn() { b.keep(@bt.dirty_targets(g, cache)) })
}

///|
/// 最小重建集：800 节点分层网格，单源变更前向闭包。
test "bench: minimal_rebuild_set on a large grid" (b : @bench.T) {
  let g = layered_grid(40, 20)
  let src = [@bt.Target::new("L0_W0")]
  b.bench(name="bt_minimal_rebuild_set_800", fn() {
    b.keep(@bt.minimal_rebuild_set(g, src))
  })
}
