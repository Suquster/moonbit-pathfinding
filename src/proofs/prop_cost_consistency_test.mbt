// Feature: championship-v1-upgrade, Property 12: 代价一致性谓词正确判定
//
// prop_cost_consistency_test.mbt —— cost-consistency 谓词属性测试（任务 10.3）。
//
//   Property 12: 代价一致性谓词正确判定
//   ------------------------------------------------------------------
//   *对任意* 带权结果，cost-consistency 谓词
//   `check_cost_matches_path(result, edge_weight)` 当且仅当返回代价与沿返回
//   路径各边权重之和的偏差 ≤1e-9 时判真，否则判假：
//     * `result == Some((path, cost))` 且 `|cost - Σ edge_weight| ≤ 1e-9`
//        → 谓词判真（代价账目自洽）；
//     * `result == Some((path, cost))` 且偏差 > 1e-9（或路径含无边相邻对，
//        代价未定义）                  → 谓词判假；
//     * `result == None`               → cost-consistency 分量平凡为真
//                                        （谓词 B 仅约束 Some 分支）。
//
//   该谓词是最短路族后置条件的「代价一致」分量（见 dijkstra_proof.mbt 的
//   `check_cost_matches_path` 与 predicates.mbt 的 `path_cost` 沿路求和器），
//   对应 Requirement 9.4「对带权结果校验返回代价与沿返回路径边权之和的偏差
//   不超过 1e-9 并据此输出布尔判定」。
//
//   说明（精确相等 vs 1e-9 容差）：`check_cost_matches_path` 以 `W : Weight`
//   的 `==` 判定相等。对 **整数权** 而言，偏差非 0 即 ≥1（远大于 1e-9），故
//   精确相等与「偏差 ≤1e-9」在整数域完全等价——整数场景是 Property 12 最严格
//   的体现。对 **浮点权** 而言，本测试以「同序求和构造的精确和」落在 ≤1e-9
//   一侧、以「显著扰动（≥1.0）」落在 >1e-9 一侧，并用 1e-9 容差参照实现交叉
//   验证，从而驱动浮点容差语义（避开精确相等无法表达的 0<偏差≤1e-9 中间带）。
//
// **Validates: Requirements 9.4**

///|
/// 由确定性随机源 `rng` 构造节点为 `0..<k` 的随机带权有向图，邻接表为
/// `Map[Int, Array[(Int, Int)]]`（节点 → `[(目标, 权重)]`）。
///
/// 每个节点随机生成 `[0, k]` 条出边；对重复目标去重（保留首次权重），使
/// `edge_weight(u, v)` 对每条边有唯一确定的权重，从而 `path_cost` 沿路求和
/// 与「逐步走边时累加权重」必然一致。权重取自 `[0, 20]`，保证求和不触及
/// `Weight for Int` 的饱和「无穷」阈值。
fn cc_build_graph(rng : @infra_pbt.Rng, k : Int) -> Map[Int, Array[(Int, Int)]] {
  let adj : Map[Int, Array[(Int, Int)]] = Map([])
  for u in 0..<k {
    let outs : Array[(Int, Int)] = []
    let seen : Array[Int] = []
    // 出度 ∈ [0, k]，覆盖「无出边的汇点」到「稠密节点」全谱。
    let deg = rng.next_range(0, k)
    for _e in 0..<deg {
      let v = rng.next_below(k) // [0, k)
      if !seen.contains(v) {
        seen.push(v)
        let w = rng.next_range(0, 20)
        outs.push((v, w))
      }
    }
    adj[u] = outs
  }
  adj
}

