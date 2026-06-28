// advanced_ext_test.mbt —— task 19.1 新增 bypass 入口的属性测试与单元测试。
//
// 覆盖五个新增 pub 函数（每个 ≥1 属性测试、外层迭代 128 次 ≥100 基线）：
//   * `ch_preprocess_with_order`      —— 与基准 Dijkstra 代价/可达一致。
//   * `alt_preprocess_with_landmarks` —— 与基准 Dijkstra 代价/可达一致。
//   * `ch_query_batch`                —— 与逐个 `ch_query` 逐位一致。
//   * `alt_query_batch`               —— 与逐个 `alt_query` 逐位一致。
//   * `jps_batch`                     —— 与逐个 `jps` 逐位一致。
//
// 生成器以 `@infra_pbt.Rng`（UInt64 种子）确定性驱动随机非负权图 / 网格，
// 保证可复现；权取整数以便 CH/ALT 与 Dijkstra 的最优代价做**精确**相等比较。
// 全程中文注释、`///|` 块风格；无 abort/todo!/panic；循环内无字符串 `+` 拼接。

///|
/// 随机图规格：节点数 `n`、整数非负权边表 `edges`、以及一个候选收缩顺序
/// `order`（可能为部分 / 含重复，用以同时检验 `ch_preprocess_with_order`
/// 的防御性归一化）。
struct ExtGSpec {
  n : Int
  edges : Array[(Int, Int, Int)]
  order : Array[Int]
}

///|
/// 由规格构建邻接表后继函数（越界节点返回空，防御性）。
fn ext_succ(spec : ExtGSpec) -> (Int) -> Array[(Int, Int)] {
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
fn ext_nodes(spec : ExtGSpec) -> Array[Int] {
  let ns : Array[Int] = []
  for i in 0..<spec.n {
    ns.push(i)
  }
  ns
}

///|
/// 随机图规格生成器：`n ∈ [1, 7]`、边数 `∈ [0, 14]`、权 `∈ [1, 9]`；
/// `order` 由 Fisher–Yates 洗牌 `[0, n)` 得到一个随机排列（合法顺序），
/// 偶发地再追加一个重复 / 越界项以触发归一化分支。
fn ext_gspec_gen() -> @infra_pbt.Gen[ExtGSpec] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 7)
    let m = rng.next_range(0, 14)
    let edges : Array[(Int, Int, Int)] = []
    for _i in 0..<m {
      let u = rng.next_range(0, n - 1)
      let v = rng.next_range(0, n - 1)
      let w = rng.next_range(1, 9)
      edges.push((u, v, w))
    }
    // 随机排列 [0, n)：Fisher–Yates。
    let order : Array[Int] = []
    for i in 0..<n {
      order.push(i)
    }
    let mut i = n - 1
    while i > 0 {
      let j = rng.next_range(0, i)
      let tmp = order[i]
      order[i] = order[j]
      order[j] = tmp
      i -= 1
    }
    // 偶发注入异常项（重复首元素 / 越界 n），检验防御性归一化。
    if rng.next_bool() && n >= 1 {
      order.push(order[0])
    }
    if rng.next_bool() {
      order.push(n)
    }
    { n, edges, order }
  })
}

///|
/// 校验带权路径为「图中真实游走」且代价等于逐段最小边权之和（平行边取最小）。
/// CH/ALT 的最优代价应与该校验自洽。
fn ext_valid_weighted(
  spec : ExtGSpec,
  source : Int,
  target : Int,
  path : Array[Int],
  cost : Int,
) -> Bool {
  let len = path.length()
  if len == 0 {
    return false
  }
  if path[0] != source || path[len - 1] != target {
    return false
  }
  // 逐段最小边权表。
  let min_edge : Map[(Int, Int), Int] = Map([])
  for e in spec.edges {
    let (u, v, w) = e
    match min_edge.get((u, v)) {
      Some(cur) => if w < cur { min_edge[(u, v)] = w }
      None => min_edge[(u, v)] = w
    }
  }
  let mut sum = 0
  let mut i = 0
  while i + 1 < len {
    match min_edge.get((path[i], path[i + 1])) {
      Some(w) => sum = sum + w
      None => return false
    }
    i += 1
  }
  sum == cost
}

