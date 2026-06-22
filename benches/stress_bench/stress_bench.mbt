// stress_bench.mbt —— 10k 节点大规模压力测试驱动（任务 20.1）。
//
// 设计依据：design.md §2.5「10k 压力测试设计（R7）」与 requirements R7.1–R7.5。
//
// 拓扑选择：采用 **4-连通加权网格**（节点编号 `r*side + c`），节点数恰为 `side²`。
// 取 `side = 100` 即 10000 节点。网格平面、低度数（≤4），构造为 O(n) 线性，
// 任意源/目标在无障碍时连通，且天然提供可采纳的曼哈顿启发式供 A\* 使用。
//
// 超时语义说明（R7.5）：MoonBit 为单线程同步执行，无法在算法运行中途抢占式中断，
// 因此「60s 超时」实现为**事后判定**——以单调时钟测量单次算法调用耗时，若超过 60s
// 上界即将该用例标记为失败并记录结构化诊断（而非无限挂起等待）。这是无异步取消
// 机制时的标准做法：驱动本身始终在有限时间内返回判定结果。

// ───────────────────────────── 命名常量（禁止 magic number） ─────────────────────────────

///|
/// 完整压力规模的网格边长：`stress_grid_side² = 10000` 节点（R7.1）。
pub let stress_grid_side : Int = 100

///|
/// smoke 规模的网格边长（`moon test` 默认运行，debug / wasm 下秒级完成）。
pub let smoke_grid_side : Int = 20

///|
/// 网格边权上界：权重在 `[1, stress_max_weight]` 内均匀采样。最小权重为 1，
/// 保证「曼哈顿步数」是任意路径代价的下界，从而 A\* 启发式可采纳。
pub let stress_max_weight : Int = 9

///|
/// 60s 超时上界（纳秒）。`@bench.monotonic_clock_end` 返回纳秒量级 `Double`，
/// 故以 `60_000_000_000.0` ns = 60000 ms = 60 s 作为判定阈值（R7.1 / R7.5）。
pub let stress_timeout_ns : Double = 60000000000.0

///|
/// 代价一致性容差（R7.3）。整数权重下偏差恒为 0，此阈值用于统一以浮点口径比较。
pub let stress_cost_epsilon : Double = 1.0e-9

///|
/// 图构造随机种子（确定性，保证三后端逐元素一致）。
pub let stress_seed : Int = 0x5715CE

// ───────────────────────────── 确定性随机源 ─────────────────────────────

///|
/// 自包含线性同余发生器（与既有 `benches/*_bench` 一致），保证可复现。
priv struct Lcg {
  mut state : Int
}

///|
fn Lcg::new(seed : Int) -> Lcg {
  let s = if seed <= 0 { (-seed).lor(1) } else { seed }
  { state: s.land(0x7fffffff) }
}

///|
fn Lcg::next(self : Lcg) -> Int {
  let v = (self.state * 1103515245 + 12345).land(0x7fffffff)
  self.state = v
  v
}

// ───────────────────────────── 网格图构造 ─────────────────────────────

///|
/// 构造 `side × side` 的 4-连通加权网格邻接表。
///
/// - 节点编号 `r*side + c`，节点数 `side²`。
/// - 向右、向下连边并补对向边（无向，对向边共享同一随机权重 `[1, max_w]`）。
/// - `blocked[id] == true` 的单元格不参与任何连边（用于构造不可达场景）。
fn build_grid_graph(
  seed : Int,
  side : Int,
  max_w : Int,
  blocked : Array[Bool],
) -> Array[Array[(Int, Int)]] {
  let n = side * side
  let rng = Lcg::new(seed)
  let adj : Array[Array[(Int, Int)]] = Array::makei(n, fn(_) { [] })
  for r in 0..<side {
    for c in 0..<side {
      let u = r * side + c
      if c + 1 < side {
        let v = r * side + (c + 1)
        let w = 1 + rng.next() % max_w
        // 权重先采样以保持随机序列稳定，再依据障碍决定是否落边。
        if !blocked[u] && !blocked[v] {
          adj[u].push((v, w))
          adj[v].push((u, w))
        }
      }
      if r + 1 < side {
        let v = (r + 1) * side + c
        let w = 1 + rng.next() % max_w
        if !blocked[u] && !blocked[v] {
          adj[u].push((v, w))
          adj[v].push((u, w))
        }
      }
    }
  }
  adj
}

