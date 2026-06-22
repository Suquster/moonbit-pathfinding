// fuzz_driver_test.mbt —— 模糊测试「驱动逻辑」（task 16.1）。
//
// 设计依据（design.md §5.1 Fuzz_Generator · Requirement 17.2/17.3/17.4/17.5）：
//
//   本文件提供把 `FuzzGraph` 喂给一批具体寻路算法、逐一运行并对其「鲁棒性」
//   作结构化裁决的驱动逻辑（harness）。它是 Property 27（task 16.2，
//   `prop_fuzz_robust_test.mbt`）的底层支撑，本身亦以单元测试自验。
//
// 鲁棒性的精确含义（R17.3）：对任一图实例运行任一算法，算法必须
//   (a) 正常终止（不死循环 / 不崩溃）——由「测试能跑完且无 panic」见证；
//   (b) 返回**结构上有效的结果**（合法路径 / 距离映射 / 全对矩阵 / 明确无解），
//       或返回**结构化 `PathError`**（R13 / R17.5）。
// 任一返回结果若结构非法（如「路径」并非图中真实游走、代价与路径不符、
// Floyd-Warshall 对角非零等），即判定该算法在该实例上**不鲁棒**。
//
// 种子与可复现（R17.4 / R17.7）：驱动入口接受 `UInt64` 种子，由
//   `@infra_pbt.rng_new(seed)` + 确定性生成器复现同一图；裁决报告携带种子，
//   失败时可经 `describe()` 输出「种子 + 各算法裁决」用于定位与复现。
//
// 非法参数处理（R17.5）：`probe_invalid_args` 专门以空节点集 / 越界源 / 越界
//   目标驱动结构化入口，断言其返回对应 `PathError` 变体而非崩溃。
//
// 质量约束（steering）：全函数实现、无 abort/todo!/panic 占位；精确枚举表示
//   结构化数据（禁止字符串模拟）；报告文本经 `@infra_text.TextBuilder` 构建，
//   绝不在循环内做字符串 `+` 拼接；全程中文注释。

///|
/// 被模糊测试的算法标识（精确枚举 · 禁止字符串模拟结构化数据）。
///
/// - `Bfs`               —— `@unweighted.bfs`（无权最短跳数）。
/// - `Dijkstra`          —— `@directed.dijkstra`（非负权单源最短路）。
/// - `BellmanFord`       —— `@directed.bellman_ford`（支持负权 + 负环检测）。
/// - `FloydWarshall`     —— `@directed.floyd_warshall`（全对最短距离矩阵）。
/// - `TypedShortestPath` —— `@graph.typed_shortest_path`（结构化错误入口）。
/// - `TypedBfs`          —— `@graph.typed_bfs_path`（结构化错误入口）。
/// - `Alt`               —— `@advanced.alt_*`（地标三角不等式加速）。
/// - `Ch`                —— `@advanced.ch_*`（收缩层次加速）。
enum FuzzAlgo {
  Bfs
  Dijkstra
  BellmanFord
  FloydWarshall
  TypedShortestPath
  TypedBfs
  Alt
  Ch
} derive(Eq, Show)

///|
/// 算法终止后的结果分类（精确枚举 · 携带规模信息便于报告与调试）。
///
/// - `PathFound(hops)` —— 找到路径，`hops` 为边数（跳数）。
/// - `NoPath`          —— 明确无解（`None` / `Unreachable`），仍属有效结果。
/// - `DistMap(size)`   —— 返回单源距离映射，`size` 为条目数。
/// - `Matrix(size)`    —— 返回全对距离矩阵，`size` 为条目数（应为 N×N）。
/// - `StructError`     —— 返回结构化 `PathError`（R17.5 结构化处理路径）。
enum FuzzResultKind {
  PathFound(Int)
  NoPath
  DistMap(Int)
  Matrix(Int)
  StructError
} derive(Eq, Show)

///|
/// 单算法鲁棒性裁决：`robust` 为真表示该算法在该图实例上安全终止并产出可接受
/// 结果（有效结果或结构化错误）；`kind` 记录结果分类用于报告。
struct AlgoVerdict {
  algo : FuzzAlgo
  robust : Bool
  kind : FuzzResultKind
} derive(Eq, Show)