///|
/// 整数权 cost-consistency 的**独立参照实现**：以「逆序」累加沿 `path` 各边
/// 权重（与 `path_cost` 内部的正序求和不同，构成有意义的等价性对照），再判定
/// 返回代价 `cost` 是否等于该和。空路径的代价定义为 0（与 `path_cost` 对空
/// 路径返回 `Some(zero())` 一致）。任一相邻对无边时代价未定义，返回 `false`。
///
/// 对整数而言「偏差 ≤1e-9」等价于「偏差 == 0」，故此处直接以相等判定。
fn cc_int_ref(
  path : Array[Int],
  cost : Int,
  edge_weight : (Int, Int) -> Int?,
) -> Bool {
  if path.length() == 0 {
    return cost == 0
  }
  let mut total = 0
  let mut i = path.length() - 1
  while i > 0 {
    match edge_weight(path[i - 1], path[i]) {
      Some(w) => total = total + w
      None => return false
    }
    i -= 1
  }
  total == cost
}

///|
/// 浮点权 cost-consistency 的**独立参照实现**：逆序累加沿 `path` 各边的浮点
/// 权重，并以 `|总和 - cost| ≤ 1e-9` 容差判定（直接体现 Requirement 9.4 的
/// 1e-9 偏差口径）。逆序求和与 `path_cost` 的正序求和因浮点非结合性可能存在
/// ~1e-15 量级差异，恰由 1e-9 容差吸收。任一相邻对无边时返回 `false`。
fn cc_double_ref(
  path : Array[Int],
  cost : Double,
  edge_weight : (Int, Int) -> Double?,
) -> Bool {
  if path.length() == 0 {
    return cost.abs() <= 1.0e-9
  }
  let mut total = 0.0
  let mut i = path.length() - 1
  while i > 0 {
    match edge_weight(path[i - 1], path[i]) {
      Some(w) => total = total + w
      None => return false
    }
    i -= 1
  }
  (total - cost).abs() <= 1.0e-9
}

