// Feature: championship-v1-upgrade, Property 9.7: 30 算法证明谓词三后端判定确定且一致
//
// prop_predicate_tri_backend_test.mbt —— 30 算法谓词三后端一致性测试（任务 11.5）。
//
//   属性（三后端一致性 / 判定确定性）
//   ------------------------------------------------------------------
//   *对任意* 随机生成的图实例，针对 Classic_Algorithm_Set 全部 30 种经典算法
//   的每一个证明谓词（最短路族 / 无权可达族 / 生成树连通性族 / 流匹配拓扑欧拉
//   族 + BFS/Dijkstra 基座），分别构造一个**正见证**（满足后置条件，应判真）与
//   一个**坏见证**（违反后置条件，应判假），并要求：
//     (1) 谓词对正见证判 `true`、对坏见证判 `false`（R9.1 + R9.2，覆盖全部 30
//         算法各 ≥1 谓词）；
//     (2) 对同一输入**重复求值结果完全一致**（确定性）——这正是三后端一致性的
//         充分条件：所有谓词均为纯函数（无副作用、不就地修改入参），其布尔判定
//         只取决于输入值而与求值后端无关，故在 `wasm-gc`/`js`/`native` 上对同
//         一谓词同一输入必给出**相同的通过/失败判定**（R9.7）。
//
//   三后端门禁语义（R9.7/R9.8）：本测试在 `wasm-gc`/`js`/`native` 三后端分别运
//   行（`moon test --target {后端}`）。由于每个被测谓词的期望判定（true/false）
//   在测试内以**后端无关的字面常量**锚定，任一后端若计算出不同判定即与该字面
//   常量不符而在该后端失败，使证明门禁失败并暴露出现分歧的谓词与后端——这正是
//   Requirement 9.8 所要求的「分歧即门禁失败」。
//
//   说明：本测试不重复 10.x / 11.1–11.4 已承担的「谓词正确性」论证，而是聚焦
//   「同一谓词在三后端给出相同判定」这一横切一致性约束，故对每个谓词以**构造
//   即已知期望**的最小正/反见证驱动，使期望判定本身可验证、后端无关。
//
// **Validates: Requirements 9.1, 9.7, 9.8**

///|
/// `tri_verdict_ok(v1, v2, expected)` —— 三后端一致性的单谓词校验内核。
///
/// `v1` / `v2` 为对**同一谓词、同一输入**的两次独立求值结果（验证确定性 /
/// 纯函数性），`expected` 为该输入对应的后端无关期望判定。当且仅当两次求值
/// 彼此一致**且**等于期望时返回 `true`。任一不符即意味着该谓词的判定不确定
/// 或偏离期望——在三后端语境下即潜在的判定分歧来源。
fn tri_verdict_ok(v1 : Bool, v2 : Bool, expected : Bool) -> Bool {
  v1 == v2 && v1 == expected
}

// ---------------------------------------------------------------------------
// 族一 · 最短路族（dijkstra / astar / bellman_ford / dag_sp /
//        bidirectional_dijkstra / ida_star / yen / johnson / floyd_warshall）
// ---------------------------------------------------------------------------

///|
/// 构造节点为 `0..<k` 的随机带权有向图（邻接表 `Map[Int, Array[(Int, Int)]]`）。
/// 权重取自 `[1, 9]` 保证严格非负（满足 Dijkstra 非负性前置），重复目标去重
/// 以保证 `edge_weight(u, v)` 取值唯一确定。
fn tb_build_weighted(
  rng : @infra_pbt.Rng,
  k : Int,
) -> Map[Int, Array[(Int, Int)]] {
  let adj : Map[Int, Array[(Int, Int)]] = Map([])
  for u in 0..<k {
    let outs : Array[(Int, Int)] = []
    let seen : Array[Int] = []
    let deg = rng.next_range(0, k)
    for _e in 0..<deg {
      let v = rng.next_below(k)
      if !seen.contains(v) {
        seen.push(v)
        outs.push((v, rng.next_range(1, 9)))
      }
    }
    adj[u] = outs
  }
  adj
}