///|
/// 一次模糊运行的聚合报告：携带触发用例的随机种子（R17.4 / R17.7）、图规模、
/// 各算法裁决，以及「全部算法均鲁棒」的总判定 `robust`。
struct FuzzRunReport {
  seed : UInt64
  graph_n : Int
  graph_m : Int
  verdicts : Array[AlgoVerdict]
  robust : Bool
} derive(Show)

// ───────────────────────── 邻接预计算与图视图 ─────────────────────────

///|
/// 由 `FuzzGraph` 预计算的高效图视图，避免每次邻居查询重扫边表（防 O(n·m)）。
///
/// - `node_list` —— 节点全集 `[0, n)`，供 edge-list / nodes 形参的算法使用。
/// - `edges`     —— 原始有向带权边序列副本（Bellman-Ford / Floyd-Warshall）。
/// - `adj_w`     —— 带权后继邻接表：`adj_w[u]` 为 `u` 的全部出边 `(目标, 权重)`。
/// - `adj_u`     —— 无权后继邻接表（同一 `(u,v)` 去重）：供 BFS 使用。
/// - `min_edge`  —— `(u,v) → 最小边权`，用于校验返回路径的代价与实际边权一致
///                  （平行边取最小，与各算法松弛口径一致）。
struct FuzzAdj {
  n : Int
  node_list : Array[Int]
  edges : Array[(Int, Int, Double)]
  adj_w : Array[Array[(Int, Double)]]
  adj_u : Array[Array[Int]]
  min_edge : Map[(Int, Int), Double]
}

///|
/// 由 `FuzzGraph` 构建 `FuzzAdj`：线性扫描边表，预分配邻接桶并 `push`，
/// 绝不在循环内做数组 `+` 拼接（无 O(n²) 复制）。生成器保证端点落在 `[0, n)`，
/// 仍冗余做范围校验以对任意 `FuzzGraph` 输入鲁棒。
fn build_adj(g : FuzzGraph) -> FuzzAdj {
  let n = g.n
  let node_list : Array[Int] = []
  for i in 0..<n {
    node_list.push(i)
  }
  let adj_w : Array[Array[(Int, Double)]] = []
  let adj_u : Array[Array[Int]] = []
  for _i in 0..<n {
    adj_w.push([])
    adj_u.push([])
  }
  let min_edge : Map[(Int, Int), Double] = Map([])
  // 无权后继去重集合：避免 BFS 邻接表中出现重复目标（平行边）。
  let seen_u : Map[(Int, Int), Unit] = Map([])
  let edges : Array[(Int, Int, Double)] = []
  for e in g.edges {
    let (u, v, w) = e
    if u >= 0 && u < n && v >= 0 && v < n {
      edges.push((u, v, w))
      adj_w[u].push((v, w))
      match min_edge.get((u, v)) {
        Some(cur) => if w < cur { min_edge[(u, v)] = w }
        None => min_edge[(u, v)] = w
      }
      if !(seen_u.get((u, v)) is Some(_)) {
        seen_u[(u, v)] = ()
        adj_u[u].push(v)
      }
    }
  }
  { n, node_list, edges, adj_w, adj_u, min_edge }
}

///|
/// 带权后继函数视图：越界节点返回空数组（防御性），图内节点返回其出边。
fn FuzzAdj::weighted_succ(self : FuzzAdj) -> (Int) -> Array[(Int, Double)] {
  fn(u) { if u >= 0 && u < self.n { self.adj_w[u] } else { [] } }
}

///|
/// 无权后继函数视图：越界节点返回空数组，图内节点返回（去重后的）后继。
fn FuzzAdj::unweighted_succ(self : FuzzAdj) -> (Int) -> Array[Int] {
  fn(u) { if u >= 0 && u < self.n { self.adj_u[u] } else { [] } }
}

///|
/// 是否存在有向边 `u → v`。
fn FuzzAdj::has_edge(self : FuzzAdj, u : Int, v : Int) -> Bool {
  self.min_edge.get((u, v)) is Some(_)
}

///|
/// `u → v` 的最小边权（平行边取最小）；无此边返回 `None`。
fn FuzzAdj::min_weight(self : FuzzAdj, u : Int, v : Int) -> Double? {
  self.min_edge.get((u, v))
}