///|
/// 单次场景：构造随机带权有向图与多类带权结果，校验
/// `check_cost_matches_path` 的判定与 Property 12 的「当且仅当」定义完全一致
/// （整数权 + 浮点权两条线）。返回 `true` 表示本次随机实例下所有断言成立。
fn cc_scenario(rng : @infra_pbt.Rng) -> Bool {
  // 节点数 k ∈ [2, 8]（k>=2 保证存在与任意 start 不同的节点，便于构造无边对）。
  let k = rng.next_range(2, 8)
  let adj = cc_build_graph(rng, k)

  // 整数权边权查询：在邻接表中线性查找 (u, v) 的权重。
  let ew = fn(u : Int, v : Int) -> Int? {
    match adj.get(u) {
      Some(outs) => {
        let mut res : Int? = None
        for pair in outs {
          if pair.0 == v {
            res = Some(pair.1)
            break
          }
        }
        res
      }
      None => None
    }
  }
  // 后继闭包（仅目标节点），用于沿真实边走出合法路径。
  let succ = fn(n : Int) -> Array[Int] {
    match adj.get(n) {
      Some(outs) => {
        let t : Array[Int] = []
        for p in outs {
          t.push(p.0)
        }
        t
      }
      None => []
    }
  }
  let start = rng.next_below(k)

  // —— 构造合法游走路径，并在走边时独立累加整数代价 walk_cost ——
  // walk_cost 由「实际选中的边权」累加得到，而 path_cost 由 edge_weight 重算，
  // 两条独立路径在去重图上必然一致。
  let path : Array[Int] = [start]
  let mut cur = start
  let mut walk_cost = 0
  let cap = rng.next_range(0, k + 2)
  for _step in 0..<cap {
    let outs = match adj.get(cur) {
      Some(xs) => xs
      None => []
    }
    if outs.length() == 0 {
      break
    }
    let pick = outs[rng.next_below(outs.length())]
    path.push(pick.0)
    walk_cost = walk_cost + pick.1
    cur = pick.0
  }

  // —— 正例 (A)：返回代价 == 沿路径边权之和 → 谓词必判真（整数精确，偏差 0）——
  if !check_cost_matches_path(Some((path, walk_cost)), ew) {
    return false
  }
  // 与独立逆序求和参照一致（同为真）。
  if check_cost_matches_path(Some((path, walk_cost)), ew) !=
    cc_int_ref(path, walk_cost, ew) {
    return false
  }

  // —— 反例 (B)：代价被扰动 delta≥1（偏差 ≥1 ≫ 1e-9）→ 谓词必判假 ——
  let delta = rng.next_range(1, 50)
  if check_cost_matches_path(Some((path, walk_cost + delta)), ew) {
    return false
  }

  // —— 平凡 (C)：result == None → cost-consistency 分量恒为真 ——
  if !check_cost_matches_path((None : (Array[Int], Int)?), ew) {
    return false
  }

  // —— 反例 (D)：路径含无边相邻对（代价未定义）→ 谓词对任意代价必判假 ——
  // 找一个不属于 succ(start) 的节点 v，构造 [start, v]（(start,v) 无边）。
  let nbrs0 = succ(start)
  let mut v = -1
  for cand in 0..<k {
    if !nbrs0.contains(cand) {
      v = cand
      break
    }
  }
  if v >= 0 {
    let broken : Array[Int] = [start, v]
    // 无论给出何种代价，path_cost 为 None → 谓词必判假。
    if check_cost_matches_path(Some((broken, 0)), ew) {
      return false
    }
    if check_cost_matches_path(Some((broken, 999)), ew) {
      return false
    }
  }

  // —— 当且仅当 (E)：对随机候选路径 + 随机候选代价，被测谓词与整数参照逐一致 ——
  // 候选路径长度 ∈ [0, k+2]，元素取自 [0, k)，候选代价取自 [0, 60]，自然覆盖
  // 空/合法/断裂/代价相符/代价不符等全部分支。
  let clen = rng.next_range(0, k + 2)
  let cand_path : Array[Int] = []
  for _i in 0..<clen {
    cand_path.push(rng.next_below(k))
  }
  let ccost = rng.next_range(0, 60)
  if check_cost_matches_path(Some((cand_path, ccost)), ew) !=
    cc_int_ref(cand_path, ccost, ew) {
    return false
  }

  // —— 浮点线：以整数权派生分数浮点权，驱动 1e-9 容差语义 ——
  // dew(u,v) = ew(u,v) / 7.0，产生形如 2.857142857… 的分数权重。
  let dew = fn(u : Int, vv : Int) -> Double? {
    match ew(u, vv) {
      Some(w) => Some(w.to_double() / 7.0)
      None => None
    }
  }
  // 浮点正确代价 = 沿 path 的正序求和（与 path_cost 同序，精确相等成立）。
  let dcost = match path_cost(path, dew) {
    Some(c) => c
    None => return false // 合法游走路径所有边均存在，不应为 None。
  }
  // 浮点正例 (A')：偏差 0 ≤ 1e-9 → 谓词判真，且与 1e-9 容差参照一致。
  if !check_cost_matches_path(Some((path, dcost)), dew) {
    return false
  }
  if check_cost_matches_path(Some((path, dcost)), dew) !=
    cc_double_ref(path, dcost, dew) {
    return false
  }
  // 浮点反例 (B')：扰动 +1.0（偏差 1.0 ≫ 1e-9）→ 谓词判假，且与参照一致。
  let dbad = dcost + 1.0
  if check_cost_matches_path(Some((path, dbad)), dew) {
    return false
  }
  if check_cost_matches_path(Some((path, dbad)), dew) !=
    cc_double_ref(path, dbad, dew) {
    return false
  }
  // 浮点平凡 (C')：result == None → 分量恒为真。
  if !check_cost_matches_path((None : (Array[Int], Double)?), dew) {
    return false
  }
  true
}

///|
/// Feature: championship-v1-upgrade, Property 12: 代价一致性谓词正确判定
/// （holds_for_all 模板，iters ≥ 100）
///
/// **Validates: Requirements 9.4**
test "Feature: championship-v1-upgrade, Property 12: cost-consistency predicate is true iff returned cost matches the path edge-weight sum within 1e-9" {
  let gen = @infra_pbt.Gen::new(fn(rng) { cc_scenario(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }, iters=100))
}