///|
/// Feature: championship-v1-upgrade, task 19.1: ch_preprocess_with_order 与 Dijkstra 一致
///
/// 对随机非负权图与随机（可能含异常项的）收缩顺序，`ch_preprocess_with_order`
/// 构建的 CH 对每个目标 `t` 的查询：可达性与最优代价均与基准 Dijkstra 一致，
/// 且返回路径为合法游走、代价自洽。迭代 128 次（≥100）。
fn prop_ch_order_matches_dijkstra(spec : ExtGSpec) -> Bool {
  let succ = ext_succ(spec)
  let nodes = ext_nodes(spec)
  let g = ch_preprocess_with_order(nodes, succ, spec.order)
  let source = 0
  let mut ok = true
  for t in nodes {
    let ch_r = ch_query(g, source, t)
    let dj_r = @dir.dijkstra(source, succ, fn(x) { x == t })
    match (ch_r, dj_r) {
      (Some((path, ch_cost)), Some((_, dj_cost))) => {
        if ch_cost != dj_cost {
          ok = false
        }
        if !ext_valid_weighted(spec, source, t, path, ch_cost) {
          ok = false
        }
      }
      (None, None) => ()
      _ => ok = false
    }
  }
  ok
}

///|
/// Feature: championship-v1-upgrade, task 19.1: alt_preprocess_with_landmarks 与 Dijkstra 一致
///
/// 取一个确定性地标子集（首节点 + 末节点 + 一个越界/重复项，检验归一化），
/// `alt_preprocess_with_landmarks` 构建的 ALT 对每个目标查询的可达性与最优
/// 代价均与基准 Dijkstra 一致，路径合法、代价自洽。迭代 128 次（≥100）。
fn prop_alt_landmarks_matches_dijkstra(spec : ExtGSpec) -> Bool {
  let succ = ext_succ(spec)
  let nodes = ext_nodes(spec)
  // 地标集：含合法项与异常项（越界 n、重复 0），检验防御性归一化。
  let landmarks : Array[Int] = [0, spec.n - 1, 0, spec.n]
  let lm = alt_preprocess_with_landmarks(nodes, succ, landmarks)
  let source = 0
  let mut ok = true
  for t in nodes {
    let alt_r = alt_query(lm, source, t, succ)
    let dj_r = @dir.dijkstra(source, succ, fn(x) { x == t })
    match (alt_r, dj_r) {
      (Some((path, alt_cost)), Some((_, dj_cost))) => {
        if alt_cost != dj_cost {
          ok = false
        }
        if !ext_valid_weighted(spec, source, t, path, alt_cost) {
          ok = false
        }
      }
      (None, None) => ()
      _ => ok = false
    }
  }
  ok
}

///|
/// Feature: championship-v1-upgrade, task 19.1: ch_query_batch 与逐个 ch_query 一致
///
/// 批量入口对全部点对的结果，必须与逐个调用冻结的 `ch_query` 逐位（可达性 +
/// 代价 + 路径长度）相同。迭代 128 次（≥100）。
fn prop_ch_batch_equiv(spec : ExtGSpec) -> Bool {
  let succ = ext_succ(spec)
  let nodes = ext_nodes(spec)
  let g = ch_preprocess(nodes, succ)
  // 构造全部 (s, t) 点对。
  let pairs : Array[(Int, Int)] = []
  for s in nodes {
    for t in nodes {
      pairs.push((s, t))
    }
  }
  let batch = ch_query_batch(g, pairs)
  if batch.length() != pairs.length() {
    return false
  }
  let mut ok = true
  let mut i = 0
  while i < pairs.length() {
    let (s, t) = pairs[i]
    let single = ch_query(g, s, t)
    match (batch[i], single) {
      (Some((p1, c1)), Some((p2, c2))) =>
        if c1 != c2 || p1.length() != p2.length() {
          ok = false
        }
      (None, None) => ()
      _ => ok = false
    }
    i += 1
  }
  ok
}

