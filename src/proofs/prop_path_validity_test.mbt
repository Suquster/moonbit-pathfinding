// Feature: championship-v1-upgrade, Property 11: 路径结构合法性谓词正确判定
//
// prop_path_validity_test.mbt —— path-validity 谓词属性测试（任务 10.2）。
//
//   Property 11: 路径结构合法性谓词正确判定
//   ------------------------------------------------------------------
//   *对任意* 随机有向图（节点 0..k 的 successor 闭包）与随机候选路径，
//   path-validity 谓词 `is_valid_path(path, start, successors)` 当且仅当
//   以下三条件同时成立时判真，否则判假：
//     (1) 路径非空（path.length() > 0）；
//     (2) 首节点等于查询源（path[0] == start）；
//     (3) 每相邻对 (path[i], path[i+1]) 在图中存在对应有向边
//         （即 path[i+1] ∈ successors(path[i])）。
//
//   该谓词是 BFS / 最短路族后置条件的「路径结构」分量（见 predicates.mbt
//   的 `is_valid_path`），对应 Requirement 9.3「路径首节点=源且每相邻对为
//   图中边时判真」与 Requirement 9.2「对满足/违反后置条件分别判真/假」。
//
// **Validates: Requirements 9.2, 9.3**

///|
/// 由确定性随机源 `rng` 构造一个节点为 `0..<k` 的随机有向图，
/// 以邻接表 `Map[Int, Array[Int]]` 表示 successor 闭包。
///
/// 每个节点随机生成 `0..k` 条出边，目标节点取自 `[0, k)`；对重复目标做去重
/// 以保持邻接表整洁（不影响 successors 语义）。返回的映射对任意 `0..<k` 节点
/// 均有条目，故由其派生的 successor 闭包对图内节点为全函数。
fn pv_build_graph(rng : @infra_pbt.Rng, k : Int) -> Map[Int, Array[Int]] {
  let adj : Map[Int, Array[Int]] = Map([])
  for u in 0..<k {
    let outs : Array[Int] = []
    // 出度 ∈ [0, k]，覆盖「无出边的汇点」到「稠密节点」全谱。
    let deg = rng.next_range(0, k)
    for _e in 0..<deg {
      let v = rng.next_below(k) // [0, k)
      if !outs.contains(v) {
        outs.push(v)
      }
    }
    adj[u] = outs
  }
  adj
}

///|
/// path-validity 的**独立参照实现**：直接按 Property 11 的三条件逐项判定，
/// 用于与被测谓词 `is_valid_path` 做「当且仅当」等价性交叉验证。
///
/// 这里以 `Array::contains` 做相邻对成边检查，实现路径与 `is_valid_path`
/// 内部的线性扫描不同，从而构成有意义的等价性对照（而非自我重复）。
fn pv_reference(
  path : Array[Int],
  start : Int,
  successors : (Int) -> Array[Int],
) -> Bool {
  // 条件 (1)：非空。
  if path.length() == 0 {
    return false
  }
  // 条件 (2)：首节点 == 源。
  if path[0] != start {
    return false
  }
  // 条件 (3)：每相邻对为图中边。
  let mut i = 0
  while i < path.length() - 1 {
    if !successors(path[i]).contains(path[i + 1]) {
      return false
    }
    i += 1
  }
  true
}

///|
/// 单次场景：构造随机有向图与多类候选路径，校验 `is_valid_path` 的判定与
/// Property 11 的「当且仅当」定义完全一致。返回 `true` 表示本次随机实例下
/// 所有断言成立。
fn pv_scenario(rng : @infra_pbt.Rng) -> Bool {
  // 节点数 k ∈ [2, 8]（k>=2 保证存在与任意 start 不同的节点，便于构造反例）。
  let k = rng.next_range(2, 8)
  let adj = pv_build_graph(rng, k)
  let succ = fn(n : Int) -> Array[Int] {
    match adj.get(n) {
      Some(xs) => xs
      None => []
    }
  }
  let start = rng.next_below(k)

  // —— 正例 (A)：从图中按真实边走出的路径 → 谓词必判真 ——
  // 自 start 起，每步随机选取一个真实后继；遇汇点或达步数上限即止。
  let walk : Array[Int] = [start]
  let cap = rng.next_range(0, k + 2)
  let mut cur = start
  for _step in 0..<cap {
    let nbrs = succ(cur)
    if nbrs.length() == 0 {
      break
    }
    let nxt = nbrs[rng.next_below(nbrs.length())]
    walk.push(nxt)
    cur = nxt
  }
  // 真实游走路径：非空、首=源、相邻对均为边 → 必为真。
  if !is_valid_path(walk, start, succ) {
    return false
  }
  // 与参照实现一致（此处应同为真）。
  if is_valid_path(walk, start, succ) != pv_reference(walk, start, succ) {
    return false
  }

  // —— 反例 (B)：空路径 → 违反条件 (1) → 必判假 ——
  let empty : Array[Int] = []
  if is_valid_path(empty, start, succ) {
    return false
  }

  // —— 反例 (C)：首节点 != 源 → 违反条件 (2) → 必判假 ——
  // 取与 start 不同的节点 other 作为首节点（k>=2 保证存在）。
  let other = (start + 1) % k
  let wrong_start : Array[Int] = []
  for x in walk {
    wrong_start.push(x)
  }
  wrong_start[0] = other
  // 首节点 other != start，无论后续边是否合法都必判假。
  if is_valid_path(wrong_start, start, succ) {
    return false
  }

  // —— 反例 (D)：注入断裂（相邻对无边）→ 违反条件 (3) → 必判假 ——
  // 仅在能找到「不属于 succ(start) 的节点 v」时构造（否则该位无法断裂）。
  if walk.length() >= 2 {
    let nbrs0 = succ(start)
    let mut v = -1
    for cand in 0..<k {
      if !nbrs0.contains(cand) {
        v = cand
        break
      }
    }
    if v >= 0 {
      let broken : Array[Int] = []
      for x in walk {
        broken.push(x)
      }
      broken[1] = v // (start, v) 无边 → 必判假
      if is_valid_path(broken, start, succ) {
        return false
      }
    }
  }

  // —— 当且仅当 (E)：对任意随机候选路径，被测谓词与参照定义逐位一致 ——
  // 候选路径长度 ∈ [0, k+2]，元素取自 [0, k)，自然覆盖空/合法/断裂/错首
  // 等全部情形；候选源 cstart 独立随机，进一步覆盖「首 != 源」分支。
  let clen = rng.next_range(0, k + 2)
  let cand_path : Array[Int] = []
  for _i in 0..<clen {
    cand_path.push(rng.next_below(k))
  }
  let cstart = rng.next_below(k)
  if is_valid_path(cand_path, cstart, succ) !=
    pv_reference(cand_path, cstart, succ) {
    return false
  }
  true
}

///|
/// Feature: championship-v1-upgrade, Property 11: 路径结构合法性谓词正确判定
/// （holds_for_all 模板，iters ≥ 100）
///
/// **Validates: Requirements 9.2, 9.3**
test "Feature: championship-v1-upgrade, Property 11: path-validity predicate is true iff non-empty, starts at source, and every adjacent pair is an edge" {
  let gen = @infra_pbt.Gen::new(fn(rng) { pv_scenario(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }, iters=100))
}
