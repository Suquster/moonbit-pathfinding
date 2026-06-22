// prop_frontier_diff_test.mbt —— task 19.3：前沿算法与基准算法的差分一致属性测试。
//
// 实现 **Property 10：前沿算法与基准算法差分一致**（Validates: Requirements 8.2, 8.3）：
//   * 在随机非负整数权有向图上，Contraction_Hierarchies（CH）与 ALT 对每组
//     随机源/目标查询返回的最短路径代价，必须与基准 Dijkstra **精确**相等
//     （整数权重 ⇒ 严格 `==`）；可达性判定亦须一致。 —— R8.2
//   * 在均匀代价网格上，Jump_Point_Search（JPS）与 A\* 对每组随机源/目标查询
//     返回的最短路径代价，必须在浮点偏差 ≤ 1e-9 内相等；可达性判定一致。 —— R8.3
//
// 生成器以 `@infra_pbt.Rng`（UInt64 种子）确定性驱动，外层迭代 128 次（≥100）；
// 每次迭代内枚举多组源/目标点对，使累计查询对数远超 100。
// 全程中文注释、`///|` 块风格；无 abort/todo!/panic 占位；循环内无字符串 `+` 拼接。

// ───────────────────────── 第一部分：CH / ALT vs Dijkstra（R8.2） ─────────────────────────

///|
/// 随机图规格：节点数 `n` 与整数非负权边表 `edges`（权 ≥ 1）。
struct FdGraphSpec {
  n : Int
  edges : Array[(Int, Int, Int)]
}

///|
/// 由规格构建邻接表后继函数（越界节点返回空，防御性）。
fn fd_succ(spec : FdGraphSpec) -> (Int) -> Array[(Int, Int)] {
  let adj : Array[Array[(Int, Int)]] = []
  for _i in 0..<spec.n {
    adj.push([])
  }
  for e in spec.edges {
    let (u, v, w) = e
    if u >= 0 && u < spec.n && v >= 0 && v < spec.n {
      adj[u].push((v, w))
    }
  }
  fn(u : Int) -> Array[(Int, Int)] {
    if u >= 0 && u < spec.n {
      adj[u]
    } else {
      []
    }
  }
}

///|
/// 节点列表 `[0, n)`。
fn fd_nodes(spec : FdGraphSpec) -> Array[Int] {
  let ns : Array[Int] = []
  for i in 0..<spec.n {
    ns.push(i)
  }
  ns
}

///|
/// 随机图规格生成器：`n ∈ [2, 7]`、边数 `∈ [0, 16]`、权 `∈ [1, 9]`。
/// 规模适中以保证 CH 预处理可在秒级完成。
fn fd_graph_gen() -> @infra_pbt.Gen[FdGraphSpec] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 7)
    let m = rng.next_range(0, 16)
    let edges : Array[(Int, Int, Int)] = []
    for _i in 0..<m {
      let u = rng.next_range(0, n - 1)
      let v = rng.next_range(0, n - 1)
      let w = rng.next_range(1, 9)
      edges.push((u, v, w))
    }
    { n, edges }
  })
}

///|
/// Feature: championship-v1-upgrade, Property 10: CH 与基准 Dijkstra 对每组查询代价精确相等且可达性一致
///
/// 在随机非负整数权图上，对全部 (源, 目标) 点对，`ch_query` 与 `@dir.dijkstra`
/// 的可达性必须一致；同时可达时整数最优代价必须 **严格相等**。
fn fd_prop_ch_matches_dijkstra(spec : FdGraphSpec) -> Bool {
  let succ = fd_succ(spec)
  let nodes = fd_nodes(spec)
  let g = ch_preprocess(nodes, succ)
  let mut ok = true
  for s in nodes {
    for t in nodes {
      let ch_r = ch_query(g, s, t)
      let dj_r = @dir.dijkstra(s, succ, fn(x) { x == t })
      match (ch_r, dj_r) {
        // 可达：整数权重 ⇒ 代价精确相等。
        (Some((_, ch_cost)), Some((_, dj_cost))) =>
          if ch_cost != dj_cost {
            ok = false
          }
        // 不可达：两者必须同时返回 None。
        (None, None) => ()
        // 可达性判定不一致 ⇒ 差分失败。
        _ => ok = false
      }
    }
  }
  ok
}

///|
/// Feature: championship-v1-upgrade, Property 10: ALT 与基准 Dijkstra 对每组查询代价精确相等且可达性一致
///
/// 在随机非负整数权图上，对全部 (源, 目标) 点对，`alt_query` 与 `@dir.dijkstra`
/// 的可达性必须一致；同时可达时整数最优代价必须 **严格相等**。
fn fd_prop_alt_matches_dijkstra(spec : FdGraphSpec) -> Bool {
  let succ = fd_succ(spec)
  let nodes = fd_nodes(spec)
  // 地标数取 min(n, 2)，规模适中。
  let num_landmarks = if spec.n < 2 { spec.n } else { 2 }
  let lm = alt_preprocess(nodes, succ, num_landmarks)
  let mut ok = true
  for s in nodes {
    for t in nodes {
      let alt_r = alt_query(lm, s, t, succ)
      let dj_r = @dir.dijkstra(s, succ, fn(x) { x == t })
      match (alt_r, dj_r) {
        (Some((_, alt_cost)), Some((_, dj_cost))) =>
          if alt_cost != dj_cost {
            ok = false
          }
        (None, None) => ()
        _ => ok = false
      }
    }
  }
  ok
}