///|
/// 由带权邻接表派生无权邻接表（仅取邻居标识），供 BFS 复用，避免每次查询重复分配。
fn derive_unweighted_adj(adj : Array[Array[(Int, Int)]]) -> Array[Array[Int]] {
  let n = adj.length()
  let uadj : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
  for u in 0..<n {
    let row = adj[u]
    let out = uadj[u]
    for pair in row {
      out.push(pair.0)
    }
  }
  uadj
}

///|
/// 全 `false` 障碍掩码（无障碍场景：任意源/目标可达）。
fn open_mask(n : Int) -> Array[Bool] {
  Array::make(n, false)
}

///|
/// 隔离目标的障碍掩码：封锁目标在网格上的 4 个邻居，使目标入度为 0（不可达场景）。
fn isolate_target_mask(side : Int, target : Int) -> Array[Bool] {
  let n = side * side
  let mask = Array::make(n, false)
  let r = target / side
  let c = target % side
  if c + 1 < side {
    mask[r * side + (c + 1)] = true
  }
  if c - 1 >= 0 {
    mask[r * side + (c - 1)] = true
  }
  if r + 1 < side {
    mask[(r + 1) * side + c] = true
  }
  if r - 1 >= 0 {
    mask[(r - 1) * side + c] = true
  }
  mask
}

// ───────────────────────────── 图不变性校验（图未被修改） ─────────────────────────────

///|
/// 计算带权邻接表的顺序敏感校验和。算法运行前后两次取值相等即视为输入图未被修改
/// （R7.1）。使用 31 进制滚动哈希并按位与掩码保持三后端数值稳定。
fn graph_checksum(adj : Array[Array[(Int, Int)]]) -> Int {
  let mask = 0x7fffffff
  let mut h = 0x1F2E3D4C
  for u in 0..<adj.length() {
    h = (h * 31 + u).land(mask)
    for pair in adj[u] {
      let (v, w) = pair
      h = (h * 31 + v).land(mask)
      h = (h * 31 + w).land(mask)
    }
  }
  h
}

// ───────────────────────────── 路径合法性 / 代价一致性校验 ─────────────────────────────

///|
/// 在带权邻接表中查找有向边 `u -> v` 的权重；不存在返回 `None`。度数 ≤4，线性扫描即可。
fn find_edge_weight(adj : Array[Array[(Int, Int)]], u : Int, v : Int) -> Int? {
  if u < 0 || u >= adj.length() {
    return None
  }
  for pair in adj[u] {
    if pair.0 == v {
      return Some(pair.1)
    }
  }
  None
}

///|
/// 校验带权路径（Dijkstra / A\*）：返回 `(path_valid, cost_consistent)`。
///
/// - `path_valid`：路径非空、首 = 源、末 = 目标，且每条相邻对在图中存在对应边（R7.2/R7.3）。
/// - `cost_consistent`：返回代价与沿路径各边权重之和的偏差 ≤ `stress_cost_epsilon`（R7.3）。
fn validate_weighted_path(
  adj : Array[Array[(Int, Int)]],
  path : Array[Int],
  cost : Int,
  source : Int,
  target : Int,
) -> (Bool, Bool) {
  let len = path.length()
  if len == 0 {
    return (false, false)
  }
  let endpoints_ok = path[0] == source && path[len - 1] == target
  let mut edges_ok = true
  let mut sum = 0
  for i in 0..<(len - 1) {
    match find_edge_weight(adj, path[i], path[i + 1]) {
      Some(w) => sum = sum + w
      None => edges_ok = false
    }
  }
  let path_valid = endpoints_ok && edges_ok
  let cost_consistent = (cost.to_double() - sum.to_double()).abs() <=
    stress_cost_epsilon
  (path_valid, cost_consistent)
}

///|
/// 校验无权路径（BFS）：路径非空、首 = 源、末 = 目标，且每条相邻对在图中存在边
/// （R7.2）。BFS 不返回代价，故代价一致性对其恒为 N/A（在 outcome 中记为 true）。
fn validate_unweighted_path(
  adj : Array[Array[(Int, Int)]],
  path : Array[Int],
  source : Int,
  target : Int,
) -> Bool {
  let len = path.length()
  if len == 0 {
    return false
  }
  if !(path[0] == source && path[len - 1] == target) {
    return false
  }
  for i in 0..<(len - 1) {
    if find_edge_weight(adj, path[i], path[i + 1]) is None {
      return false
    }
  }
  true
}

