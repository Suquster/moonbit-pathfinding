// prop_cycle_idem_test.mbt —— 环检测错误条件与增量幂等（空操作）属性测试（task 9.4）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 13 与 Property 15，复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` /
// `holds_for_all` 模板（每条属性 ≥100 次迭代，由 `holds_for_all` 默认
// `iters=100` 保证）。
//
// 单元层面的具体环（a↔b、自环）与「输入未变 → 零重建」示例已由
// build_tool_test.mbt 承载；本文件聚焦「对任意含环图 / 任意未变输入恒成立」
// 的不变量。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。

// ---------------------------------------------------------------------------
// 生成器（generators）
// ---------------------------------------------------------------------------

///|
/// 含环构建图生成器（cyclic build graph generator）。
///
/// 必定含环：随机在「多节点环」与「自环」两种基底构造间二选一，再叠加若干
/// 随机额外边（不会消除既有环）。
///   * 多节点环：取前 `c`（2 ≤ c ≤ n）个节点构成 n0→n1→…→n_{c-1}→n0；
///   * 自环：随机某节点依赖自身 (u, u)。
/// 节点名 `n0..n{n-1}` 唯一，规避重名导致的图退化。
fn gen_cyclic_graph() -> @infra_pbt.Gen[BuildGraph] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 6)
    let nodes : Array[Target] = []
    for i in 0..<n {
      nodes.push(Target::new("n\{i}"))
    }
    let edges : Array[(Target, Target)] = []
    if rng.next_bool() {
      // 多节点环：前 c 个节点首尾相接。
      let c = rng.next_range(2, n)
      for i in 0..<c {
        edges.push((nodes[i], nodes[(i + 1) % c]))
      }
    } else {
      // 自环：随机一个节点依赖自身。
      let idx = rng.next_below(n)
      edges.push((nodes[idx], nodes[idx]))
    }
    // 叠加若干随机额外边（仅可能新增环，绝不消除既有环）。
    let extra = rng.next_range(0, n)
    let mut k = 0
    while k < extra {
      let a = rng.next_below(n)
      let b = rng.next_below(n)
      edges.push((nodes[a], nodes[b]))
      k += 1
    }
    BuildGraph::new(nodes, edges)
  })
}

///|
/// 「输入未变」场景生成器（unchanged-input fingerprint generator）。
///
/// 产出一组目标的输入指纹 `(目标名, mtime, 内容哈希)`，目标名 `t0..t{n-1}`
/// 唯一。用于模拟「一次成功构建后输入完全未变」：先 observe + mark_built
/// 固化基线，再在不改动任何指纹的前提下复查脏状态。
fn gen_unchanged_fingerprints() -> @infra_pbt.Gen[
  Array[(String, Int64, String)],
] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 6)
    let out : Array[(String, Int64, String)] = []
    for i in 0..<n {
      let name = "t\{i}"
      let mtime = rng.next_range(1, 1000000).to_int64()
      let hash = "h\{rng.next_range(0, 9999)}"
      out.push((name, mtime, hash))
    }
    out
  })
}

// ---------------------------------------------------------------------------
// 辅助谓词
// ---------------------------------------------------------------------------

///|
/// 判定 `seq` 中每个目标都属于图节点集合 `nodes`。
fn all_in_nodes(seq : Array[Target], nodes : Array[Target]) -> Bool {
  for t in seq {
    let mut found = false
    for n in nodes {
      if n == t {
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Property 13：构建图环检测错误条件
// ---------------------------------------------------------------------------

///|
/// 含环图的环检测错误契约：`detect_cycle` 必须报告非空且全部隶属于图节点的
/// 环节点序列；`topo_order` 必须以 `Cycle`（Err）拒绝并给出非空环节点序列。
fn cycle_reported(g : BuildGraph) -> Bool {
  // detect_cycle 报告构成环的节点序列（非空且均为图中节点）。
  let detected = match detect_cycle(g) {
    Some(seq) => seq.length() >= 1 && all_in_nodes(seq, g.nodes)
    None => false
  }
  // topo_order 对含环图返回 Cycle（拒绝执行构建），且环节点序列非空。
  let rejected = match topo_order(g) {
    Ok(_) => false
    Err(cyc) => cyc.nodes.length() >= 1
  }
  detected && rejected
}

///|
/// Feature: moonbit-infra-suite, Property 13: 构建图环检测错误条件
///
/// 对任意含环的构建图，`detect_cycle` 报告构成环的节点序列（非空、均为图中
/// 节点），且 `topo_order` 返回 `Cycle`（拒绝执行构建）。
///
/// **Validates: Requirements 6.2, 6.6**
test "Feature: moonbit-infra-suite, Property 13: cyclic graph is detected and rejected" {
  let ok = @infra_pbt.holds_for_all(gen_cyclic_graph(), cycle_reported)
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 15：增量构建幂等（空操作）
// ---------------------------------------------------------------------------

///|
/// 增量空操作契约：模拟一次成功构建（observe + mark_built 固化基线）后，在
/// 输入完全未变的前提下，所有目标 `is_dirty` 均为 `false`（零重建）。
fn no_op_is_clean(fps : Array[(String, Int64, String)]) -> Bool {
  let cache = BuildCache::new()
  // 一次成功构建：观测当前指纹并固化为基线（基线 == 当前）。
  for fp in fps {
    let (name, mtime, hash) = fp
    cache.observe(name, mtime, hash)
    cache.mark_built(name)
  }
  // 输入未变：再次构建对所有目标零重建。
  for fp in fps {
    let (name, _, _) = fp
    if is_dirty(Target::new(name), cache) {
      return false
    }
  }
  true
}

///|
/// Feature: moonbit-infra-suite, Property 15: 增量构建幂等（空操作）
///
/// 对任意一组目标输入指纹，一次成功构建后若输入未变，则再次构建零重建：
/// 所有目标 `is_dirty` 为 `false`。
///
/// **Validates: Requirements 6.2, 6.6**
test "Feature: moonbit-infra-suite, Property 15: rebuild with unchanged input is a no-op" {
  let ok = @infra_pbt.holds_for_all(
    gen_unchanged_fingerprints(),
    no_op_is_clean,
  )
  assert_true(ok)
}