// ───────────────────────── 数值与校验辅助 ─────────────────────────

///|
/// 双精度绝对值（全函数，不依赖可能缺失的库函数，三后端逐位一致）。
fn dabs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
/// 路径代价比较的相对容差：随代价量级线性放宽，吸收逐段求和与算法内部
/// 累加的浮点次序差异，避免「数值上等价却因末位舍入判不一致」的误报。
fn cost_eps(cost : Double) -> Double {
  1.0e-6 * (dabs(cost) + 1.0)
}

///|
/// 校验返回路径是「图中真实游走」：非空、首节点为 `source`、末节点为 `target`、
/// 相邻节点对均由一条有向边相连。是「返回有效结果」(R17.3) 的核心判据。
fn valid_walk(
  adj : FuzzAdj,
  source : Int,
  target : Int,
  path : Array[Int],
) -> Bool {
  let len = path.length()
  if len == 0 {
    return false
  }
  if path[0] != source || path[len - 1] != target {
    return false
  }
  let mut i = 0
  while i + 1 < len {
    if !adj.has_edge(path[i], path[i + 1]) {
      return false
    }
    i += 1
  }
  true
}

///|
/// 校验带权路径结果：先校验为真实游走，再校验代价非 NaN、且与「逐段最小边权
/// 之和」在 `cost_eps` 容差内一致。`allow_negative` 为假时附加「代价非负」校验
/// （非负权电池）；为真时允许负代价（含负权边的有符号电池）。
fn valid_weighted_result(
  adj : FuzzAdj,
  source : Int,
  target : Int,
  path : Array[Int],
  cost : Double,
  allow_negative : Bool,
) -> Bool {
  if !valid_walk(adj, source, target, path) {
    return false
  }
  // NaN 一律判非法（NaN != NaN 恒真）。
  if cost != cost {
    return false
  }
  if !allow_negative && cost < 0.0 {
    return false
  }
  // 代价应等于路径上逐段最小边权之和（平行边取最小，与松弛口径一致）。
  let mut sum = 0.0
  let mut i = 0
  while i + 1 < path.length() {
    match adj.min_weight(path[i], path[i + 1]) {
      Some(w) => sum = sum + w
      None => return false
    }
    i += 1
  }
  approx_eq(cost, sum, cost_eps(cost))
}

// ───────────────────────── 单算法运行器 ─────────────────────────
//
// 每个运行器：运行算法 → 对返回值作结构化校验 → 产出 `AlgoVerdict`。
// 校验失败即 `robust = false`（暴露潜在缺陷）；正常无解 / 结构化错误均为鲁棒。

///|
/// 运行 `@unweighted.bfs`：`Some(path)` 校验为真实无权游走；`None` 视为明确无解。
fn run_bfs(adj : FuzzAdj, source : Int, target : Int) -> AlgoVerdict {
  let succ = adj.unweighted_succ()
  match @uw.bfs(source, succ, fn(x) { x == target }) {
    Some(path) => {
      let ok = valid_walk(adj, source, target, path)
      { algo: Bfs, robust: ok, kind: PathFound(path.length() - 1) }
    }
    None => { algo: Bfs, robust: true, kind: NoPath }
  }
}

///|
/// 运行 `@directed.dijkstra`（非负权电池）：`Some((path, cost))` 作带权校验
/// （不允许负代价）；`None` 视为明确无解。
fn run_dijkstra(adj : FuzzAdj, source : Int, target : Int) -> AlgoVerdict {
  let succ = adj.weighted_succ()
  match @dir.dijkstra(source, succ, fn(x) { x == target }) {
    Some((path, cost)) => {
      let ok = valid_weighted_result(adj, source, target, path, cost, false)
      { algo: Dijkstra, robust: ok, kind: PathFound(path.length() - 1) }
    }
    None => { algo: Dijkstra, robust: true, kind: NoPath }
  }
}