// ───────────────────────────── 计时原语 ─────────────────────────────

///|
/// 测量一次 `work` 的单调时钟耗时（纳秒量级 `Double`，与既有原生基准同源时间）。
fn elapsed(work : () -> Unit) -> Double {
  let ts = @bench.monotonic_clock_start()
  work()
  @bench.monotonic_clock_end(ts)
}

// ───────────────────────────── 结构化结果模型（禁止字符串模拟） ─────────────────────────────

///|
/// 被压力测试覆盖的算法种类（类型安全枚举，禁止以字符串模拟结构化数据）。
pub(all) enum StressAlgo {
  Bfs
  Dijkstra
  Astar
} derive(Eq, Show)

///|
/// 算法可读名称（用于诊断渲染）。
pub fn StressAlgo::name(self : StressAlgo) -> String {
  match self {
    Bfs => "BFS"
    Dijkstra => "Dijkstra"
    Astar => "A*"
  }
}

///|
/// 单个压力测试用例的结构化结果与诊断要素（R7.1–R7.5 逐项判定）。
pub(all) struct StressOutcome {
  algo : StressAlgo
  source : Int
  target : Int
  graph_size : Int
  /// 该用例预期目标是否可达（无障碍场景为真，隔离目标场景为假）。
  expect_reachable : Bool
  /// 算法实际返回非空路径（即判定可达）。
  reachable : Bool
  /// 是否在 60s 超时上界内终止（R7.5）。
  terminated_in_budget : Bool
  /// 单次算法调用实测耗时（纳秒量级）。
  elapsed_ns : Double
  /// 返回路径结构合法（R7.2）。不可达用例此项记为 true（N/A）。
  path_valid : Bool
  /// 返回代价与路径权重和一致（R7.3）。BFS 与不可达用例此项记为 true（N/A）。
  cost_consistent : Bool
  /// 算法运行前后输入图校验和一致，即输入图未被修改（R7.1）。
  graph_unmodified : Bool
  /// 综合判定：该用例是否通过全部相关验收标准。
  passed : Bool
}

///|
/// 依据各检查项与预期可达性聚合综合判定 `passed`。
fn StressOutcome::evaluate(
  algo : StressAlgo,
  source : Int,
  target : Int,
  graph_size : Int,
  expect_reachable : Bool,
  reachable : Bool,
  elapsed_ns : Double,
  path_valid : Bool,
  cost_consistent : Bool,
  graph_unmodified : Bool,
) -> StressOutcome {
  let terminated_in_budget = elapsed_ns <= stress_timeout_ns
  // 通用前置：必须在预算内终止且不修改输入图。
  let base_ok = terminated_in_budget && graph_unmodified
  let passed = if expect_reachable {
    // 可达：返回非空合法路径且代价一致（R7.2/R7.3）。
    base_ok && reachable && path_valid && cost_consistent
  } else {
    // 不可达：必须返回明确无解（空路径 / None），即 reachable 为假（R7.4）。
    base_ok && !reachable
  }
  {
    algo,
    source,
    target,
    graph_size,
    expect_reachable,
    reachable,
    terminated_in_budget,
    elapsed_ns,
    path_valid,
    cost_consistent,
    graph_unmodified,
    passed,
  }
}

///|
/// 渲染单个用例的结构化诊断字符串（用 `@infra_text.TextBuilder`，禁止循环内 `+`）。
/// 用于 R7.5 / R7.1 失败时输出可定位诊断（算法、源/目标、各检查项、耗时）。
pub fn StressOutcome::diagnostic(self : StressOutcome) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("[stress] algo=")
  tb.push_str(self.algo.name())
  tb.push_str(" n=")
  tb.push_str(self.graph_size.to_string())
  tb.push_str(" src=")
  tb.push_str(self.source.to_string())
  tb.push_str(" dst=")
  tb.push_str(self.target.to_string())
  tb.push_str(" expect_reachable=")
  tb.push_str(self.expect_reachable.to_string())
  tb.push_str(" reachable=")
  tb.push_str(self.reachable.to_string())
  tb.push_str(" terminated_in_budget=")
  tb.push_str(self.terminated_in_budget.to_string())
  tb.push_str(" elapsed_ns=")
  tb.push_str(self.elapsed_ns.to_string())
  tb.push_str(" path_valid=")
  tb.push_str(self.path_valid.to_string())
  tb.push_str(" cost_consistent=")
  tb.push_str(self.cost_consistent.to_string())
  tb.push_str(" graph_unmodified=")
  tb.push_str(self.graph_unmodified.to_string())
  tb.push_str(" passed=")
  tb.push_str(self.passed.to_string())
  tb.build()
}

