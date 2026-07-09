// family15_coverage_test.mbt —— 证明谓词层覆盖率收口（INFRA 第十五批）。
// moon coverage analyze 显示 proofs 包内若干谓词的**拒绝分支**（bad-witness
// 分支）尚未被任何测试触达；证明谓词的可证伪性（falsifiability）要求每个
// return false / Err 分支都有显式反例。本文件为每条未覆盖分支补齐确定性
// 反例锚点。

// ---------------------------------------------------------------------------
// build_tool_proof：build_order_respects_deps 的拒绝分支
// ---------------------------------------------------------------------------

///|
test "build_order_respects_deps rejects out-of-range and violated deps" {
  // 端点越界 ⇒ false。
  assert_false(build_order_respects_deps([0, 1], [(0, 5)]))
  assert_false(build_order_respects_deps([0, 1], [(-1, 0)]))
  // 依赖 v 未先于 u（pos[v] >= pos[u]）⇒ false。
  assert_false(build_order_respects_deps([0, 1], [(0, 1)]))
}

// ---------------------------------------------------------------------------
// metrics_time_proof：三个非降 / 夹逼谓词的拒绝分支
// ---------------------------------------------------------------------------

///|
test "metrics predicates reject decreasing and out-of-range witnesses" {
  assert_false(non_decreasing64([2L, 1L]))
  assert_false(non_decreasing_f([2.0, 1.0]))
  assert_false(all_within64([5L], 0L, 3L))
}

// ---------------------------------------------------------------------------
// infra_family_proof：往返 / 魔数 / 判定一致谓词的拒绝分支
// ---------------------------------------------------------------------------

///|
test "infra family predicates reject mismatched witnesses" {
  // 长度不等与逐元素不等。
  assert_false(bytes_round_trip_eq([1, 2], [1]))
  assert_false(bytes_round_trip_eq([1, 2], [1, 3]))
  // 数据短于魔数与魔数不匹配。
  assert_false(has_magic_prefix([1], [1, 2]))
  assert_false(has_magic_prefix([9, 2], [1, 2]))
  // 单边 Some / None ⇒ 判定不一致。
  assert_false(spans_agree(Some((0, 1)), None))
}

// ---------------------------------------------------------------------------
// loop_invariants：单调 / 层序 / 极差谓词的拒绝与遍历分支
// ---------------------------------------------------------------------------

///|
test "loop invariant predicates cover rejection and scan branches" {
  // dijkstra_pop_monotonic 的违例分支。
  assert_false(dijkstra_pop_monotonic([3, 1]))
  // bfs_level_invariant 的 lo 更新分支（后续元素更小）与违例判定。
  assert_true(bfs_level_invariant([2, 1]))
  assert_false(bfs_level_invariant([3, 1]))
  // is_monotonic_nondecreasing 的平凡分支与扫描分支。
  assert_true(is_monotonic_nondecreasing(([] : Array[Int])))
  assert_true(is_monotonic_nondecreasing([1, 2, 3]))
  assert_false(is_monotonic_nondecreasing([2, 1]))
  // pairwise_diff_within 的平凡分支与 lo/hi 双更新分支。
  assert_true(pairwise_diff_within([], 0))
  assert_true(pairwise_diff_within([5, 3, 9], 6))
  assert_false(pairwise_diff_within([5, 3, 9], 5))
}

// ---------------------------------------------------------------------------
// flow_matching_proof：费用流 / 匹配 / 拓扑序 / 欧拉路径的拒绝分支
// ---------------------------------------------------------------------------

///|
test "min cost flow valid rejects invalid flow and mismatched arrays" {
  // 底层 max_flow_valid 失败（流超容量）⇒ false。
  assert_false(min_cost_flow_valid(2, [(0, 1)], [1], [1], [2], 0, 1, 2, 4))
  // unit_cost 长度与边数不一致 ⇒ false。
  assert_false(
    min_cost_flow_valid(2, [(0, 1)], [1], ([] : Array[Int]), [1], 0, 1, 1, 1),
  )
  // 费用不守恒 ⇒ false。
  assert_false(min_cost_flow_valid(2, [(0, 1)], [1], [3], [1], 0, 1, 1, 99))
}

