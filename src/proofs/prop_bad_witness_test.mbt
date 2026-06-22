// Feature: championship-v1-upgrade, Property 14: 坏见证被拒绝且不改输入
//
// prop_bad_witness_test.mbt —— bad-witness 拒绝属性测试（任务 10.5）。
//
//   Property 14: 坏见证被拒绝且不改输入
//   ------------------------------------------------------------------
//   *对任意* 随机带权有向图与*故意构造的坏见证*（违反最短路后置条件之一
//   的结果），最短路聚合后置谓词 `shortest_path_post` 必判 false，且**不
//   修改、不丢弃**所提供的输入（nodes 数组、path 数组等内容逐元素不变）。
//
//   坏见证三类（分别违反 predicates.mbt 中的 A / B / C 分量）：
//     (A) path-validity 违例：相邻对无对应边（路径断裂）；
//     (B) cost-consistency 违例：返回代价 != 沿路径边权之和；
//     (C) none-witness 违例：目标确可达却返回 None。
//
//   「不修改输入」性质源于本模块所有谓词均为**纯函数**：谓词只读取
//   result / path / nodes 并返回 Bool，从不写回。本测试在调用前后对输入做
//   内容快照并逐元素比对，运行时验证该纯性（对应 Requirement 9.6）。
//
// **Validates: Requirements 9.6**

///|
/// 由确定性随机源 `rng` 构造节点为 `0..<k` 的随机**带权**有向图，
/// 以邻接表 `Map[Int, Array[(Int, Int)]]`（目标节点, 边权）表示后继闭包。
///
/// 每个节点随机生成 `0..k` 条出边，目标取自 `[0, k)`，边权取自 `[1, 10)`；
/// 对重复目标做去重以保持邻接表整洁（不影响后继语义）。
fn bw_build_graph(rng : @infra_pbt.Rng, k : Int) -> Map[Int, Array[(Int, Int)]] {
  let adj : Map[Int, Array[(Int, Int)]] = Map([])
  for u in 0..<k {
    let outs : Array[(Int, Int)] = []
    let deg = rng.next_range(0, k)
    for _e in 0..<deg {
      let v = rng.next_below(k)
      let w = rng.next_range(1, 10)
      let mut dup = false
      for p in outs {
        if p.0 == v {
          dup = true
          break
        }
      }
      if !dup {
        outs.push((v, w))
      }
    }
    adj[u] = outs
  }
  adj
}

///|
/// 对 `Array[Int]` 做内容快照（复制到新数组），用于「不修改输入」的前后比对。
fn bw_snapshot(xs : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  for x in xs {
    out.push(x)
  }
  out
}

///|
/// 单次场景：构造随机带权图与三类坏见证，校验：
///   (1) 聚合谓词 `shortest_path_post` 对每个坏见证判 false；
///   (2) 调用前后输入（nodes / path）内容逐元素不变（谓词为纯函数）。
/// 返回 `true` 表示本次随机实例下所有断言成立。
fn bw_scenario(rng : @infra_pbt.Rng) -> Bool {
  // 节点数 k ∈ [2, 8]（k>=2 便于构造「非 start 后继」的断裂目标）。
  let k = rng.next_range(2, 8)
  let adj = bw_build_graph(rng, k)
  let succ = fn(n : Int) -> Array[(Int, Int)] {
    match adj.get(n) {
      Some(xs) => xs
      None => []
    }
  }
  let edge_weight = fn(u : Int, v : Int) -> Int? {
    for p in succ(u) {
      if p.0 == v {
        return Some(p.1)
      }
    }
    None
  }
  let nodes : Array[Int] = []
  for i in 0..<k {
    nodes.push(i)
  }
  let start = rng.next_below(k)

  // —— 真实游走路径（沿真实边）：用于隔离「仅违反 B」与「违反 C」的见证 ——
  let walk : Array[Int] = [start]
  let cap = rng.next_range(0, k + 2)
  let mut cur = start
  for _step in 0..<cap {
    let nbrs = succ(cur)
    if nbrs.length() == 0 {
      break
    }
    let nxt = nbrs[rng.next_below(nbrs.length())].0
    walk.push(nxt)
    cur = nxt
  }
  let walk_last = walk[walk.length() - 1]
  // goal 命中 walk 末节点（walk_last 由 start 可达），隔离 A 的 goal 分量与 C。
  let goal = fn(n : Int) -> Bool { n == walk_last }

  // ============================================================
  // 坏见证 (B)：代价与路径实际和不符（仅违反 cost-consistency）
  // ============================================================
  // walk 为真实路径（A 成立），末节点满足 goal（A 的 goal 分量成立），
  // 仅把代价改为错误值（实际和 + 1）→ 聚合谓词必判 false。
  let real_cost = match path_cost(walk, edge_weight) {
    Some(c) => c
    None => 0 // walk 为真实路径，理论上恒为 Some
  }
  let witness_b : (Array[Int], Int)? = Some((walk, real_cost + 1))
  let nodes_before_b = bw_snapshot(nodes)
  let walk_before_b = bw_snapshot(walk)
  if shortest_path_post(witness_b, start, goal, succ, edge_weight, nodes) {
    return false // 坏见证未被拒绝
  }
  if !seq_eq(nodes, nodes_before_b) {
    return false // nodes 被修改
  }
  if !seq_eq(walk, walk_before_b) {
    return false // path 被修改
  }

  // ============================================================
  // 坏见证 (C)：目标可达却返回 None（仅违反 none-witness）
  // ============================================================
  // walk_last 由 start 可达（goal 命中它），却给出 None → 聚合谓词必判 false。
  let witness_c : (Array[Int], Int)? = None
  let nodes_before_c = bw_snapshot(nodes)
  if shortest_path_post(witness_c, start, goal, succ, edge_weight, nodes) {
    return false // 坏见证未被拒绝
  }
  if !seq_eq(nodes, nodes_before_c) {
    return false // nodes 被修改
  }

  // ============================================================
  // 坏见证 (A)：路径断裂——相邻对无对应边（违反 path-validity）
  // ============================================================
  // 找一个不是 start 后继的节点 v，构造 [start, v] → 相邻对无边 → 必判假。
  // 若 start 的后继已覆盖全部节点，则本类无法构造，跳过（B/C 已覆盖坏见证）。
  let succ0 = succ(start)
  let mut v = -1
  for cand in 0..<k {
    let mut is_succ = false
    for p in succ0 {
      if p.0 == cand {
        is_succ = true
        break
      }
    }
    if !is_succ {
      v = cand
      break
    }
  }
  if v >= 0 {
    let broken : Array[Int] = [start, v]
    let goal_a = fn(n : Int) -> Bool { n == v }
    let witness_a : (Array[Int], Int)? = Some((broken, 1))
    let nodes_before_a = bw_snapshot(nodes)
    let broken_before_a = bw_snapshot(broken)
    if shortest_path_post(witness_a, start, goal_a, succ, edge_weight, nodes) {
      return false // 坏见证未被拒绝
    }
    if !seq_eq(nodes, nodes_before_a) {
      return false // nodes 被修改
    }
    if !seq_eq(broken, broken_before_a) {
      return false // path 被修改
    }
  }
  true
}

///|
/// Feature: championship-v1-upgrade, Property 14: 坏见证被拒绝且不改输入
/// （holds_for_all 模板，iters ≥ 100）
///
/// **Validates: Requirements 9.6**
test "Feature: championship-v1-upgrade, Property 14: bad witnesses are rejected and inputs are unchanged" {
  let gen = @infra_pbt.Gen::new(fn(rng) { bw_scenario(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }, iters=100))
}
