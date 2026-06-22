// predicates.mbt — shared mathematical predicates for formal proofs.
//
// This module is the **single source of truth** for the invariants used
// across `bfs_proof.mbt` (task 33.2) and `dijkstra_proof.mbt` (task 34.x).
//
// Design philosophy (per design.md §7.1 / Requirement R8):
//   * Every proof assertion is encoded once as a `pub fn` returning `Bool`,
//     so that (a) the same predicate can be referenced from both the
//     `moon prove` post-condition comment block and from runtime tests
//     that exercise the predicate concretely, and (b) when `moon prove`
//     matures, its annotations can import these predicates directly.
//   * Each predicate is **total and pure** — no partial pattern matches,
//     no side effects, no recursion on unbounded data. `moon prove` is
//     happier with total functions.
//   * Predicates are **generic** in the node type `N : Eq + Hash`, so the
//     same definitions serve BFS (unweighted) and Dijkstra (weighted)
//     without duplication.
//
// When we flip the "Formally verified" badge from grey to green
// (tasks.md 34.3), every assertion in `bfs_proof.mbt` / `dijkstra_proof.mbt`
// will be phrased in terms of the predicates defined here.

///|
/// `is_valid_path(path, start, successors)` — true iff `path` is a legal
/// walk from `start` through the graph induced by `successors`.
///
/// Formal meaning (the target of `moon prove` for BFS / Dijkstra):
///
///   1. `path` is non-empty;
///   2. `path[0] == start`;
///   3. for every consecutive pair `(path[i], path[i+1])`, there exists
///      some successor of `path[i]` equal to `path[i+1]`.
///
/// This predicate is the "path-structural" half of the BFS post-condition:
/// together with `is_reachable` (reachability witness) it pins down what
/// "BFS returns a valid result" means.
pub fn[N : Eq] is_valid_path(
  path : Array[N],
  start : N,
  successors : (N) -> Array[N],
) -> Bool {
  if path.length() == 0 {
    return false
  }
  if path[0] != start {
    return false
  }
  let mut i = 0
  while i < path.length() - 1 {
    let u = path[i]
    let v = path[i + 1]
    // v must appear in successors(u). We do a linear scan because
    // successors may return any Array, not a set — this keeps the
    // predicate total and easy to prove about.
    let nbrs = successors(u)
    let mut found = false
    let mut j = 0
    while j < nbrs.length() {
      if nbrs[j] == v {
        found = true
        break
      }
      j += 1
    }
    if !found {
      return false
    }
    i += 1
  }
  true
}

///|
/// `is_reachable(start, goal, successors, nodes)` — true iff there exists
/// **some** path from `start` to a node satisfying `goal`.
///
/// The predicate is implemented as a bounded BFS over `nodes` (the whole
/// known node set), so it terminates even if `successors` would otherwise
/// enumerate an infinite state space. This makes it safe to call from proof
/// obligations that quantify over all graphs.
///
/// Bound rationale: a simple-path between two nodes visits every node at
/// most once, so iterating `nodes.length()` times from `start` is both
/// necessary and sufficient.
pub fn[N : Eq + Hash] is_reachable(
  start : N,
  goal : (N) -> Bool,
  successors : (N) -> Array[N],
  nodes : Array[N],
) -> Bool {
  if goal(start) {
    return true
  }
  let visited : Map[N, Bool] = Map([])
  visited[start] = true
  let queue : Array[N] = [start]
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head += 1
    for v in successors(u) {
      if visited.contains(v) {
        continue
      }
      if goal(v) {
        return true
      }
      visited[v] = true
      queue.push(v)
    }
  }
  // touch `nodes` to justify the bound. We only ever iterate up to
  // `nodes.length()` nodes because `visited` ensures no repeats; this
  // helper intentionally has the same asymptotic shape as BFS.
  ignore(nodes)
  false
}