///|
test "matching predicates reject illegal witnesses" {
  // 同一左端点两条图边（覆盖 edge_set 内层 Some 分支）；匹配边不在图中。
  assert_false(matching_valid([(0, 9)], [(0, 1), (0, 2)]))
  // 左端点根本无图边（edge_set.get(l) = None 分支）。
  assert_false(matching_valid([(5, 1)], [(0, 1)]))
  // 左端点重复匹配 ⇒ false。
  assert_false(matching_valid([(0, 1), (0, 2)], [(0, 1), (0, 2)]))
  // perfect_matching_weight：匹配非法 / 规模不符 / 权重数组长度不符 /
  // 权重和不符 各拒绝分支。
  assert_false(perfect_matching_weight([(5, 1)], [(0, 1)], [1], 1, 1))
  assert_false(perfect_matching_weight([(0, 1)], [(0, 1)], [1], 2, 1))
  assert_false(perfect_matching_weight([(0, 1)], [(0, 1)], [], 1, 1))
  assert_false(perfect_matching_weight([(0, 1)], [(0, 1)], [3], 1, 99))
}

///|
test "topo order post rejects duplicates missing endpoints and back edges" {
  // 序列重复节点。
  assert_false(topo_order_post([0, 0], []))
  // 边端点不在序中。
  assert_false(topo_order_post([0, 1], [(0, 7)]))
  // u 不先于 v。
  assert_false(topo_order_post([1, 0], [(0, 1)]))
}

///|
test "eulerian trail valid covers empty graph and rejection branches" {
  // 空边集：至多一个节点判真，两个节点判假。
  assert_true(eulerian_trail_valid([], []))
  assert_true(eulerian_trail_valid([0], []))
  assert_false(eulerian_trail_valid([0, 1], []))
  // 节点数与边数不匹配。
  assert_false(eulerian_trail_valid([0], [(0, 1)]))
  // 重边可用重数：同一条边出现两次（覆盖 inner Some(c)=c+1 分支），
  // 并被轨迹恰好用尽两次。
  assert_true(eulerian_trail_valid([0, 1, 0, 1], [(0, 1), (1, 0), (0, 1)]))
  // 段使用不存在的边（inner.get(v) = None 分支）。
  assert_false(eulerian_trail_valid([0, 2], [(0, 1)]))
  // 段起点无任何出边（avail.get(u) = None 分支）。
  assert_false(eulerian_trail_valid([2, 0], [(0, 1)]))
  // 同一条边被使用两次（重数耗尽 c = 0 分支）。
  assert_false(eulerian_trail_valid([0, 1, 0, 1], [(0, 1), (1, 0), (0, 2)]))
}

// ---------------------------------------------------------------------------
// spanning_connectivity_proof：MST / 分量 / SCC / 桥 / 缩点的拒绝分支
// ---------------------------------------------------------------------------

///|
test "mst post rejects cycle and disconnection" {
  // 越界端点。
  assert_false(mst_post(2, [(0, 5, 1)]))
  // 成环（两端已连通再合并）。
  assert_false(mst_post(3, [(0, 1, 1), (1, 0, 1)]))
  // 边数正确但不连通（含重边成环即无法覆盖全部节点）——构造 4 节点
  // 3 条边但 0-1 间成环：{0-1, 1-0, 2-3}，触发根不一致分支。
  assert_false(mst_post(4, [(0, 1, 1), (1, 0, 1), (2, 3, 1)]))
}

///|
test "components partition post rejects bad labels" {
  // 越界端点。
  assert_false(components_partition_post(2, [0, 0], [(0, 9)]))
  // 连通两端标签不同。
  assert_false(components_partition_post(2, [0, 1], [(0, 1)]))
}

///|
test "scc partition post rejects wrong shapes and labels" {
  assert_false(scc_partition_post(-1, [], []))
  assert_false(scc_partition_post(2, [0], []))
  assert_false(scc_partition_post(1, [0], [(0, 5)]))
  // 互达 (0↔1) 但标签不同 ⇒ false。
  assert_false(scc_partition_post(2, [0, 1], [(0, 1), (1, 0)]))
}

