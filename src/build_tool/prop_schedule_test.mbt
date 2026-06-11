// prop_schedule_test.mbt —— Build_Tool 调度拓扑不变量属性测试（任务 9.3）。
//
// 本文件以属性（property）形式校验 `schedule` 的核心契约：对任意无环构建图，
// 其并行批次展平后的执行顺序必须满足「任一节点在其所有依赖之后执行」的拓扑
// 不变量（Requirement 6.7）。复用共享 PBT 包 @infra_pbt 的 Gen / Rng /
// holds_for_all 模板（默认 ≥100 次迭代）。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`。

///|
/// 随机无环构建图生成器（acyclic build graph generator）。
///
/// 无环性保证：节点按 `n0 .. n{k-1}` 线性编号，边仅由「低编号 → 高编号」生成
/// （即对每对 `i < j` 以约 50% 概率加入边 `(n_i, n_j)`）。依赖边 `(u, v)` 语义
/// 为「`u` 必须在 `v` 之前」，故所有边方向与编号单调一致，构建图必然无环——
/// 这正是 Property 14「对任意无环构建图」所约束的输入空间。
///
/// 规模刻意保持较小（1..8 个节点），以在每次迭代内充分覆盖「链 / 菱形 / 宽层 /
/// 多源多汇」等拓扑形态，同时保证三后端测试可在合理时间内完成。
fn gen_acyclic_build_graph() -> @infra_pbt.Gen[BuildGraph] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 8)
    let nodes : Array[Target] = []
    for i in 0..<n {
      nodes.push(Target::new("n" + i.to_string()))
    }
    let edges : Array[(Target, Target)] = []
    // 仅生成「低编号 → 高编号」边，确保构建图无环。
    for i in 0..<n {
      for j in (i + 1)..<n {
        if rng.next_bool() {
          edges.push((nodes[i], nodes[j]))
        }
      }
    }
    BuildGraph::new(nodes, edges)
  })
}

///|
/// 校验某并行度下 `schedule` 输出满足拓扑不变量与全覆盖。
///
/// 将批次序列展平为单一执行顺序，记录每个节点的执行序号 `pos`，随后校验：
///   1. 全覆盖——无环图的全部节点都应被调度（展平长度 == 节点数）；
///   2. 拓扑不变量——对每条依赖边 `(u, v)`，`pos[u] < pos[v]`，即任一节点严格
///      排在其所有依赖之后执行（Requirement 6.7）。
fn schedule_respects_topology(g : BuildGraph, jobs : Int) -> Bool {
  let batches = schedule(g, jobs)
  let pos : Map[Target, Int] = Map([])
  let mut idx = 0
  for batch in batches {
    for t in batch {
      pos[t] = idx
      idx += 1
    }
  }
  // 1. 无环图的所有节点都应被调度。
  if idx != g.nodes.length() {
    return false
  }
  // 2. 每条依赖边都满足「依赖先于目标」。
  for edge in g.edges {
    let (u, v) = edge
    match (pos.get(u), pos.get(v)) {
      (Some(pu), Some(pv)) => if pu >= pv { return false }
      _ => return false
    }
  }
  true
}

///|
/// Feature: moonbit-infra-suite, Property 14: 构建调度拓扑不变量
///
/// 对任意由生成器产生的无环构建图，`schedule` 的批次展平顺序应满足「任一节点
/// 在其所有依赖之后执行」的不变量。同时在「不限并行度（jobs <= 0，整层一批）」
/// 与「受限并行度（jobs = 2，宽层被切分为多批）」两种调度下校验，确保并行度
/// 约束不破坏依赖顺序。
///
/// **Validates: Requirements 6.7**
test "Feature: moonbit-infra-suite, Property 14: build schedule topological invariant" {
  let g = gen_acyclic_build_graph()
  let ok = @infra_pbt.holds_for_all(g, fn(graph) {
    // 不限并行度（整层一批）。
    schedule_respects_topology(graph, 0) &&
    // 受限并行度（宽层切分为批宽 ≤ 2 的多个批次）。
    schedule_respects_topology(graph, 2)
  })
  assert_true(ok)
}