// ───────────────────────── 第二部分：JPS vs A\*（R8.3） ─────────────────────────

///|
/// 均匀代价网格的差分容差：浮点最短路代价偏差不超过该阈值即视为相等（R8.3）。
let fd_eps : Double = 1.0e-9

///|
/// 与 `jps.mbt` 内部一致的对角步代价近似常量（√2 的截断近似）。
/// A\* 的后继代价与启发式均复用该常量，确保两算法在同一代价模型下比较。
let fd_diag_cost : Double = 1.4142135

///|
/// 随机网格规格：宽高、随机阻挡掩码与若干随机查询点对。
struct FdGridSpec {
  width : Int
  height : Int
  blocked : Array[Bool]
  pairs : Array[((Int, Int), (Int, Int))]
}

///|
/// 随机网格生成器：宽高 `∈ [2, 6]`，每格约 20% 概率为墙；随机 `∈ [2, 6]` 组
/// 查询点对（坐标落在网格范围内）。墙比例偏低以提升「存在路径」的样本占比。
fn fd_grid_gen() -> @infra_pbt.Gen[FdGridSpec] {
  @infra_pbt.Gen::new(fn(rng) {
    let width = rng.next_range(2, 6)
    let height = rng.next_range(2, 6)
    let blocked : Array[Bool] = []
    for _i in 0..<(width * height) {
      // 约 20% 为墙（next_range(0,4)==0）。
      blocked.push(rng.next_range(0, 4) == 0)
    }
    let k = rng.next_range(2, 6)
    let pairs : Array[((Int, Int), (Int, Int))] = []
    for _i in 0..<k {
      let sr = rng.next_range(0, height - 1)
      let sc = rng.next_range(0, width - 1)
      let gr = rng.next_range(0, height - 1)
      let gc = rng.next_range(0, width - 1)
      pairs.push(((sr, sc), (gr, gc)))
    }
    { width, height, blocked, pairs }
  })
}

///|
/// `(r, c)` 是否在网格内且非墙。越界视为墙（与 JPS 的 `walkable` 语义一致）。
fn fd_grid_walkable(spec : FdGridSpec, r : Int, c : Int) -> Bool {
  if r < 0 || r >= spec.height || c < 0 || c >= spec.width {
    return false
  }
  !spec.blocked[r * spec.width + c]
}

///|
/// 构建与 JPS 完全相同的 8 向移动模型后继函数：基数步代价 1.0、对角步代价
/// `fd_diag_cost`；目标格可走即可移动（与 `jps.mbt` 的 `jump` 一致，不额外
/// 施加禁止切角约束），以保证 A\* 与 JPS 处于同一代价模型下做差分比较。
fn fd_astar_succ(
  spec : FdGridSpec,
) -> ((Int, Int)) -> Array[((Int, Int), Double)] {
  fn(node : (Int, Int)) -> Array[((Int, Int), Double)] {
    let (r, c) = node
    let dirs = [
      (-1, 0),
      (1, 0),
      (0, -1),
      (0, 1),
      (-1, -1),
      (-1, 1),
      (1, -1),
      (1, 1),
    ]
    let out : Array[((Int, Int), Double)] = []
    for d in dirs {
      let (dr, dc) = d
      let nr = r + dr
      let nc = c + dc
      if fd_grid_walkable(spec, nr, nc) {
        let cost = if dr != 0 && dc != 0 { fd_diag_cost } else { 1.0 }
        out.push(((nr, nc), cost))
      }
    }
    out
  }
}

///|
/// Octile 距离启发式——8 向网格 A\* 的标准可采纳估计，复用 `fd_diag_cost`
/// 常量以与 JPS 的代价模型保持一致。
fn fd_octile(a : (Int, Int), b : (Int, Int)) -> Double {
  let (ar, ac) = a
  let (br, bc) = b
  let dx = (br - ar).abs().to_double()
  let dy = (bc - ac).abs().to_double()
  let big = if dx > dy { dx } else { dy }
  let small = if dx > dy { dy } else { dx }
  big + (fd_diag_cost - 1.0) * small
}