// ───────────────────────────── 单算法用例驱动 ─────────────────────────────

///|
/// 在给定带权图上运行一次 BFS 用例并产出结构化判定（不修改输入图）。
fn run_bfs_case(
  adj : Array[Array[(Int, Int)]],
  uadj : Array[Array[Int]],
  source : Int,
  target : Int,
  expect_reachable : Bool,
) -> StressOutcome {
  let before = graph_checksum(adj)
  let mut result : Array[Int]? = None
  let dt = elapsed(fn() {
    result = @uw.bfs(source, fn(u) { uadj[u] }, fn(v) { v == target })
  })
  let after = graph_checksum(adj)
  let graph_unmodified = before == after
  let (reachable, path_valid) = match result {
    Some(path) => (true, validate_unweighted_path(adj, path, source, target))
    None => (false, true)
  }
  StressOutcome::evaluate(
    Bfs,
    source,
    target,
    adj.length(),
    expect_reachable,
    reachable,
    dt,
    path_valid,
    // BFS 无代价，代价一致性 N/A。
    true,
    graph_unmodified,
  )
}

///|
/// 在给定带权图上运行一次 Dijkstra 用例并产出结构化判定（不修改输入图）。
fn run_dijkstra_case(
  adj : Array[Array[(Int, Int)]],
  source : Int,
  target : Int,
  expect_reachable : Bool,
) -> StressOutcome {
  let before = graph_checksum(adj)
  let mut result : (Array[Int], Int)? = None
  let dt = elapsed(fn() {
    result = @dir.dijkstra(source, fn(u) { adj[u] }, fn(v) { v == target })
  })
  let after = graph_checksum(adj)
  let graph_unmodified = before == after
  let (reachable, path_valid, cost_consistent) = match result {
    Some((path, cost)) => {
      let (pv, cc) = validate_weighted_path(adj, path, cost, source, target)
      (true, pv, cc)
    }
    None => (false, true, true)
  }
  StressOutcome::evaluate(
    Dijkstra,
    source,
    target,
    adj.length(),
    expect_reachable,
    reachable,
    dt,
    path_valid,
    cost_consistent,
    graph_unmodified,
  )
}

///|
/// 在给定带权图上运行一次 A\* 用例并产出结构化判定（不修改输入图）。
/// 启发式采用网格曼哈顿距离（步数）；因边权 ≥ 1，步数为任意路径代价的下界，可采纳。
fn run_astar_case(
  adj : Array[Array[(Int, Int)]],
  side : Int,
  source : Int,
  target : Int,
  expect_reachable : Bool,
) -> StressOutcome {
  let tr = target / side
  let tc = target % side
  let heuristic = fn(u : Int) -> Int {
    let ur = u / side
    let uc = u % side
    (ur - tr).abs() + (uc - tc).abs()
  }
  let before = graph_checksum(adj)
  let mut result : (Array[Int], Int)? = None
  let dt = elapsed(fn() {
    result = @dir.astar(source, fn(u) { adj[u] }, heuristic, fn(v) {
      v == target
    })
  })
  let after = graph_checksum(adj)
  let graph_unmodified = before == after
  let (reachable, path_valid, cost_consistent) = match result {
    Some((path, cost)) => {
      let (pv, cc) = validate_weighted_path(adj, path, cost, source, target)
      (true, pv, cc)
    }
    None => (false, true, true)
  }
  StressOutcome::evaluate(
    Astar,
    source,
    target,
    adj.length(),
    expect_reachable,
    reachable,
    dt,
    path_valid,
    cost_consistent,
    graph_unmodified,
  )
}

// ───────────────────────────── 套件驱动与报告 ─────────────────────────────

///|
/// 一次压力测试套件的聚合结果。
pub(all) struct StressReport {
  grid_side : Int
  cases : Array[StressOutcome]
}

