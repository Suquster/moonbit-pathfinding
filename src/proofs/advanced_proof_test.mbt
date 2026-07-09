// advanced_proof_test.mbt —— 加速算法族后置条件谓词的运行期测试。
//
// 以最小正反例验证 advanced_proof.mbt 中的谓词可编译、可被运行期调用，并在
// 正反例上行为正确。查询后置条件（ch/cch/alt/hl/jps）由一张 4 节点带权小图
// 驱动（A=0→B=1→C=2→D=3，另有 A→C 直边），代价等价护栏由构造的一致/分歧
// 结果对驱动。

///|
/// 4 节点测试图：0->1(1), 1->2(2), 2->3(1), 0->2(4)。最短 0->3 = 0-1-2-3 代价 4。
fn adv_succ(n : Int) -> Array[(Int, Int)] {
  match n {
    0 => [(1, 1), (2, 4)]
    1 => [(2, 2)]
    2 => [(3, 1)]
    _ => []
  }
}

///|
fn adv_edge_weight(u : Int, v : Int) -> Int? {
  for p in adv_succ(u) {
    if p.0 == v {
      return Some(p.1)
    }
  }
  None
}

///|
let adv_nodes : Array[Int] = [0, 1, 2, 3]

///|
fn adv_is_goal_3(n : Int) -> Bool {
  n == 3
}

// --- 查询后置条件：合法最短路应被接受 ---

///|
test "ch/cch/alt/hl_query_post accept a valid shortest path" {
  let ok : (Array[Int], Int)? = Some(([0, 1, 2, 3], 4))
  assert_true(
    ch_query_post(ok, 0, adv_is_goal_3, adv_succ, adv_edge_weight, adv_nodes),
  )
  assert_true(
    cch_query_post(ok, 0, adv_is_goal_3, adv_succ, adv_edge_weight, adv_nodes),
  )
  assert_true(
    alt_query_post(ok, 0, adv_is_goal_3, adv_succ, adv_edge_weight, adv_nodes),
  )
  assert_true(
    hub_labeling_post(
      ok, 0, adv_is_goal_3, adv_succ, adv_edge_weight, adv_nodes,
    ),
  )
}

// --- 查询后置条件：代价谎报应被拒绝 (B 分量) ---

///|
test "ch_query_post rejects a mismatched cost witness" {
  // 路径合法但声明代价 99 与真实边权和 4 不符 → B 分量判假。
  let bad : (Array[Int], Int)? = Some(([0, 1, 2, 3], 99))
  assert_false(
    ch_query_post(bad, 0, adv_is_goal_3, adv_succ, adv_edge_weight, adv_nodes),
  )
}

// --- 查询后置条件：非法边应被拒绝 (A 分量) ---

///|
test "alt_query_post rejects a path with a non-existent edge" {
  // 0->3 无直接边 → A 分量判假。
  let bad : (Array[Int], Int)? = Some(([0, 3], 1))
  assert_false(
    alt_query_post(bad, 0, adv_is_goal_3, adv_succ, adv_edge_weight, adv_nodes),
  )
}

// --- JPS 栅格查询后置条件 ---

///|
test "jps_post accepts a valid grid path" {
  let succ = fn(p : (Int, Int)) -> Array[((Int, Int), Int)] {
    match p {
      (0, 0) => [((0, 1), 1)]
      (0, 1) => [((0, 2), 1)]
      _ => []
    }
  }
  let ew = fn(a : (Int, Int), b : (Int, Int)) -> Int? {
    for q in succ(a) {
      if q.0 == b {
        return Some(q.1)
      }
    }
    None
  }
  let goal = fn(p : (Int, Int)) -> Bool { p == (0, 2) }
  let grid_nodes = [(0, 0), (0, 1), (0, 2)]
  let ok : (Array[(Int, Int)], Int)? = Some(([(0, 0), (0, 1), (0, 2)], 2))
  assert_true(jps_post(ok, (0, 0), goal, succ, ew, grid_nodes))
}

// --- 代价等价护栏：加速算法 vs 参考实现 ---

///|
test "cost_agrees_with_reference true when both reachable with equal cost" {
  // 路径可不同（并列最短），代价相同即一致。
  let fast : (Array[Int], Int)? = Some(([0, 1, 2, 3], 4))
  let reference : (Array[Int], Int)? = Some(([0, 1, 2, 3], 4))
  assert_true(cost_agrees_with_reference(fast, reference))
}

///|
test "cost_agrees_with_reference true when both unreachable" {
  let fast : (Array[Int], Int)? = None
  let reference : (Array[Int], Int)? = None
  assert_true(cost_agrees_with_reference(fast, reference))
}

///|
test "cost_agrees_with_reference false on cost divergence" {
  let fast : (Array[Int], Int)? = Some(([0, 2, 3], 5))
  let reference : (Array[Int], Int)? = Some(([0, 1, 2, 3], 4))
  assert_false(cost_agrees_with_reference(fast, reference))
}

///|
test "cost_agrees_with_reference false on reachability disagreement" {
  let fast : (Array[Int], Int)? = Some(([0, 1, 2, 3], 4))
  let reference : (Array[Int], Int)? = None
  assert_false(cost_agrees_with_reference(fast, reference))
}

// --- 批量代价等价护栏 ---

///|
test "batch_cost_agrees true for aligned equal-cost batch" {
  let fast : Array[(Array[Int], Int)?] = [Some(([0, 1], 1)), None]
  let reference : Array[(Array[Int], Int)?] = [Some(([0, 1], 1)), None]
  assert_true(batch_cost_agrees(fast, reference))
}

///|
test "batch_cost_agrees false on length mismatch" {
  let fast : Array[(Array[Int], Int)?] = [Some(([0, 1], 1))]
  let reference : Array[(Array[Int], Int)?] = [Some(([0, 1], 1)), None]
  assert_false(batch_cost_agrees(fast, reference))
}

///|
test "batch_cost_agrees false when one pair diverges" {
  let fast : Array[(Array[Int], Int)?] = [Some(([0, 1], 1)), Some(([0, 2], 9))]
  let reference : Array[(Array[Int], Int)?] = [
    Some(([0, 1], 1)),
    Some(([0, 2], 4)),
  ]
  assert_false(batch_cost_agrees(fast, reference))
}