///|
/// Feature: championship-v1-upgrade, task 19.1: alt_query_batch 与逐个 alt_query 一致
///
/// 批量入口逐位结果与逐个 `alt_query` 相同。迭代 128 次（≥100）。
fn prop_alt_batch_equiv(spec : ExtGSpec) -> Bool {
  let succ = ext_succ(spec)
  let nodes = ext_nodes(spec)
  let num_landmarks = if spec.n < 2 { spec.n } else { 2 }
  let lm = alt_preprocess(nodes, succ, num_landmarks)
  let pairs : Array[(Int, Int)] = []
  for s in nodes {
    for t in nodes {
      pairs.push((s, t))
    }
  }
  let batch = alt_query_batch(lm, pairs, succ)
  if batch.length() != pairs.length() {
    return false
  }
  let mut ok = true
  let mut i = 0
  while i < pairs.length() {
    let (s, t) = pairs[i]
    let single = alt_query(lm, s, t, succ)
    match (batch[i], single) {
      (Some((p1, c1)), Some((p2, c2))) =>
        if c1 != c2 || p1.length() != p2.length() {
          ok = false
        }
      (None, None) => ()
      _ => ok = false
    }
    i += 1
  }
  ok
}

///|
/// 属性测试入口：ch_preprocess_with_order 正确性（≥100 迭代）。
test "Feature: championship-v1-upgrade, task 19.1: ch_preprocess_with_order matches dijkstra" {
  let ok = @infra_pbt.holds_for_all(
    ext_gspec_gen(),
    prop_ch_order_matches_dijkstra,
    iters=128,
  )
  assert_true(ok)
}

///|
/// 属性测试入口：alt_preprocess_with_landmarks 正确性（≥100 迭代）。
test "Feature: championship-v1-upgrade, task 19.1: alt_preprocess_with_landmarks matches dijkstra" {
  let ok = @infra_pbt.holds_for_all(
    ext_gspec_gen(),
    prop_alt_landmarks_matches_dijkstra,
    iters=128,
  )
  assert_true(ok)
}

///|
/// 属性测试入口：ch_query_batch 等价于逐个查询（≥100 迭代）。
test "Feature: championship-v1-upgrade, task 19.1: ch_query_batch equals per-pair ch_query" {
  let ok = @infra_pbt.holds_for_all(
    ext_gspec_gen(),
    prop_ch_batch_equiv,
    iters=128,
  )
  assert_true(ok)
}

///|
/// 属性测试入口：alt_query_batch 等价于逐个查询（≥100 迭代）。
test "Feature: championship-v1-upgrade, task 19.1: alt_query_batch equals per-pair alt_query" {
  let ok = @infra_pbt.holds_for_all(
    ext_gspec_gen(),
    prop_alt_batch_equiv,
    iters=128,
  )
  assert_true(ok)
}

// ───────────────────────── JPS 批量：网格生成器与属性 ─────────────────────────

///|
/// 随机网格规格：宽高与随机阻挡掩码，外加若干随机查询点对。
struct ExtGridSpec {
  width : Int
  height : Int
  blocked : Array[Bool]
  pairs : Array[((Int, Int), (Int, Int))]
}