///|
/// 运行 `@directed.bellman_ford`：`Ok(dist)` 校验源距离为 0、且各距离非 NaN
/// （非负权电池下并应非负）；`Err(_)`（负环）视为结构化处理（鲁棒）。
fn run_bellman_ford(
  adj : FuzzAdj,
  source : Int,
  allow_negative : Bool,
) -> AlgoVerdict {
  match @dir.bellman_ford(adj.node_list, adj.edges, source) {
    Ok(dist) => {
      let mut ok = match dist.get(source) {
        Some(d) => d == 0.0
        None => false
      }
      for pair in dist {
        let (_, d) = pair
        if d != d {
          ok = false // NaN
        }
        if !allow_negative && d < 0.0 {
          ok = false
        }
      }
      { algo: BellmanFord, robust: ok, kind: DistMap(dist.length()) }
    }
    Err(_) => { algo: BellmanFord, robust: true, kind: StructError }
  }
}

///|
/// 运行 `@directed.floyd_warshall`：校验矩阵规模为 N×N、无 NaN，且自身到自身
/// 的距离符合预期。`allow_negative` 为假（非负权）时对角线必为 0；为真（可含
/// 负权）时对角线必 ≤ 0——含负权环的图中，某节点经负环回到自身的总权可为负，
/// 这是 Floyd-Warshall 的**正确终止行为**（它不检测负环），而非鲁棒性违例；
/// 自距永不可能为正。
fn run_floyd_warshall(adj : FuzzAdj, allow_negative : Bool) -> AlgoVerdict {
  let m = @dir.floyd_warshall(adj.node_list, adj.edges)
  let mut ok = m.length() == adj.n * adj.n
  // 对角线（自身到自身）检查。
  let mut i = 0
  while i < adj.n {
    match m.get((i, i)) {
      Some(d) =>
        if d != d {
          ok = false // NaN
        } else if allow_negative {
          if d > 0.0 {
            ok = false // 自距不可能为正
          }
        } else if d != 0.0 {
          ok = false // 非负权下自距必为 0
        }
      None => ok = false
    }
    i += 1
  }
  // 任一条目为 NaN 即非法。
  for pair in m {
    let (_, d) = pair
    if d != d {
      ok = false
    }
  }
  { algo: FloydWarshall, robust: ok, kind: Matrix(m.length()) }
}

///|
/// 运行 `@graph.typed_shortest_path`（结构化错误入口）：`Ok((path, cost))`
/// 作带权校验；`Err(_)`（SourceNotFound / TargetNotFound / Unreachable /
/// NegativeCycle / InvalidArgument）均为结构化处理（鲁棒）。
fn run_typed_sp(
  adj : FuzzAdj,
  source : Int,
  target : Int,
  allow_negative : Bool,
) -> AlgoVerdict {
  let succ = adj.weighted_succ()
  match @graph.typed_shortest_path(adj.node_list, source, target, succ) {
    Ok((path, cost)) => {
      let ok = valid_weighted_result(
        adj, source, target, path, cost, allow_negative,
      )
      {
        algo: TypedShortestPath,
        robust: ok,
        kind: PathFound(path.length() - 1),
      }
    }
    Err(_) => { algo: TypedShortestPath, robust: true, kind: StructError }
  }
}

///|
/// 运行 `@graph.typed_bfs_path`（结构化错误入口）：`Ok((path, hops))` 校验为
/// 真实无权游走且 `hops == path.length() - 1`；`Err(_)` 为结构化处理（鲁棒）。
fn run_typed_bfs(adj : FuzzAdj, source : Int, target : Int) -> AlgoVerdict {
  let succ = adj.unweighted_succ()
  match @graph.typed_bfs_path(adj.node_list, source, target, succ) {
    Ok((path, hops)) => {
      let ok = valid_walk(adj, source, target, path) &&
        hops == path.length() - 1
      { algo: TypedBfs, robust: ok, kind: PathFound(hops) }
    }
    Err(_) => { algo: TypedBfs, robust: true, kind: StructError }
  }
}