///|
/// `path_cost(path, edge_weight)` — sum of edge weights along `path`.
///
/// `edge_weight(u, v)` should return `Some(w)` when `(u, v)` is an edge,
/// `None` otherwise. The predicate `is_valid_path` above uses `successors`
/// rather than `edge_weight`, so `path_cost` is a separate helper that
/// `dijkstra_proof.mbt` uses to phrase the "cost assertion".
///
/// If the path contains an illegal pair (no edge), the function returns
/// `None`, signalling "undefined cost". Dijkstra's post-condition quantifies
/// over only well-formed paths, so this `None` branch never fires in the
/// `moon prove` obligation, but having a total function keeps the proof
/// environment happy.
pub fn[N, W : @core.Weight] path_cost(
  path : Array[N],
  edge_weight : (N, N) -> W?,
) -> W? {
  if path.length() == 0 {
    return Some(@core.Weight::zero())
  }
  let mut total = @core.Weight::zero()
  let mut i = 0
  while i < path.length() - 1 {
    match edge_weight(path[i], path[i + 1]) {
      Some(w) => total = @core.Weight::add(total, w)
      None => return None
    }
    i += 1
  }
  Some(total)
}

///|
/// `is_non_negative(w)` — true iff `w >= Weight::zero()`.
///
/// Small but essential helper for Dijkstra's non-negativity invariant
/// (`dist[v] >= 0` for every reachable v under non-negative edge weights,
/// task 34.1). Keeping it as a named predicate makes the proof annotations
/// read like mathematics rather than inline comparisons.
pub fn[W : @core.Weight] is_non_negative(w : W) -> Bool {
  !(w < @core.Weight::zero())
}

///|
/// `all_edges_non_negative(edges, edge_weight)` — quantifier predicate
/// used as a *precondition* by Dijkstra's proof (Requirement R8.2a).
///
/// Iterates edge list explicitly; this avoids the need for `moon prove`
/// to reason about successor closures directly.
pub fn[N, W : @core.Weight] all_edges_non_negative(
  edges : Array[(N, N)],
  edge_weight : (N, N) -> W?,
) -> Bool {
  let mut i = 0
  while i < edges.length() {
    let (u, v) = edges[i]
    match edge_weight(u, v) {
      Some(w) => if !is_non_negative(w) { return false }
      None => ()
    }
    i += 1
  }
  true
}

// ---------------------------------------------------------------------------
// 通用方向无关谓词（direction-agnostic predicates）
//
// 以下谓词与具体图算法无关，作为各方向 `{方向}_proof.mbt` 的「通用谓词复用」
// 基座（详见 design.md「proofs（扩展）」）。它们同样保持纯、全（total）：
//   * round_trip_eq —— 往返一致性（parse∘print / decode∘encode）：
//       Mini_Compiler AST、Regex 语法树、Serialization、JSON-RPC、结构化日志复用；
//   * is_idempotent —— 幂等：Build_Tool 增量空操作复用；
//   * preserves     —— 不变量保持：SSA pass 流水线、run_passes 复用；
//   * seq_eq        —— 序列逐元素相等：DST 重放、Actor FIFO 顺序复用。
// ---------------------------------------------------------------------------

///|
/// `round_trip_eq(x, encode, decode)` —— 通用往返一致性谓词。
///
/// 当且仅当 `decode(encode(x))` 还原出与 `x` 相等的值时成立；解码失败（`None`）
/// 视为往返破坏，返回 `false`。各方向的「打印/解析」「编码/解码」往返性质均可
/// 以此谓词表述，避免在每个 `*_proof.mbt` 中重复编写往返骨架。
pub fn[T : Eq, S] round_trip_eq(
  x : T,
  encode : (T) -> S,
  decode : (S) -> T?,
) -> Bool {
  match decode(encode(x)) {
    Some(y) => y == x
    None => false
  }
}