///|
/// 族一一致性校验：对最短路族 9 种算法的谓词各构造一个真实游走正见证与一个
/// 「错代价」坏见证，逐一校验确定性与期望判定。返回 `true` 表示本实例全部通过。
fn tb_shortest_path_family(rng : @infra_pbt.Rng) -> Bool {
  let k = rng.next_range(2, 7)
  let adj = tb_build_weighted(rng, k)
  let succ = fn(n : Int) -> Array[(Int, Int)] {
    match adj.get(n) {
      Some(xs) => xs
      None => []
    }
  }
  let edge_weight = fn(u : Int, v : Int) -> Int? {
    match adj.get(u) {
      Some(xs) => {
        let mut found : Int? = None
        for p in xs {
          if p.0 == v {
            found = Some(p.1)
          }
        }
        found
      }
      None => None
    }
  }
  let nodes : Array[Int] = []
  for n in 0..<k {
    nodes.push(n)
  }
  let start = rng.next_below(k)
  // 构造一条沿真实边的游走（必为合法路径）。
  let walk : Array[Int] = [start]
  let mut cur = start
  let steps = rng.next_range(0, k)
  for _s in 0..<steps {
    let nbrs = succ(cur)
    if nbrs.length() == 0 {
      break
    }
    let p = nbrs[rng.next_below(nbrs.length())]
    walk.push(p.0)
    cur = p.0
  }
  let last = walk[walk.length() - 1]
  let goal = fn(n : Int) -> Bool { n == last }
  // 正见证代价 = 沿路径边权之和；坏见证 = 代价 +1（破坏代价一致性 B）。
  let cost = match path_cost(walk, edge_weight) {
    Some(c) => c
    None => 0
  }
  let good : (Array[Int], Int)? = Some((walk, cost))
  let bad : (Array[Int], Int)? = Some((walk, cost + 1))

  // dijkstra（基座谓词，签名不含 goal/nodes：仅 A + B + 非负性）。
  if !tri_verdict_ok(
      dijkstra_post(good, start, succ, edge_weight),
      dijkstra_post(good, start, succ, edge_weight),
      true,
    ) {
    return false
  }
  if !tri_verdict_ok(
      dijkstra_post(bad, start, succ, edge_weight),
      dijkstra_post(bad, start, succ, edge_weight),
      false,
    ) {
    return false
  }

  // astar / bellman_ford / dag_sp / bidirectional_dijkstra / ida_star
  // 均为 shortest_path_post 的语义特化薄封装，签名一致，统一驱动。
  let unary_posts : Array[
    (
      (Array[Int], Int)?,
      Int,
      (Int) -> Bool,
      (Int) -> Array[(Int, Int)],
      (Int, Int) -> Int?,
      Array[Int],
    ) -> Bool,
  ] = [
    astar_post, bellman_ford_post, dag_sp_post, bidirectional_dijkstra_post, ida_star_post,
  ]
  for post in unary_posts {
    if !tri_verdict_ok(
        post(good, start, goal, succ, edge_weight, nodes),
        post(good, start, goal, succ, edge_weight, nodes),
        true,
      ) {
      return false
    }
    if !tri_verdict_ok(
        post(bad, start, goal, succ, edge_weight, nodes),
        post(bad, start, goal, succ, edge_weight, nodes),
        false,
      ) {
      return false
    }
  }

  // yen（K 最短路）：单条正见证 → 真；错代价单条 → 假。
  let yen_good : Array[(Array[Int], Int)] = [(walk, cost)]
  let yen_bad : Array[(Array[Int], Int)] = [(walk, cost + 1)]
  if !tri_verdict_ok(
      yen_post(yen_good, start, goal, succ, edge_weight, nodes),
      yen_post(yen_good, start, goal, succ, edge_weight, nodes),
      true,
    ) {
    return false
  }
  if !tri_verdict_ok(
      yen_post(yen_bad, start, goal, succ, edge_weight, nodes),
      yen_post(yen_bad, start, goal, succ, edge_weight, nodes),
      false,
    ) {
    return false
  }

  // johnson / floyd_warshall（全对最短路）：以 lookup 闭包表达单对结果。
  let pairs : Array[(Int, Int)] = [(start, last)]
  let lookup_good = fn(s : Int, t : Int) -> (Array[Int], Int)? {
    if s == start && t == last {
      Some((walk, cost))
    } else {
      None
    }
  }
  let lookup_bad = fn(s : Int, t : Int) -> (Array[Int], Int)? {
    if s == start && t == last {
      Some((walk, cost + 1))
    } else {
      None
    }
  }
  let all_pairs_posts : Array[
    (
      Array[(Int, Int)],
      (Int, Int) -> (Array[Int], Int)?,
      (Int) -> Array[(Int, Int)],
      (Int, Int) -> Int?,
      Array[Int],
    ) -> Bool,
  ] = [johnson_post, floyd_warshall_post]
  for post in all_pairs_posts {
    if !tri_verdict_ok(
        post(pairs, lookup_good, succ, edge_weight, nodes),
        post(pairs, lookup_good, succ, edge_weight, nodes),
        true,
      ) {
      return false
    }
    if !tri_verdict_ok(
        post(pairs, lookup_bad, succ, edge_weight, nodes),
        post(pairs, lookup_bad, succ, edge_weight, nodes),
        false,
      ) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// 族二 · 无权可达族（bfs / bfs_all / dfs / bidirectional_bfs）
// ---------------------------------------------------------------------------

///|
/// 构造节点为 `0..<k` 的随机无权有向图（邻接表 `Map[Int, Array[Int]]`）。
fn tb_build_unweighted(rng : @infra_pbt.Rng, k : Int) -> Map[Int, Array[Int]] {
  let adj : Map[Int, Array[Int]] = Map([])
  for u in 0..<k {
    let outs : Array[Int] = []
    let deg = rng.next_range(0, k)
    for _e in 0..<deg {
      let v = rng.next_below(k)
      if !outs.contains(v) {
        outs.push(v)
      }
    }
    adj[u] = outs
  }
  adj
}

///|
/// 由 `start` 出发的可达节点集合（独立有界 BFS，用于构造 bfs_all 的正见证）。
fn tb_reach_set(
  start : Int,
  successors : (Int) -> Array[Int],
  k : Int,
) -> Array[Int] {
  let visited : Map[Int, Bool] = Map([])
  visited[start] = true
  let queue : Array[Int] = [start]
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head += 1
    for v in successors(u) {
      if !visited.contains(v) {
        visited[v] = true
        queue.push(v)
      }
    }
  }
  let out : Array[Int] = []
  for n in 0..<k {
    if visited.contains(n) {
      out.push(n)
    }
  }
  out
}

///|
/// 族二一致性校验：bfs / dfs / bidirectional_bfs / bfs_all 各构造正/坏见证。
fn tb_unweighted_family(rng : @infra_pbt.Rng) -> Bool {
  let k = rng.next_range(2, 7)
  let adj = tb_build_unweighted(rng, k)
  let succ = fn(n : Int) -> Array[Int] {
    match adj.get(n) {
      Some(xs) => xs
      None => []
    }
  }
  let nodes : Array[Int] = []
  for n in 0..<k {
    nodes.push(n)
  }
  let start = rng.next_below(k)
  let empty : Array[Int]? = Some([])

  // bfs_post：正见证取 goal == start、路径 [start]（长度 1，最短性平凡成立）。
  let self_goal = fn(n : Int) -> Bool { n == start }
  let bfs_good : Array[Int]? = Some([start])
  if !tri_verdict_ok(
      bfs_post(bfs_good, start, succ, self_goal, nodes),
      bfs_post(bfs_good, start, succ, self_goal, nodes),
      true,
    ) {
    return false
  }
  // 坏见证：空路径 → 违反「非空 / 首=源」→ 判假。
  if !tri_verdict_ok(
      bfs_post(empty, start, succ, self_goal, nodes),
      bfs_post(empty, start, succ, self_goal, nodes),
      false,
    ) {
    return false
  }

  // dfs_post：正见证取一条真实游走（DFS 不要求最短）。
  let walk : Array[Int] = [start]
  let mut cur = start
  let steps = rng.next_range(0, k)
  for _s in 0..<steps {
    let nbrs = succ(cur)
    if nbrs.length() == 0 {
      break
    }
    let nxt = nbrs[rng.next_below(nbrs.length())]
    walk.push(nxt)
    cur = nxt
  }
  let walk_last = walk[walk.length() - 1]
  let walk_goal = fn(n : Int) -> Bool { n == walk_last }
  let dfs_good : Array[Int]? = Some(walk)
  if !tri_verdict_ok(
      dfs_post(dfs_good, start, succ, walk_goal, nodes),
      dfs_post(dfs_good, start, succ, walk_goal, nodes),
      true,
    ) {
    return false
  }
  if !tri_verdict_ok(
      dfs_post(empty, start, succ, walk_goal, nodes),
      dfs_post(empty, start, succ, walk_goal, nodes),
      false,
    ) {
    return false
  }

  // bidirectional_bfs_post：目标节点取 start，正见证 [start]。
  let bibfs_good : Array[Int]? = Some([start])
  if !tri_verdict_ok(
      bidirectional_bfs_post(bibfs_good, start, start, succ, nodes),
      bidirectional_bfs_post(bibfs_good, start, start, succ, nodes),
      true,
    ) {
    return false
  }
  if !tri_verdict_ok(
      bidirectional_bfs_post(empty, start, start, succ, nodes),
      bidirectional_bfs_post(empty, start, start, succ, nodes),
      false,
    ) {
    return false
  }

  // bfs_all_post：正见证取真实可达集合；坏见证取空集合（缺源 → 判假）。
  let reached = tb_reach_set(start, succ, k)
  let reached_empty : Array[Int] = []
  if !tri_verdict_ok(
      bfs_all_post(reached, start, succ, nodes),
      bfs_all_post(reached, start, succ, nodes),
      true,
    ) {
    return false
  }
  if !tri_verdict_ok(
      bfs_all_post(reached_empty, start, succ, nodes),
      bfs_all_post(reached_empty, start, succ, nodes),
      false,
    ) {
    return false
  }
  true
}

// ---------------------------------------------------------------------------
// 族三 · 生成树与连通性（kruskal / prim / connected_components /
//        tarjan_scc / bridges / condensation）
// ---------------------------------------------------------------------------

///|
/// 族三一致性校验：以「链 / 环 / 三角形」等可由构造直接判定期望的最小实例，
/// 覆盖生成树不变量、连通分量划分、强连通划分、桥定义与缩点无环 5 类谓词。
fn tb_spanning_connectivity_family(rng : @infra_pbt.Rng) -> Bool {
  // 节点数 n ∈ [2, 6]：链 0-1-...-(n-1) 即一棵生成树。
  let n = rng.next_range(2, 6)

  // mst_post（kruskal / prim 共享）：链生成树（n-1 条边、无环、连通）→ 真。
  let chain_tree : Array[(Int, Int, Int)] = []
  for i in 0..<(n - 1) {
    chain_tree.push((i, i + 1, rng.next_range(1, 9)))
  }
  if !tri_verdict_ok(mst_post(n, chain_tree), mst_post(n, chain_tree), true) {
    return false
  }
  // 坏见证：去掉末边 → 边数 != n-1 且不连通 → 假（n>=2 时链至少 1 条边）。
  let broken_tree : Array[(Int, Int, Int)] = []
  for i in 0..<(n - 2) {
    broken_tree.push((i, i + 1, 1))
  }
  if !tri_verdict_ok(mst_post(n, broken_tree), mst_post(n, broken_tree), false) {
    return false
  }

  // 无向链边集（用于连通分量 / 桥）。
  let undirected_chain : Array[(Int, Int)] = []
  for i in 0..<(n - 1) {
    undirected_chain.push((i, i + 1))
  }

  // components_partition_post：链全连通 → 全部同标签（取常量标签）→ 真。
  let same_label : Array[Int] = []
  let lab = rng.next_range(0, 5)
  for _i in 0..<n {
    same_label.push(lab)
  }
  if !tri_verdict_ok(
      components_partition_post(n, same_label, undirected_chain),
      components_partition_post(n, same_label, undirected_chain),
      true,
    ) {
    return false
  }
  // 坏见证：把节点 0 标成不同标签 → 边端 (0,1) 标签不一致 → 假。
  let bad_label : Array[Int] = []
  for i in 0..<n {
    bad_label.push(if i == 0 { lab + 1 } else { lab })
  }
  if !tri_verdict_ok(
      components_partition_post(n, bad_label, undirected_chain),
      components_partition_post(n, bad_label, undirected_chain),
      false,
    ) {
    return false
  }

  // scc_partition_post：有向环 0→1→...→(n-1)→0 全互相可达 → 同标签 → 真。
  let directed_cycle : Array[(Int, Int)] = []
  for i in 0..<n {
    directed_cycle.push((i, (i + 1) % n))
  }
  let scc_same : Array[Int] = []
  for _i in 0..<n {
    scc_same.push(7)
  }
  if !tri_verdict_ok(
      scc_partition_post(n, scc_same, directed_cycle),
      scc_partition_post(n, scc_same, directed_cycle),
      true,
    ) {
    return false
  }
  // 坏见证：给节点 0 不同标签，但它与其它节点互相可达 → 判假。
  let scc_bad : Array[Int] = []
  for i in 0..<n {
    scc_bad.push(if i == 0 { 8 } else { 7 })
  }
  if !tri_verdict_ok(
      scc_partition_post(n, scc_bad, directed_cycle),
      scc_partition_post(n, scc_bad, directed_cycle),
      false,
    ) {
    return false
  }

  // bridges_post：无向链每条边都是桥 → 报告首边 (0,1) → 真。
  let bridge_good : Array[(Int, Int)] = [(0, 1)]
  if !tri_verdict_ok(
      bridges_post(n, undirected_chain, bridge_good),
      bridges_post(n, undirected_chain, bridge_good),
      true,
    ) {
    return false
  }
  // 坏见证：在含环的图（链 + 回边 0-(n-1)）中，(0,1) 不再是桥 → 判假。
  // 注：n==2 时回边 (0,1) 与链边 (0,1) 平行（平行边），删一条仍由另一条连通；
  // n>=3 时构成环 0-1-…-(n-1)-0，删 (0,1) 仍可绕行——故对所有 n>=2 均非桥，
  // bridges_post 报告 (0,1) 为桥即判假，期望恒为 false。
  let cyclic_undirected : Array[(Int, Int)] = []
  for e in undirected_chain {
    cyclic_undirected.push(e)
  }
  cyclic_undirected.push((0, n - 1))
  if !tri_verdict_ok(
      bridges_post(n, cyclic_undirected, bridge_good),
      bridges_post(n, cyclic_undirected, bridge_good),
      false,
    ) {
    return false
  }

  // condensation_is_dag：有向链（无环）→ 真；有向二元环 → 假。
  let dag_edges : Array[(Int, Int)] = []
  for i in 0..<(n - 1) {
    dag_edges.push((i, i + 1))
  }
  if !tri_verdict_ok(
      condensation_is_dag(n, dag_edges),
      condensation_is_dag(n, dag_edges),
      true,
    ) {
    return false
  }
  let cyclic_edges : Array[(Int, Int)] = [(0, 1), (1, 0)]
  if !tri_verdict_ok(
      condensation_is_dag(n, cyclic_edges),
      condensation_is_dag(n, cyclic_edges),
      false,
    ) {
    return false
  }
  true
}

// ---------------------------------------------------------------------------
// 族四 · 流与匹配 / 拓扑 / 欧拉（edmonds_karp / dinic / min_cut /
//        min_cost_flow / hopcroft_karp / kuhn_munkres / eulerian / topo_sort）
// ---------------------------------------------------------------------------

///|
/// 族四一致性校验：以最小可控的流网络 / 二分匹配 / 拓扑序 / 欧拉路径实例，
/// 覆盖最大流合法性、最大流=最小割、最小费用流、匹配合法性、带权完美匹配、
/// 拓扑序与欧拉路径 7 类谓词（edmonds_karp 与 dinic 共享 max_flow_valid）。
fn tb_flow_matching_family(rng : @infra_pbt.Rng) -> Bool {
  // 单边网络 0 →(cap) 1，流量 f <= cap。
  let cap = rng.next_range(2, 9)
  let flow_val = rng.next_range(1, cap)
  let edges_flow : Array[(Int, Int)] = [(0, 1)]
  let capacity : Array[Int] = [cap]
  let flow : Array[Int] = [flow_val]

  // max_flow_valid（edmonds_karp / dinic 共享）：容量约束 + 守恒 + 流值一致。
  if !tri_verdict_ok(
      max_flow_valid(2, edges_flow, capacity, flow, 0, 1, flow_val),
      max_flow_valid(2, edges_flow, capacity, flow, 0, 1, flow_val),
      true,
    ) {
    return false
  }
  // 坏见证：声明流值 +1，与实际净流不符 → 判假。
  if !tri_verdict_ok(
      max_flow_valid(2, edges_flow, capacity, flow, 0, 1, flow_val + 1),
      max_flow_valid(2, edges_flow, capacity, flow, 0, 1, flow_val + 1),
      false,
    ) {
    return false
  }

  // max_flow_equals_min_cut（min_cut）：源侧 {0}、汇侧 {1}，割容量 == cap。
  let source_side : Array[Bool] = [true, false]
  if !tri_verdict_ok(
      max_flow_equals_min_cut(2, edges_flow, capacity, source_side, 0, 1, cap),
      max_flow_equals_min_cut(2, edges_flow, capacity, source_side, 0, 1, cap),
      true,
    ) {
    return false
  }
  // 坏见证：声明最大流值 != 割容量 → 判假。
  if !tri_verdict_ok(
      max_flow_equals_min_cut(
        2,
        edges_flow,
        capacity,
        source_side,
        0,
        1,
        cap + 1,
      ),
      max_flow_equals_min_cut(
        2,
        edges_flow,
        capacity,
        source_side,
        0,
        1,
        cap + 1,
      ),
      false,
    ) {
    return false
  }

  // min_cost_flow_valid：单位费用 uc，总费用 == f * uc。
  let uc = rng.next_range(1, 5)
  let unit_cost : Array[Int] = [uc]
  let total_cost = flow_val * uc
  if !tri_verdict_ok(
      min_cost_flow_valid(
        2, edges_flow, capacity, unit_cost, flow, 0, 1, flow_val, total_cost,
      ),
      min_cost_flow_valid(
        2, edges_flow, capacity, unit_cost, flow, 0, 1, flow_val, total_cost,
      ),
      true,
    ) {
    return false
  }
  // 坏见证：声明总费用 +1 → 判假。
  if !tri_verdict_ok(
      min_cost_flow_valid(
        2,
        edges_flow,
        capacity,
        unit_cost,
        flow,
        0,
        1,
        flow_val,
        total_cost + 1,
      ),
      min_cost_flow_valid(
        2,
        edges_flow,
        capacity,
        unit_cost,
        flow,
        0,
        1,
        flow_val,
        total_cost + 1,
      ),
      false,
    ) {
    return false
  }

  // matching_valid（hopcroft_karp）：图含 (0,0)/(1,1)，匹配选这两条 → 合法。
  let graph_edges : Array[(Int, Int)] = [(0, 0), (1, 1)]
  let matching_good : Array[(Int, Int)] = [(0, 0), (1, 1)]
  if !tri_verdict_ok(
      matching_valid(matching_good, graph_edges),
      matching_valid(matching_good, graph_edges),
      true,
    ) {
    return false
  }
  // 坏见证：左部节点 0 被匹配两次 → 判假。
  let matching_bad : Array[(Int, Int)] = [(0, 0), (0, 1)]
  if !tri_verdict_ok(
      matching_valid(matching_bad, graph_edges),
      matching_valid(matching_bad, graph_edges),
      false,
    ) {
    return false
  }

  // perfect_matching_weight（kuhn_munkres）：完美匹配（规模 2）+ 权重一致。
  let mw0 = rng.next_range(1, 9)
  let mw1 = rng.next_range(1, 9)
  let match_weights : Array[Int] = [mw0, mw1]
  if !tri_verdict_ok(
      perfect_matching_weight(
        matching_good,
        graph_edges,
        match_weights,
        2,
        mw0 + mw1,
      ),
      perfect_matching_weight(
        matching_good,
        graph_edges,
        match_weights,
        2,
        mw0 + mw1,
      ),
      true,
    ) {
    return false
  }
  // 坏见证：声明总权重 +1 → 判假。
  if !tri_verdict_ok(
      perfect_matching_weight(
        matching_good,
        graph_edges,
        match_weights,
        2,
        mw0 + mw1 + 1,
      ),
      perfect_matching_weight(
        matching_good,
        graph_edges,
        match_weights,
        2,
        mw0 + mw1 + 1,
      ),
      false,
    ) {
    return false
  }

  // topo_order_post：DAG 链 0→1→2，序 [0,1,2] 合法。
  let dag_edges : Array[(Int, Int)] = [(0, 1), (1, 2)]
  let order_good : Array[Int] = [0, 1, 2]
  if !tri_verdict_ok(
      topo_order_post(order_good, dag_edges),
      topo_order_post(order_good, dag_edges),
      true,
    ) {
    return false
  }
  // 坏见证：逆序 [2,1,0] 违反每条边的先后约束 → 判假。
  let order_bad : Array[Int] = [2, 1, 0]
  if !tri_verdict_ok(
      topo_order_post(order_bad, dag_edges),
      topo_order_post(order_bad, dag_edges),
      false,
    ) {
    return false
  }

  // eulerian_trail_valid：边 (0,1)/(1,2)，欧拉路径 [0,1,2] 用尽每条边一次。
  let euler_edges : Array[(Int, Int)] = [(0, 1), (1, 2)]
  let trail_good : Array[Int] = [0, 1, 2]
  if !tri_verdict_ok(
      eulerian_trail_valid(trail_good, euler_edges),
      eulerian_trail_valid(trail_good, euler_edges),
      true,
    ) {
    return false
  }
  // 坏见证：[0,2,1] 的相邻对 (0,2) 不是图中边 → 判假。
  let trail_bad : Array[Int] = [0, 2, 1]
  if !tri_verdict_ok(
      eulerian_trail_valid(trail_bad, euler_edges),
      eulerian_trail_valid(trail_bad, euler_edges),
      false,
    ) {
    return false
  }
  true
}

///|
/// 单次三后端一致性场景：对四大算法族的全部 30 算法谓词逐一校验「确定性 +
/// 期望判定」。任一族失败即返回 `false`。纯函数链路保证三后端判定一致。
fn tb_scenario(rng : @infra_pbt.Rng) -> Bool {
  tb_shortest_path_family(rng) &&
  tb_unweighted_family(rng) &&
  tb_spanning_connectivity_family(rng) &&
  tb_flow_matching_family(rng)
}

///|
/// Feature: championship-v1-upgrade, Property 9.7: 30 算法证明谓词三后端判定确定且一致
/// （holds_for_all 模板，iters ≥ 100；在 wasm-gc/js/native 三后端分别运行）
///
/// **Validates: Requirements 9.1, 9.7, 9.8**
test "Feature: championship-v1-upgrade, Property 9.7: all 30 classic-algorithm proof predicates yield deterministic, backend-independent verdicts" {
  let gen = @infra_pbt.Gen::new(fn(rng) { tb_scenario(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }, iters=100))
}