///|
/// 运行 `@advanced.alt_*`（非负权电池）：预处理后查询，`Some((path, cost))`
/// 作带权校验；`None` 视为明确无解。地标数取 `min(2, n)`。
fn run_alt(adj : FuzzAdj, source : Int, target : Int) -> AlgoVerdict {
  let succ = adj.weighted_succ()
  let num_landmarks = if adj.n < 2 { adj.n } else { 2 }
  let lm = @adv.alt_preprocess(adj.node_list, succ, num_landmarks)
  match @adv.alt_query(lm, source, target, succ) {
    Some((path, cost)) => {
      let ok = valid_weighted_result(adj, source, target, path, cost, false)
      { algo: Alt, robust: ok, kind: PathFound(path.length() - 1) }
    }
    None => { algo: Alt, robust: true, kind: NoPath }
  }
}

///|
/// 运行 `@advanced.ch_*`（非负权电池）：预处理后查询，`Some((path, cost))`
/// 作带权校验（CH 将快捷边解包回原始节点，路径相邻对应为原始边）；
/// `None` 视为明确无解。
fn run_ch(adj : FuzzAdj, source : Int, target : Int) -> AlgoVerdict {
  let succ = adj.weighted_succ()
  let g = @adv.ch_preprocess(adj.node_list, succ)
  match @adv.ch_query(g, source, target) {
    Some((path, cost)) => {
      let ok = valid_weighted_result(adj, source, target, path, cost, false)
      { algo: Ch, robust: ok, kind: PathFound(path.length() - 1) }
    }
    None => { algo: Ch, robust: true, kind: NoPath }
  }
}

// ───────────────────────── 聚合驱动入口 ─────────────────────────

///|
/// 由各算法裁决聚合「全部鲁棒」总判定。
fn aggregate_robust(verdicts : Array[AlgoVerdict]) -> Bool {
  let mut robust = true
  for v in verdicts {
    if !v.robust {
      robust = false
    }
  }
  robust
}

///|
/// 对一个**非负权**图实例运行完整算法电池（BFS / Dijkstra / Bellman-Ford /
/// Floyd-Warshall / typed_shortest_path / typed_bfs / ALT / CH），逐一裁决
/// 鲁棒性并聚合为 `FuzzRunReport`（携带 `seed` 以便复现 · R17.4/R17.7）。
///
/// 源 / 目标固定取 `0` 与 `n-1`（覆盖 `source == target` 的单节点边界）。
/// 空图（`n == 0`）无合法节点：仅运行 Floyd-Warshall（空矩阵）与结构化入口的
/// 非法参数路径（应返回 `InvalidArgument`），确保对空图同样鲁棒。
fn fuzz_run_nonneg(g : FuzzGraph, seed : UInt64) -> FuzzRunReport {
  let adj = build_adj(g)
  let verdicts : Array[AlgoVerdict] = []
  if g.n >= 1 {
    let source = 0
    let target = g.n - 1
    verdicts.push(run_bfs(adj, source, target))
    verdicts.push(run_dijkstra(adj, source, target))
    verdicts.push(run_bellman_ford(adj, source, false))
    verdicts.push(run_floyd_warshall(adj, false))
    verdicts.push(run_typed_sp(adj, source, target, false))
    verdicts.push(run_typed_bfs(adj, source, target))
    verdicts.push(run_alt(adj, source, target))
    verdicts.push(run_ch(adj, source, target))
  } else {
    // 空图：Floyd-Warshall 返回空矩阵（规模 0 == 0×0）。
    verdicts.push(run_floyd_warshall(adj, false))
    // 结构化入口对空节点集应返回 InvalidArgument（结构化处理 · R17.5）。
    let succ = adj.weighted_succ()
    let kind = match @graph.typed_shortest_path(adj.node_list, 0, 0, succ) {
      Ok(_) => PathFound(0) // 不应发生：空节点集无法产出路径。
      Err(@graph.PathError::InvalidArgument(_)) => StructError
      Err(_) => StructError
    }
    let robust = match @graph.typed_shortest_path(adj.node_list, 0, 0, succ) {
      Err(@graph.PathError::InvalidArgument(_)) => true
      _ => false
    }
    verdicts.push({ algo: TypedShortestPath, robust, kind })
  }
  {
    seed,
    graph_n: g.n,
    graph_m: g.edges.length(),
    verdicts,
    robust: aggregate_robust(verdicts),
  }
}