///|
/// Feature: championship-v1-upgrade, Property 10: JPS 与基准 A\* 对每组查询代价偏差 ≤ 1e-9 且可达性一致
///
/// 在随机均匀代价网格上，对每组（起点、终点均可走的）查询点对，`jps` 与
/// `@dir.astar`（同一 8 向代价模型 + Octile 启发式）的可达性必须一致；
/// 同时可达时浮点最优代价偏差不超过 `fd_eps`（1e-9）。
fn fd_prop_jps_matches_astar(spec : FdGridSpec) -> Bool {
  match JPSGrid::new(spec.width, spec.height, spec.blocked) {
    // 非法维度（掩码长度不符）由构造器拒绝，跳过该实例。
    None => true
    Some(grid) => {
      let succ = fd_astar_succ(spec)
      let mut ok = true
      for pair in spec.pairs {
        let (s, t) = pair
        let (sr, sc) = s
        let (tr, tc) = t
        // 仅比较起点与终点均可走的点对：JPS 对不可走端点直接返回 None，
        // 而 A\* 不校验起点是否为墙，故此类点对不在差分语义范围内。
        if !fd_grid_walkable(spec, sr, sc) || !fd_grid_walkable(spec, tr, tc) {
          continue
        }
        let jps_r = jps(grid, s, t)
        let astar_r = @dir.astar(s, succ, fn(n) { fd_octile(n, t) }, fn(n) {
          n == t
        })
        match (jps_r, astar_r) {
          // 可达：浮点代价偏差 ≤ 1e-9。
          (Some((_, jc)), Some((_, ac))) =>
            if (jc - ac).abs() > fd_eps {
              ok = false
            }
          // 不可达：两者必须同时返回 None。
          (None, None) => ()
          // 可达性判定不一致 ⇒ 差分失败。
          _ => ok = false
        }
      }
      ok
    }
  }
}

// ───────────────────────── 属性测试入口（外层 ≥100 迭代） ─────────────────────────

///|
/// 属性入口：CH 与 Dijkstra 差分一致（128 次迭代 ≥100，每次枚举全部点对）。
test "Feature: championship-v1-upgrade, Property 10: CH matches Dijkstra cost" {
  let ok = @infra_pbt.holds_for_all(
    fd_graph_gen(),
    fd_prop_ch_matches_dijkstra,
    iters=128,
  )
  assert_true(ok)
}

///|
/// 属性入口：ALT 与 Dijkstra 差分一致（128 次迭代 ≥100，每次枚举全部点对）。
test "Feature: championship-v1-upgrade, Property 10: ALT matches Dijkstra cost" {
  let ok = @infra_pbt.holds_for_all(
    fd_graph_gen(),
    fd_prop_alt_matches_dijkstra,
    iters=128,
  )
  assert_true(ok)
}

///|
/// 属性入口：JPS 与 A\* 差分一致（128 次迭代 ≥100，每次多组点对）。
test "Feature: championship-v1-upgrade, Property 10: JPS matches A-star cost" {
  let ok = @infra_pbt.holds_for_all(
    fd_grid_gen(),
    fd_prop_jps_matches_astar,
    iters=128,
  )
  assert_true(ok)
}

// ───────────────────────── 确定性单元锚点 ─────────────────────────

///|
/// 单元锚点：线性链上 CH/ALT 与 Dijkstra 代价完全一致（整数精确）。
test "Feature: championship-v1-upgrade, Property 10: CH/ALT vs Dijkstra chain anchor" {
  let nodes = [0, 1, 2, 3, 4]
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 2), (2, 5)],
    [(2, 1)],
    [(3, 3)],
    [(4, 1)],
    [],
  ]
  let succ = fn(n : Int) { adj[n] }
  let g = ch_preprocess(nodes, succ)
  let lm = alt_preprocess(nodes, succ, 2)
  for t in nodes {
    let dj = @dir.dijkstra(0, succ, fn(x) { x == t })
    let ch_r = ch_query(g, 0, t)
    let alt_r = alt_query(lm, 0, t, succ)
    match (dj, ch_r, alt_r) {
      (Some((_, d)), Some((_, c)), Some((_, a))) => {
        assert_eq(c, d)
        assert_eq(a, d)
      }
      (None, None, None) => assert_true(true)
      _ => assert_true(false)
    }
  }
}

///|
/// 单元锚点：开阔 5×5 网格上 JPS 与 A\* 代价一致（对角线最短路）。
test "Feature: championship-v1-upgrade, Property 10: JPS vs A-star open grid anchor" {
  let spec : FdGridSpec = {
    width: 5,
    height: 5,
    blocked: Array::make(25, false),
    pairs: [((0, 0), (4, 4)), ((0, 0), (0, 4)), ((2, 2), (2, 2))],
  }
  // 5×5 全开网格：掩码长度恒为 25，构造必然成功；以 match 安全解构，
  // 不可能的 None 分支以断言失败兜底（不使用 abort 占位）。
  match JPSGrid::new(spec.width, spec.height, spec.blocked) {
    None => assert_true(false)
    Some(grid) => {
      let succ = fd_astar_succ(spec)
      for pair in spec.pairs {
        let (s, t) = pair
        let jps_r = jps(grid, s, t)
        let astar_r = @dir.astar(s, succ, fn(n) { fd_octile(n, t) }, fn(n) {
          n == t
        })
        match (jps_r, astar_r) {
          (Some((_, jc)), Some((_, ac))) =>
            assert_true((jc - ac).abs() <= fd_eps)
          (None, None) => assert_true(true)
          _ => assert_true(false)
        }
      }
    }
  }
}