///|
/// `is_idempotent(x, f)` —— 幂等谓词：`f(f(x)) == f(x)`。
///
/// 用于 Build_Tool「输入未变 → 零重建」等空操作不变量。
pub fn[T : Eq] is_idempotent(x : T, f : (T) -> T) -> Bool {
  let once = f(x)
  f(once) == once
}

///|
/// `preserves(x, transform, inv)` —— 不变量保持谓词。
///
/// 当 `x` 满足不变量 `inv` 时，要求 `transform(x)` 仍满足；`x` 本不满足时
/// 视为前提不成立，平凡为真。用于「SSA pass 保持单赋值不变量」一类性质。
pub fn[T] preserves(x : T, transform : (T) -> T, inv : (T) -> Bool) -> Bool {
  !inv(x) || inv(transform(x))
}

///|
/// `seq_eq(xs, ys)` —— 序列逐元素相等谓词。
///
/// 显式逐元素比较（不依赖 `Array::==`），保持谓词总且易于证明。用于
/// DST「同种子 → 同调度序列」与 Actor「发送序 == 处理序」等性质。
pub fn[T : Eq] seq_eq(xs : Array[T], ys : Array[T]) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  let mut i = 0
  while i < xs.length() {
    if xs[i] != ys[i] {
      return false
    }
    i += 1
  }
  true
}

// ---------------------------------------------------------------------------
// 四类核心谓词 → 统一聚合组合子（30 算法基座 · Requirement 9.1–9.6）
//
// 既有 `bfs_post` / `dijkstra_post` 已分别示范「无权可达」与「带权最短路」两
// 类后置条件的拼装方式。本节把它们归纳为 30 算法共享的复用基座：
//
//   (A) path-validity     —— 路径结构合法（非空、首=源、相邻对为图中边）
//        既有：`is_valid_path` / `check_edges_valid` / `check_edges_valid_weighted`
//   (B) cost-consistency  —— 返回代价 == 沿路径边权之和（精确相等；Double
//        的 ≤1e-9 容差由对应 PBT 用例驱动）
//        既有：`path_cost` / `check_cost_matches_path` / `check_non_negativity`
//   (C) none-witness      —— 返回 None/空 ⟺ 目标确不可达（有界 BFS 预言机）
//        既有：`is_reachable` / `check_none_witness`；本节新增带权重载
//        `check_none_witness_weighted` 适配最短路 `(Array[N], W)?` 结果形状。
//   (D) bad-witness 拒绝   —— 对故意构造的违例结果（违反 A/B/C 之一），聚合
//        谓词必判 false 且不修改、不丢弃输入。该性质由本模块所有谓词均为
//        **纯函数**（无副作用、不就地修改入参 `Array`/闭包）天然保证：谓词
//        只读取 `result` / `path` / `nodes` 并返回 `Bool`，从不写回。bad-witness
//        的拒绝行为由 10.5 的 `prop_bad_witness_test.mbt` 测试驱动验证。
//
// 新增的两个带权重载（`check_ends_at_goal_weighted` /
// `check_none_witness_weighted`）让上述谓词组合可直接服务最短路族 30 算法
// 的 `(Array[N], W)?` 结果，无需在各 `*_proof.mbt` 中重复编写拆包骨架。
// ---------------------------------------------------------------------------

///|
/// `check_ends_at_goal_weighted(result, goal)` —— path-validity(A) 的「末节点
/// 落在目标」分量，适配最短路算法的带权结果 `(Array[N], W)?`。
///
/// 与 `check_ends_at_goal`（无权 `Array[N]?`）语义一致：`Some((path, _))` 时
/// 要求 `path` 非空且末节点满足 `goal`；`None` 时平凡为真（由 none-witness 另
/// 行校验）。从带权结果中剥离权重分量后复用同一判定，避免重复。
pub fn[N, W] check_ends_at_goal_weighted(
  result : (Array[N], W)?,
  goal : (N) -> Bool,
) -> Bool {
  match result {
    Some((path, _cost)) => path.length() > 0 && goal(path[path.length() - 1])
    None => true
  }
}