///|
/// 对一个**可含负权**图实例运行「负权安全」算法子电池（Bellman-Ford /
/// Floyd-Warshall / typed_shortest_path）。这些算法对负权有定义行为：要么返回
/// 有效结果，要么以结构化错误（如 `NegativeCycle`）处理，绝不死循环（R17.3）。
///
/// 注意：Dijkstra / BFS / ALT / CH 要求非负权（负权下可能无定义甚至不终止），
/// 故有符号电池不纳入这些算法——这正是非负 / 有符号两套电池分流的原因。
fn fuzz_run_signed(g : FuzzGraph, seed : UInt64) -> FuzzRunReport {
  let adj = build_adj(g)
  let verdicts : Array[AlgoVerdict] = []
  if g.n >= 1 {
    let source = 0
    let target = g.n - 1
    verdicts.push(run_bellman_ford(adj, source, true))
    verdicts.push(run_floyd_warshall(adj, true))
    verdicts.push(run_typed_sp(adj, source, target, true))
  } else {
    verdicts.push(run_floyd_warshall(adj, true))
  }
  {
    seed,
    graph_n: g.n,
    graph_m: g.edges.length(),
    verdicts,
    robust: aggregate_robust(verdicts),
  }
}

///|
/// 模糊测试主入口（非负权 · R17.7 可复现）：以 `seed` 经
/// `@infra_pbt.rng_new` + `fuzz_graph_nonneg_gen(max_n, max_edges)` 确定性
/// 生成图实例，再运行完整非负权电池并返回裁决报告。
///
/// 「同种子 → 同图 → 同裁决」：相同 `seed` / 规模参数下结果逐字段一致，
/// 任一发现的失败实例据此复现（R17.4/R17.7）。
fn fuzz_run_from_seed_nonneg(
  seed : UInt64,
  max_n : Int,
  max_edges : Int,
) -> FuzzRunReport {
  let rng = @infra_pbt.rng_new(seed)
  let g = fuzz_graph_nonneg_gen(max_n, max_edges).generate(rng)
  fuzz_run_nonneg(g, seed)
}

///|
/// 模糊测试主入口（可含负权 · R17.7 可复现）：以 `seed` 经
/// `fuzz_graph_gen(max_n, max_edges)`（权可正可负）确定性生成图实例，再运行
/// 负权安全子电池并返回裁决报告。
fn fuzz_run_from_seed_signed(
  seed : UInt64,
  max_n : Int,
  max_edges : Int,
) -> FuzzRunReport {
  let rng = @infra_pbt.rng_new(seed)
  let g = fuzz_graph_gen(max_n, max_edges).generate(rng)
  fuzz_run_signed(g, seed)
}

///|
/// 非法参数结构化处理探针（R17.5）：以「空节点集」「越界源」「越界目标」三类
/// 非法输入驱动结构化入口 `typed_shortest_path`，断言其分别返回
/// `InvalidArgument` / `SourceNotFound` / `TargetNotFound` 而非崩溃。
/// 全部命中预期变体返回 `true`。
fn probe_invalid_args() -> Bool {
  let succ : (Int) -> Array[(Int, Double)] = fn(_u) { [] }
  // (1) 空节点集 → InvalidArgument。
  let empty_ok = match @graph.typed_shortest_path([], 0, 0, succ) {
    Err(@graph.PathError::InvalidArgument(_)) => true
    _ => false
  }
  // (2) 源不在节点集（节点仅 {0,1}，源取 5）→ SourceNotFound。
  let src_ok = match @graph.typed_shortest_path([0, 1], 5, 1, succ) {
    Err(@graph.PathError::SourceNotFound) => true
    _ => false
  }
  // (3) 目标不在节点集（节点仅 {0,1}，目标取 9）→ TargetNotFound。
  let tgt_ok = match @graph.typed_shortest_path([0, 1], 0, 9, succ) {
    Err(@graph.PathError::TargetNotFound) => true
    _ => false
  }
  empty_ok && src_ok && tgt_ok
}

