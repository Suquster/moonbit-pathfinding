// Feature: championship-v1-upgrade, Property 13: 无解见证谓词正确判定
//
// prop_none_witness_test.mbt —— none-witness 谓词属性测试（任务 10.4）。
//
//   Property 13: 无解见证谓词正确判定
//   ------------------------------------------------------------------
//   *对任意* 返回空路径（None）的查询，none-witness 谓词
//   `check_none_witness(result, start, successors, goal, nodes)` 当且仅当
//   输入图中确无从源 `start` 到满足 `goal` 节点的路径时判真：
//     * `result == None` 且目标确不可达  → 谓词判真（None 是合理的无解见证）；
//     * `result == None` 但目标实际可达  → 谓词判假（None 不是合理见证）；
//     * `result == Some(path)`           → none-witness 分量平凡为真
//                                          （谓词 C 仅约束 None 分支）。
//
//   该谓词是 BFS / 最短路族后置条件的「无解见证」分量（见 bfs_proof.mbt 的
//   `check_none_witness` 与 predicates.mbt 的 `is_reachable` 有界 BFS 预言机），
//   对应 Requirement 9.5「对无解查询返回空路径时校验确无从源到目标的路径并
//   据此输出布尔判定」。
//
// **Validates: Requirements 9.5**

///|
/// 由确定性随机源 `rng` 构造一个节点为 `0..<k` 的随机有向图，
/// 以邻接表 `Map[Int, Array[Int]]` 表示 successor 闭包。
///
/// 每个节点随机生成 `[0, k]` 条出边，目标节点取自 `[0, k)`；对重复目标去重
/// 以保持邻接表整洁（不影响 successors 语义）。返回的映射对任意 `0..<k` 节点
/// 均有条目，故由其派生的 successor 闭包对图内节点为全函数。
fn nw_build_graph(rng : @infra_pbt.Rng, k : Int) -> Map[Int, Array[Int]] {
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
/// 可达性的**独立参照实现**：以显式栈 DFS 判定从 `start` 是否存在到满足
/// `goal` 节点的路径。该实现与被测谓词内部依赖的 `is_reachable`（BFS 队列）
/// 采用不同遍历策略（DFS vs BFS），从而构成有意义的等价性对照（而非自我
/// 重复）。返回 `true` 表示目标可达。
fn nw_reachable_ref(
  start : Int,
  goal : (Int) -> Bool,
  successors : (Int) -> Array[Int],
) -> Bool {
  if goal(start) {
    return true
  }
  let visited : Map[Int, Bool] = Map([])
  visited[start] = true
  let stack : Array[Int] = [start]
  while stack.length() > 0 {
    let u = match stack.pop() {
      Some(x) => x
      None => break
    }
    for v in successors(u) {
      if visited.contains(v) {
        continue
      }
      if goal(v) {
        return true
      }
      visited[v] = true
      stack.push(v)
    }
  }
  false
}

///|
/// 单次场景：构造随机有向图与随机源/目标，校验 `check_none_witness` 的判定
/// 与 Property 13 的「当且仅当」定义完全一致。返回 `true` 表示本次随机实例
/// 下所有断言成立。
fn nw_scenario(rng : @infra_pbt.Rng) -> Bool {
  // 节点数 k ∈ [2, 8]，保证图规模适中且存在多节点以构造可达/不可达分支。
  let k = rng.next_range(2, 8)
  let adj = nw_build_graph(rng, k)
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
  let goal_node = rng.next_below(k)
  let goal = fn(n : Int) -> Bool { n == goal_node }

  // 独立 DFS 参照：目标是否真正可达。
  let reachable = nw_reachable_ref(start, goal, succ)

  // —— 核心「当且仅当」(A)：result == None 时，谓词判真 ⟺ 目标确不可达 ——
  // 即：可达 → 谓词判假（None 不是合理见证）；不可达 → 谓词判真。
  let none_result : Array[Int]? = None
  let verdict_none = check_none_witness(none_result, start, succ, goal, nodes)
  if verdict_none != !reachable {
    return false
  }

  // —— 反例分支 (B)：「目标可达但返回 None」→ 谓词必判假 ——
  // 构造一个保证可达的目标（goal == start，自反可达），此时返回 None 不合理。
  let goal_reachable = fn(n : Int) -> Bool { n == start }
  if check_none_witness(none_result, start, succ, goal_reachable, nodes) {
    return false
  }

  // —— 真例分支 (C)：「目标不可达且返回 None」→ 谓词必判真 ——
  // 构造一个恒不可满足的目标（从不为真），任何节点都不满足 → 确不可达。
  let goal_unreachable = fn(_n : Int) -> Bool { false }
  if !check_none_witness(none_result, start, succ, goal_unreachable, nodes) {
    return false
  }

  // —— 平凡分支 (D)：result == Some(path) 时，none-witness 分量恒为真 ——
  // 无论目标是否可达，只要给出显式（Some）见证，C 分量都平凡判真。
  let some_walk : Array[Int] = [start]
  let cap = rng.next_range(0, k + 2)
  let mut cur = start
  for _step in 0..<cap {
    let nbrs = succ(cur)
    if nbrs.length() == 0 {
      break
    }
    let nxt = nbrs[rng.next_below(nbrs.length())]
    some_walk.push(nxt)
    cur = nxt
  }
  let some_result : Array[Int]? = Some(some_walk)
  // Some 分支：谓词对随机目标恒判真（C 仅约束 None 分支）。
  if !check_none_witness(some_result, start, succ, goal, nodes) {
    return false
  }
  // 即便目标可达，Some 见证下 C 分量同样平凡为真。
  if !check_none_witness(some_result, start, succ, goal_reachable, nodes) {
    return false
  }

  // —— 等价性 (E)：对随机源/目标，None 分支谓词与独立 DFS 参照逐一致 ——
  // 独立随机 cstart / cgoal，进一步扩大可达/不可达两类分支的采样覆盖。
  let cstart = rng.next_below(k)
  let cgoal_node = rng.next_below(k)
  let cgoal = fn(n : Int) -> Bool { n == cgoal_node }
  let creachable = nw_reachable_ref(cstart, cgoal, succ)
  if check_none_witness(none_result, cstart, succ, cgoal, nodes) != !creachable {
    return false
  }
  true
}

///|
/// Feature: championship-v1-upgrade, Property 13: 无解见证谓词正确判定
/// （holds_for_all 模板，iters ≥ 100）
///
/// **Validates: Requirements 9.5**
test "Feature: championship-v1-upgrade, Property 13: none-witness predicate is true iff the graph truly has no path from source to goal" {
  let gen = @infra_pbt.Gen::new(fn(rng) { nw_scenario(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }, iters=100))
}