///|
/// 套件内全部用例均通过即返回真（R7.1–R7.5 全绿）。
pub fn StressReport::all_passed(self : StressReport) -> Bool {
  for c in self.cases {
    if !c.passed {
      return false
    }
  }
  true
}

///|
/// 收集所有未通过用例的结构化诊断（每行一个用例），供失败时定位。
pub fn StressReport::failure_diagnostics(self : StressReport) -> String {
  let tb = @infra_text.TextBuilder::new()
  let mut first = true
  for c in self.cases {
    if !c.passed {
      if !first {
        tb.push_char('\n')
      }
      tb.push_str(c.diagnostic())
      first = false
    }
  }
  tb.build()
}

///|
/// 运行完整压力测试套件：在 `side × side` 网格上，对 BFS / Dijkstra / A\* 各运行
/// 一个「可达」用例（无障碍，角到角）与一个「不可达」用例（隔离目标），共 6 个用例。
///
/// 覆盖：R7.1（终止/不改图/不 panic）、R7.2（边存在）、R7.3（端点/代价一致）、
/// R7.4（不可达返回无解）、R7.5（超时事后判定）。
pub fn run_stress_suite(side : Int) -> StressReport {
  let n = side * side
  // 源固定为左上角 0，目标固定为右下角 n-1。
  let source = 0
  let target = n - 1

  // —— 可达场景：无障碍加权网格，角到角必然可达。 ——
  let open_adj = build_grid_graph(
    stress_seed,
    side,
    stress_max_weight,
    open_mask(n),
  )
  let open_uadj = derive_unweighted_adj(open_adj)

  // —— 不可达场景：隔离目标（封锁其全部网格邻居），目标入度为 0。 ——
  let blocked = isolate_target_mask(side, target)
  let iso_adj = build_grid_graph(stress_seed, side, stress_max_weight, blocked)
  let iso_uadj = derive_unweighted_adj(iso_adj)

  let cases : Array[StressOutcome] = [
    // 可达用例。
    run_bfs_case(open_adj, open_uadj, source, target, true),
    run_dijkstra_case(open_adj, source, target, true),
    run_astar_case(open_adj, side, source, target, true),
    // 不可达用例。
    run_bfs_case(iso_adj, iso_uadj, source, target, false),
    run_dijkstra_case(iso_adj, source, target, false),
    run_astar_case(iso_adj, side, source, target, false),
  ]
  { grid_side: side, cases }
}

// ───────────────────────────── smoke / 完整规模入口 ─────────────────────────────
//
// 完整 10k 规模采集放在 `@bench.T` 基准块（仅 `moon bench` 执行）；普通 `moon test`
// 仅运行下方较小规模 smoke 用例以验证驱动结构正确，避免 debug / wasm 下拖垮门禁。

///|
/// smoke：在较小规模网格上验证压力测试驱动结构正确——6 个用例全部通过，
/// 且可达用例确实返回合法路径、不可达用例确实返回无解。
test "smoke: stress suite on small grid passes all R7 checks" {
  let report = run_stress_suite(smoke_grid_side)
  // 用例数恒为 6（3 算法 × {可达, 不可达}）。
  assert_eq(report.cases.length(), 6)
  if !report.all_passed() {
    println(report.failure_diagnostics())
  }
  assert_true(report.all_passed())
  // 进一步断言场景语义：前 3 个为可达、后 3 个为不可达。
  for i in 0..<3 {
    let c = report.cases[i]
    assert_true(c.expect_reachable && c.reachable)
    assert_true(c.terminated_in_budget && c.graph_unmodified)
  }
  for i in 3..<6 {
    let c = report.cases[i]
    assert_true(!c.expect_reachable && !c.reachable)
    assert_true(c.terminated_in_budget && c.graph_unmodified)
  }
}

///|
/// 完整 10k 规模压力测试采集（仅 `moon bench` 执行）。在 10000 节点网格上对
/// BFS / Dijkstra / A\* 运行可达与不可达用例，断言全部通过，并以 `@bench.T`
/// 测点登记一次完整套件耗时。
test "bench: stress suite on 10k-node grid (BFS/Dijkstra/A*)" (b : @bench.T) {
  let report = run_stress_suite(stress_grid_side)
  if !report.all_passed() {
    println(report.failure_diagnostics())
  }
  assert_true(report.all_passed())
  b.bench(name="stress_suite_10k_grid", fn() {
    b.keep(run_stress_suite(stress_grid_side).all_passed())
  })
}