///|
/// 以 `@infra_text.TextBuilder` 构建失败报告（禁止循环内字符串 `+` 拼接 ·
/// R22.4）：输出种子、图规模与各算法裁决，供失败定位与种子复现（R17.4）。
fn FuzzRunReport::describe(self : FuzzRunReport) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("FuzzRunReport(seed=")
  tb.push_str(self.seed.to_string())
  tb.push_str(", n=")
  tb.push_str(self.graph_n.to_string())
  tb.push_str(", m=")
  tb.push_str(self.graph_m.to_string())
  tb.push_str(", robust=")
  tb.push_str(self.robust.to_string())
  tb.push_str("):")
  for v in self.verdicts {
    tb.push_str(" [")
    tb.push_str(v.algo.to_string())
    tb.push_str(" robust=")
    tb.push_str(v.robust.to_string())
    tb.push_str("]")
  }
  tb.build()
}

// ───────────────────────── 单元测试：驱动逻辑自验 ─────────────────────────
//
// 以下为 task 16.1「驱动逻辑」自身的单元测试（确定性示例 + 代表性结构图），
// 验证 harness 能正确运行各算法、对有效结果与结构化错误作出鲁棒裁决，并能
// 由种子复现。Property 27（≥100 实例的属性测试）见 task 16.2
// （`prop_fuzz_robust_test.mbt`），本文件不重复实现。

///|
/// 非法参数结构化处理（R17.5）：空节点集 / 越界源 / 越界目标分别命中
/// `InvalidArgument` / `SourceNotFound` / `TargetNotFound`，不崩溃。
test "Feature: championship-v1-upgrade, task 16.1: invalid arguments handled structurally" {
  assert_true(probe_invalid_args())
}

///|
/// 非负权电池：对一批固定种子（覆盖多种结构类别）运行完整算法电池，断言全部
/// 算法在每个实例上均鲁棒（终止 + 有效结果或结构化错误），且报告携带正确种子。
test "Feature: championship-v1-upgrade, task 16.1: nonneg battery robust across seeds" {
  let seeds : Array[UInt64] = [
    1, 2, 3, 7, 11, 42, 99, 100, 256, 1000, 65537, 123456789,
  ]
  for s in seeds {
    let report = fuzz_run_from_seed_nonneg(s, 24, 80)
    // 全算法鲁棒；失败时输出报告（含种子）便于复现。
    assert_true(report.robust)
    assert_eq(report.seed, s)
    // 电池应覆盖 8 个算法（n>=1 时）或空图子集（n==0 时为 2 个）。
    assert_true(report.verdicts.length() == 8 || report.verdicts.length() == 2)
  }
}

///|
/// 有符号权电池（可含负权）：负权安全算法对一批固定种子均鲁棒——返回有效结果
/// 或以结构化错误（如 NegativeCycle）处理，绝不死循环 / 崩溃。
test "Feature: championship-v1-upgrade, task 16.1: signed battery robust across seeds" {
  let seeds : Array[UInt64] = [1, 2, 5, 13, 21, 42, 77, 128, 999, 31337]
  for s in seeds {
    let report = fuzz_run_from_seed_signed(s, 20, 60)
    assert_true(report.robust)
    assert_eq(report.seed, s)
  }
}

///|
/// 可复现性（R17.7）：相同种子 / 规模两次运行产出逐字段相同的报告
/// （以 `Show` 表示比较）。
test "Feature: championship-v1-upgrade, task 16.1: reports reproducible by seed" {
  let a = fuzz_run_from_seed_nonneg(20240621, 24, 80)
  let b = fuzz_run_from_seed_nonneg(20240621, 24, 80)
  assert_eq(a.to_string(), b.to_string())
}

