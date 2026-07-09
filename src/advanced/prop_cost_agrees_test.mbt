// prop_cost_agrees_test.mbt —— 用 @proofs 的加速算法代价等价护栏对 CH/ALT
// 真实实现做**接地**（grounding）差分测试。
//
// prop_frontier_diff_test.mbt 已内联比较 CH/ALT/JPS 与基准算法的代价；本文件
// 进一步把「加速算法查询代价必须与 Dijkstra 参考逐对相等」这一不变量交由
// `@proofs.cost_agrees_with_reference` / `@proofs.batch_cost_agrees` 判定，从而
// 让 advanced_proof.mbt 中新增的证明谓词获得**真实算法**驱动的运行期见证
// （证据驱动：谓词不再只是「可能为真」，而是被 CH/ALT 实测满足）。

///|
/// 复用 fd_* 生成器构造随机图，逐点对以 @proofs 护栏校验 CH == Dijkstra。
fn ca_prop_ch_agrees(spec : FdGraphSpec) -> Bool {
  let succ = fd_succ(spec)
  let nodes = fd_nodes(spec)
  let g = ch_preprocess(nodes, succ)
  let mut ok = true
  for s in nodes {
    for t in nodes {
      let fast = ch_query(g, s, t)
      let reference = @dir.dijkstra(s, succ, fn(x) { x == t })
      if !@proofs.cost_agrees_with_reference(fast, reference) {
        ok = false
      }
    }
  }
  ok
}

///|
/// 逐点对以 @proofs 护栏校验 ALT == Dijkstra。
fn ca_prop_alt_agrees(spec : FdGraphSpec) -> Bool {
  let succ = fd_succ(spec)
  let nodes = fd_nodes(spec)
  let num_landmarks = if spec.n < 2 { spec.n } else { 2 }
  let lm = alt_preprocess(nodes, succ, num_landmarks)
  let mut ok = true
  for s in nodes {
    for t in nodes {
      let fast = alt_query(lm, s, t, succ)
      let reference = @dir.dijkstra(s, succ, fn(x) { x == t })
      if !@proofs.cost_agrees_with_reference(fast, reference) {
        ok = false
      }
    }
  }
  ok
}

///|
/// 批量护栏接地：CH 批量查询与逐点 Dijkstra 参考经 `batch_cost_agrees` 校验。
fn ca_prop_ch_batch_agrees(spec : FdGraphSpec) -> Bool {
  let succ = fd_succ(spec)
  let nodes = fd_nodes(spec)
  let g = ch_preprocess(nodes, succ)
  let pairs : Array[(Int, Int)] = []
  for s in nodes {
    for t in nodes {
      pairs.push((s, t))
    }
  }
  let fast = ch_query_batch(g, pairs)
  let reference : Array[(Array[Int], Int)?] = []
  for p in pairs {
    reference.push(@dir.dijkstra(p.0, succ, fn(x) { x == p.1 }))
  }
  @proofs.batch_cost_agrees(fast, reference)
}

///|
test "Feature: proofs-grounding, CH cost_agrees_with_reference holds on random graphs" {
  let ok = @infra_pbt.holds_for_all(
    fd_graph_gen(),
    ca_prop_ch_agrees,
    iters=128,
  )
  assert_true(ok)
}

///|
test "Feature: proofs-grounding, ALT cost_agrees_with_reference holds on random graphs" {
  let ok = @infra_pbt.holds_for_all(
    fd_graph_gen(),
    ca_prop_alt_agrees,
    iters=128,
  )
  assert_true(ok)
}

///|
test "Feature: proofs-grounding, CH batch_cost_agrees holds on random graphs" {
  let ok = @infra_pbt.holds_for_all(
    fd_graph_gen(),
    ca_prop_ch_batch_agrees,
    iters=128,
  )
  assert_true(ok)
}