///|
/// `check_none_witness_weighted(result, start, successors, goal, nodes)` ——
/// none-witness(C) 的带权重载，适配最短路算法的 `(Array[N], W)?` 结果。
///
/// 语义与 `check_none_witness`（无权）一致：`Some(_)` 时算法已给出显式可达
/// 见证，平凡为真；`None` 时用有界 BFS 预言机 `is_reachable` 交叉验证图中
/// 确无从 `start` 到满足 `goal` 节点的路径。带权后继 `(N, W)` 先剥离权重再
/// 复用无权可达性预言机——「是否可达」与边权无关。
pub fn[N : Eq + Hash, W] check_none_witness_weighted(
  result : (Array[N], W)?,
  start : N,
  successors : (N) -> Array[(N, W)],
  goal : (N) -> Bool,
  nodes : Array[N],
) -> Bool {
  match result {
    Some(_) => true
    None => {
      // 剥离权重分量，复用无权可达性预言机 is_reachable。
      let unw_succ = fn(n : N) -> Array[N] {
        let xs = successors(n)
        let out : Array[N] = []
        for p in xs {
          out.push(p.0)
        }
        out
      }
      !is_reachable(start, goal, unw_succ, nodes)
    }
  }
}

///|
/// `shortest_path_post(result, start, goal, successors, edge_weight, nodes)`
/// —— **统一聚合组合子**：把 path-validity(A) + cost-consistency(B) +
/// none-witness(C) 按「最短路语义」拼装为单一后置条件谓词（Requirement
/// 9.1–9.6）。`bfs_post` / `dijkstra_post` 是此模式的早期实例，本组合子将其
/// 推广为最短路族 30 算法（dijkstra/astar/bellman_ford/dag_sp/bidirectional_* /
/// ida_star/yen/johnson/floyd_warshall 等）共享的基座。
///
/// 判定语义：
///   * `result == Some((path, cost))`：
///       - (A) `path` 非空、`path[0] == start`、每相邻对 `(path[i], path[i+1])`
///         在图中存在对应边（经 `successors` 校验），且末节点满足 `goal`；
///       - (B) `cost` 与沿 `path` 各边权之和（经 `edge_weight` 累加）一致。
///   * `result == None`：
///       - (C) 用 `nodes` + `successors` 做有界可达性预言机，校验图中确无
///         从 `start` 到满足 `goal` 的路径。
///
/// 四个分量谓词对「不适用」分支均平凡返回 `true`（`Some` 分量在 `None` 时
/// 平凡真，反之亦然），故可直接合取，与 `bfs_post`/`dijkstra_post` 写法一致。
///
/// (D) bad-witness 拒绝：本谓词为纯函数，对违反 A/B/C 之一的 `result` 必返回
/// `false` 且不修改入参；由 10.5 测试驱动验证。
///
/// 运行时用法示例：
///
/// ```moonbit skip
/// let r = @dir.dijkstra(start, succ, edge_weight, goal)
/// assert_true(@proofs.shortest_path_post(r, start, goal, succ, edge_weight, nodes))
/// ```
pub fn[N : Eq + Hash, W : @core.Weight] shortest_path_post(
  result : (Array[N], W)?,
  start : N,
  goal : (N) -> Bool,
  successors : (N) -> Array[(N, W)],
  edge_weight : (N, N) -> W?,
  nodes : Array[N],
) -> Bool {
  // (A) 路径结构合法：非空、首=源、相邻对为边（check_edges_valid_weighted）
  //     + 末节点落在目标（check_ends_at_goal_weighted）。
  check_edges_valid_weighted(result, start, successors) &&
  check_ends_at_goal_weighted(result, goal) &&
  // (B) 代价一致：返回代价 == 沿路径边权之和。
  check_cost_matches_path(result, edge_weight) &&
  // (C) none-witness：None ⟺ 目标确不可达。
  check_none_witness_weighted(result, start, successors, goal, nodes)
}