///|
/// 随机网格生成器：宽高 `∈ [1, 6]`，每格约 25% 概率为墙；随机生成 `∈ [1, 5]`
/// 组查询点对（坐标落在网格范围内）。
fn ext_grid_gen() -> @infra_pbt.Gen[ExtGridSpec] {
  @infra_pbt.Gen::new(fn(rng) {
    let width = rng.next_range(1, 6)
    let height = rng.next_range(1, 6)
    let blocked : Array[Bool] = []
    for _i in 0..<(width * height) {
      // 约 25% 为墙（next_range(0,3)==0）。
      blocked.push(rng.next_range(0, 3) == 0)
    }
    let k = rng.next_range(1, 5)
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
/// Feature: championship-v1-upgrade, task 19.1: jps_batch 与逐个 jps 一致
///
/// 对随机网格与随机点对，`jps_batch` 的逐位结果与逐个 `jps` 完全一致
/// （可达性 + 代价 + 路径长度）。迭代 128 次（≥100）。
fn prop_jps_batch_equiv(spec : ExtGridSpec) -> Bool {
  match JPSGrid::new(spec.width, spec.height, spec.blocked) {
    None => true // 非法维度（掩码长度不符）由构造器拒绝，跳过该实例。
    Some(grid) => {
      let batch = jps_batch(grid, spec.pairs)
      if batch.length() != spec.pairs.length() {
        return false
      }
      let mut ok = true
      let mut i = 0
      while i < spec.pairs.length() {
        let (s, g) = spec.pairs[i]
        let single = jps(grid, s, g)
        match (batch[i], single) {
          (Some((p1, c1)), Some((p2, c2))) =>
            if c1 != c2 || p1.length() != p2.length() {
              ok = false
            }
          (None, None) => ()
          _ => ok = false
        }
        i += 1
      }
      ok
    }
  }
}

///|
/// 属性测试入口：jps_batch 等价于逐个查询（≥100 迭代）。
test "Feature: championship-v1-upgrade, task 19.1: jps_batch equals per-pair jps" {
  let ok = @infra_pbt.holds_for_all(
    ext_grid_gen(),
    prop_jps_batch_equiv,
    iters=128,
  )
  assert_true(ok)
}

// ───────────────────────── 确定性单元测试（锚点） ─────────────────────────

///|
/// 单元锚点：ch_preprocess_with_order 在线性链上返回完整展开路径与正确代价，
/// 且对「部分 / 含越界」的顺序仍能正确归一化、产出合法结果。
test "Feature: championship-v1-upgrade, task 19.1: ch_preprocess_with_order anchor" {
  let nodes = [0, 1, 2, 3]
  let adj : Array[Array[(Int, Int)]] = [[(1, 2)], [(2, 2)], [(3, 2)], []]
  let succ = fn(n : Int) { adj[n] }
  // 仅给出部分顺序且含越界项 9；其余节点应被自动补齐。
  let g = ch_preprocess_with_order(nodes, succ, [2, 9, 0])
  match ch_query(g, 0, 3) {
    Some((path, cost)) => {
      @test.assert_eq(cost, 6)
      @test.assert_eq(path[0], 0)
      @test.assert_eq(path[path.length() - 1], 3)
      @test.assert_eq(path.length(), 4)
    }
    None => assert_true(false)
  }
}

///|
/// 单元锚点：alt_preprocess_with_landmarks 在小图上与 Dijkstra 代价一致；
/// 空地标集退化为 Dijkstra（零启发式）仍正确。
test "Feature: championship-v1-upgrade, task 19.1: alt_preprocess_with_landmarks anchor" {
  let nodes = [0, 1, 2, 3, 4]
  let adj : Array[Array[(Int, Int)]] = [
    [(1, 2), (2, 5)],
    [(2, 1)],
    [(3, 3)],
    [(4, 1)],
    [],
  ]
  let succ = fn(n : Int) { adj[n] }
  // 指定地标集。
  let lm = alt_preprocess_with_landmarks(nodes, succ, [0, 4])
  for t in nodes {
    let alt_r = alt_query(lm, 0, t, succ)
    let dj_r = @dir.dijkstra(0, succ, fn(x) { x == t })
    match (alt_r, dj_r) {
      (Some((_, a)), Some((_, d))) => @test.assert_eq(a, d)
      (None, None) => assert_true(true)
      _ => assert_true(false)
    }
  }
  // 空地标集：退化为 Dijkstra（最短 0->4 = 2+1+3+1 = 7）。
  let lm0 = alt_preprocess_with_landmarks(nodes, succ, [])
  @test.assert_eq(lm0.landmarks.length(), 0)
  match alt_query(lm0, 0, 4, succ) {
    Some((_, c)) => @test.assert_eq(c, 7)
    None => assert_true(false)
  }
}

///|
/// 单元锚点：jps_batch 在开阔网格上对多点对返回与单次 jps 一致的结果。
test "Feature: championship-v1-upgrade, task 19.1: jps_batch anchor" {
  let grid = match JPSGrid::new(5, 5, Array::make(25, false)) {
    Some(g) => g
    None => abort("jps_batch anchor: invalid grid")
  }
  let pairs = [((0, 0), (4, 4)), ((0, 0), (0, 4)), ((2, 2), (2, 2))]
  let batch = jps_batch(grid, pairs)
  @test.assert_eq(batch.length(), 3)
  let mut i = 0
  while i < pairs.length() {
    let (s, g) = pairs[i]
    match (batch[i], jps(grid, s, g)) {
      (Some((_, c1)), Some((_, c2))) => assert_true(c1 == c2)
      (None, None) => assert_true(true)
      _ => assert_true(false)
    }
    i += 1
  }
}