///|
/// 代表性结构图（直接构造，绕开生成器）：空图 / 单节点自环 / 平行边 /
/// 多连通分量 / 线性链，逐一断言全算法鲁棒并核对结果分类。
test "Feature: championship-v1-upgrade, task 16.1: representative structural graphs robust" {
  // 空图：仅运行 Floyd-Warshall（空矩阵）+ 结构化非法参数路径。
  let empty = fuzz_run_nonneg({ n: 0, edges: [] }, 0)
  assert_true(empty.robust)
  assert_eq(empty.verdicts.length(), 2)

  // 单节点 + 自环：source == target == 0，各算法应返回平凡路径 [0] 或无解。
  let single = fuzz_run_nonneg({ n: 1, edges: [(0, 0, 2.5)] }, 0)
  assert_true(single.robust)

  // 平行边：0->1 两条不同权重；最短应取较小者。
  let parallel = fuzz_run_nonneg({ n: 2, edges: [(0, 1, 5.0), (0, 1, 1.0)] }, 0)
  assert_true(parallel.robust)

  // 多连通分量：{0,1} 与 {2,3} 互不连通；target=3 自 source=0 不可达。
  let multi = fuzz_run_nonneg({ n: 4, edges: [(0, 1, 1.0), (2, 3, 1.0)] }, 0)
  assert_true(multi.robust)

  // 线性链 0->1->2->3，权 1/2/3；source=0,target=3 可达，代价 6。
  let chain = fuzz_run_nonneg(
    { n: 4, edges: [(0, 1, 1.0), (1, 2, 2.0), (2, 3, 3.0)] },
    0,
  )
  assert_true(chain.robust)
}

///|
/// 验证「有效结果」校验确实生效：手工构造一条线性链，断言 Dijkstra /
/// typed_shortest_path 返回的路径被判为合法游走、且代价裁决为 PathFound。
test "Feature: championship-v1-upgrade, task 16.1: valid result classification on reachable chain" {
  let adj = build_adj({ n: 4, edges: [(0, 1, 1.0), (1, 2, 2.0), (2, 3, 3.0)] })
  // Dijkstra：0->3 可达，路径 [0,1,2,3]，代价 6.0。
  let dj = run_dijkstra(adj, 0, 3)
  assert_true(dj.robust)
  assert_eq(dj.kind, PathFound(3))
  // typed_shortest_path 同理。
  let tsp = run_typed_sp(adj, 0, 3, false)
  assert_true(tsp.robust)
  assert_eq(tsp.kind, PathFound(3))
  // BFS（无权）：跳数 3。
  let bfs = run_bfs(adj, 0, 3)
  assert_true(bfs.robust)
  assert_eq(bfs.kind, PathFound(3))
}

///|
/// 验证「明确无解 / 结构化错误」分类：构造不可达对，断言 BFS 返回 NoPath、
/// typed_shortest_path 返回 StructError（Unreachable），二者均判鲁棒。
test "Feature: championship-v1-upgrade, task 16.1: unreachable classified as NoPath / StructError" {
  // 两个孤立分量：0->1 与 2->3；查询 0 到 3 不可达。
  let adj = build_adj({ n: 4, edges: [(0, 1, 1.0), (2, 3, 1.0)] })
  let bfs = run_bfs(adj, 0, 3)
  assert_true(bfs.robust)
  assert_eq(bfs.kind, NoPath)
  let tsp = run_typed_sp(adj, 0, 3, false)
  assert_true(tsp.robust)
  assert_eq(tsp.kind, StructError)
}

///|
/// 验证负权环以结构化错误处理（R17.5）：构造可达负权环，断言 Bellman-Ford
/// 返回结构化错误（StructError）、typed_shortest_path 返回 NegativeCycle，
/// 二者均判鲁棒（不死循环、不崩溃）。
test "Feature: championship-v1-upgrade, task 16.1: negative cycle handled structurally" {
  // 0->1->2->1 形成可达负权环：1->2 权 -1，2->1 权 -1。
  let adj = build_adj({ n: 3, edges: [(0, 1, 1.0), (1, 2, -1.0), (2, 1, -1.0)] })
  let bf = run_bellman_ford(adj, 0, true)
  assert_true(bf.robust)
  assert_eq(bf.kind, StructError)
  // typed_shortest_path：0 到 2 路径上存在负权环 → NegativeCycle（结构化）。
  let tsp = run_typed_sp(adj, 0, 2, true)
  assert_true(tsp.robust)
  assert_eq(tsp.kind, StructError)
}

///|
/// 失败报告文本（describe）：包含种子与各算法标识，且非空（R17.4 复现线索）。
test "Feature: championship-v1-upgrade, task 16.1: describe emits seed and verdicts" {
  let report = fuzz_run_from_seed_nonneg(424242, 16, 40)
  let text = report.describe()
  assert_true(text.length() > 0)
  // 含种子与至少一个算法标识。
  assert_true(text.contains("424242"))
  assert_true(text.contains("Dijkstra"))
}