///|
test "edge is bridge covers src==dst reachability and parallel edges" {
  // 桥：链 0-1，删除后不可达。
  assert_true(edge_is_bridge(2, [(0, 1)], 0, 1))
  // 平行边：正反向记录各删一份后仍剩一条 (0,1) ⇒ 仍可达，非桥；
  // 覆盖 removed_backward 分支。
  assert_false(edge_is_bridge(2, [(0, 1), (1, 0), (0, 1)], 0, 1))
  // 端点相同 ⇒ false（reachable_directed src==dst 由 scc 用例覆盖）。
  assert_false(edge_is_bridge(2, [(0, 1)], 0, 0))
  // 边不存在 ⇒ false。
  assert_false(edge_is_bridge(3, [(0, 1)], 1, 2))
  // 越界端点 ⇒ false。
  assert_false(edge_is_bridge(2, [(0, 9)], 0, 1))
  // 自反标签用例：scc_partition_post 对 i==j 互达（src==dst 分支）。
  assert_true(scc_partition_post(1, [0], []))
}

///|
test "condensation is dag rejects bad inputs and self loops" {
  assert_false(condensation_is_dag(-1, []))
  assert_false(condensation_is_dag(1, [(0, 5)]))
  assert_false(condensation_is_dag(1, [(0, 0)]))
  // 双节点环 ⇒ false（Kahn 无法剥离）。
  assert_false(condensation_is_dag(2, [(0, 1), (1, 0)]))
}

// ---------------------------------------------------------------------------
// shortest_path_family_proof：yen_post 的空结果与代价降序分支
// ---------------------------------------------------------------------------

///|
test "yen post covers empty results and decreasing cost rejection" {
  let succ = fn(n : Int) -> Array[(Int, Int)] {
    if n == 0 {
      [(1, 1)]
    } else {
      []
    }
  }
  let ew = fn(u : Int, v : Int) -> Int? {
    if u == 0 && v == 1 {
      Some(1)
    } else {
      None
    }
  }
  let goal = fn(n : Int) -> Bool { n == 2 }
  // 空结果 + 目标确不可达 ⇒ true（覆盖 none-witness 分支）。
  assert_true(
    yen_post(([] : Array[(Array[Int], Int)]), 0, goal, succ, ew, [0, 1, 2]),
  )
  // 代价降序 ⇒ false（覆盖 prev_cost 比较分支）。
  let goal1 = fn(n : Int) -> Bool { n == 1 }
  let succ2 = fn(n : Int) -> Array[(Int, Int)] {
    if n == 0 {
      [(1, 1), (1, 2)]
    } else {
      []
    }
  }
  let ew2 = fn(u : Int, v : Int) -> Int? {
    if u == 0 && v == 1 {
      Some(1)
    } else {
      None
    }
  }
  assert_false(
    yen_post([([0, 1], 1), ([0, 1], 0)], 0, goal1, succ2, ew2, [0, 1]),
  )
}

// ---------------------------------------------------------------------------
// unweighted_family_proof：可达集合谓词的拒绝分支
// ---------------------------------------------------------------------------

///|
test "bfs all post rejects unsound and incomplete witnesses" {
  let succ = fn(n : Int) -> Array[Int] {
    if n == 0 {
      [1]
    } else {
      ([] : Array[Int])
    }
  }
  // 声称可达但实际不可达（含节点 2）⇒ false。
  assert_false(bfs_all_post([0, 1, 2], 0, succ, [0, 1, 2]))
  // 实际可达（节点 1）却未包含 ⇒ false。
  assert_false(bfs_all_post([0], 0, succ, [0, 1]))
}

// ---------------------------------------------------------------------------
// resilience_diff_proof：补丁往返谓词的解码失败分支
// ---------------------------------------------------------------------------

///|
test "patch round trip eq rejects decode failure" {
  let broken = fn(_a : Int, _b : Int) -> Int? { None }
  assert_false(patch_round_trip_eq(1, 2, broken))
}

// ---------------------------------------------------------------------------
// proof_report：from_json 错误分支与 JSON 解析边缘分支
// ---------------------------------------------------------------------------

///|
test "proof report from_json rejects malformed documents" {
  // 顶层非对象 / 非法 JSON。
  assert_true(ProofReport::from_json("[]") is Err(_))
  assert_true(ProofReport::from_json("not json") is Err(_))
  assert_true(parse_proof_report("not json") is None)
  // backends 不是数组。
  assert_true(
    ProofReport::from_json(
      "{\"moon_version\":\"s\",\"generated_at\":\"t\",\"backends\":1,\"entries\":[]}",
    )
    is Err(_),
  )
  // 缺少 entries 字段 / entries 不是数组。
  assert_true(
    ProofReport::from_json(
      "{\"moon_version\":\"s\",\"generated_at\":\"t\",\"backends\":[]}",
    )
    is Err(_),
  )
  assert_true(
    ProofReport::from_json(
      "{\"moon_version\":\"s\",\"generated_at\":\"t\",\"backends\":[],\"entries\":1}",
    )
    is Err(_),
  )
  // 缺少 moon_version（字符串字段缺失）与 moon_version 非字符串。
  assert_true(
    ProofReport::from_json(
      "{\"generated_at\":\"t\",\"backends\":[],\"entries\":[]}",
    )
    is Err(_),
  )
  assert_true(
    ProofReport::from_json(
      "{\"moon_version\":1,\"generated_at\":\"t\",\"backends\":[],\"entries\":[]}",
    )
    is Err(_),
  )
  // entry 不是对象 / entry 缺 passed / passed 非布尔。
  let head = "{\"moon_version\":\"s\",\"generated_at\":\"t\",\"backends\":[],\"entries\":["
  assert_true(ProofReport::from_json(head + "1]}") is Err(_))
  assert_true(
    ProofReport::from_json(
      head + "{\"algorithm\":\"p\",\"property\":\"k\",\"evidence\":\"d\"}]}",
    )
    is Err(_),
  )
  assert_true(
    ProofReport::from_json(
      head +
      "{\"algorithm\":\"p\",\"property\":\"k\",\"passed\":1,\"evidence\":\"d\"}]}",
    )
    is Err(_),
  )
  // entry 内字符串字段缺失 / 非字符串。
  assert_true(
    ProofReport::from_json(
      head + "{\"property\":\"k\",\"passed\":true,\"evidence\":\"d\"}]}",
    )
    is Err(_),
  )
  assert_true(
    ProofReport::from_json(
      head +
      "{\"algorithm\":1,\"property\":\"k\",\"passed\":true,\"evidence\":\"d\"}]}",
    )
    is Err(_),
  )
}

///|
test "proof report json parser covers escapes and edge branches" {
  // 合法往返：含 \uXXXX（大写十六进制）、各转义字符的字符串经
  // to_json → from_json 往返。
  let r = ProofReport::{
    moon_version: "s\"\\/\n\t\r",
    generated_at: "2026-07-09T00:00:00Z",
    backends: ["native"],
    entries: [
      ProofEntry::{
        algorithm: "p",
        property: "k",
        passed: true,
        evidence: "детали 详情",
      },
    ],
  }
  match ProofReport::from_json(r.to_json()) {
    Ok(back) => {
      assert_true(back.moon_version == r.moon_version)
      assert_true(back.entries[0].evidence == r.entries[0].evidence)
    }
    Err(_) => assert_true(false)
  }
  // 非法转义（\x）与非法 \u 序列 ⇒ 解析失败。
  assert_true(
    ProofReport::from_json(
      "{\"moon_version\":\"a\\x\",\"generated_at\":\"t\",\"backends\":[],\"entries\":[]}",
    )
    is Err(_),
  )
  assert_true(
    ProofReport::from_json(
      "{\"moon_version\":\"a\\uZZZZ\",\"generated_at\":\"t\",\"backends\":[],\"entries\":[]}",
    )
    is Err(_),
  )
  // 大写十六进制 \u 转义可解析。
  assert_true(
    ProofReport::from_json(
      "{\"moon_version\":\"a\\u00E9\\u00AB\",\"generated_at\":\"t\",\"backends\":[],\"entries\":[]}",
    )
    is Ok(_),
  )
}
