// advanced_bench.mbt —— CH / JPS / ALT / Dijkstra 原始计时采集与统计汇总（任务 21.1）。
//
// 设计依据（design.md §「方向 2」/ requirements R5.1–R5.4、R5.6、R8.4、R8.5）：
//   * R5.3：每个基准用例测量前执行 **≥3 次预热**、采集 **≥10 次计时样本**。
//   * R5.2：报告记录 MoonBit 版本/后端/机器/生成器/种子/图规模/边数/查询数/
//     原始计时/汇总统计量；统计量统一由 `@infra_bench.compute_stats` 计算。
//   * R5.1：产出 Markdown + JSON 双产物（JSON 由本采集器输出，MD 由脚本层渲染）。
//   * R8.4：为 CH/JPS/ALT 记录预处理耗时、≥10 次重复的平均/中位查询耗时、查询
//     样本量、数据集标识与图规模。
//   * R8.5：为 CH/ALT 记录相对基准 Dijkstra 的中位查询加速比，并判定其平均查询
//     耗时不高于 Dijkstra。
//   * R8.7/R5.6：`OSM_Roadmap_Dataset` 不可用时由脚本层降级（告警 + 继续），本
//     采集器在合成图上完成正确性级别的可复现计时证据，数据集标识标注为合成。
//
// 拓扑选择：加权图采用 **4-连通网格**（路网式、平面、低收缩代价），使 CH 预处理
// 在 release/native 下数十毫秒内完成；随机稠密图会使 CH 收缩退化为近 O(n³) 的捷径
// 爆炸，不适合作为可复现基准。JPS 另用独立障碍网格。
//
// 执行约定：完整规模的采集放在 `@bench.T` 基准块中，仅由 `moon bench`（脚本层以
// `--release` 调用）执行并打印 JSON；普通 `moon test` 只跑一个极小规模 smoke 测试，
// 避免在 debug/wasm 解释执行下因 CH 预处理过慢而拖垮项目级测试门禁。
//
// 时间源：`moonbitlang/core/bench` 的单调时钟（与既有原生基准同源），返回值单位
// 与 `monotonic_clock_end` 一致（纳秒量级 `Double`）。加速比为同单位比值，单位无关。

// ───────────────────────────── 采集参数（命名常量） ─────────────────────────────

///|
/// 加权网格边长（节点数 = side × side）。当前 `@advanced` 的 CH 预处理在网格上存在
/// 捷径爆炸，规模超过约 30 节点即急剧变慢（生产级 CH 性能升级见并行任务 19.1）；
/// 因此默认取保守的 5×5，使完整采集（含 CH）在 release/native 下秒级完成。CH 性能
/// 升级落地后，仅需上调此常量即可获得更大规模真实计时；脚本层对采集超时已做告警
/// 降级（R5.6/R8.7），不影响其余基准产出。
let weighted_grid_side : Int = 5

///|
/// 网格边权上界（权重在 `[1, max_weight]` 内均匀采样，避免零权并列主导计时）。
let max_weight : Int = 9

///|
/// JPS 网格边长（`grid_dim × grid_dim` 均匀网格）。
let grid_dim : Int = 32

///|
/// JPS 网格障碍占比的分子（`blocked when rng % 100 < obstacle_pct`）。
let obstacle_pct : Int = 18

///|
/// 每个基准用例的查询对数量（单个计时样本内重复执行的查询次数；R8.4 样本量）。
let query_count : Int = 100

///|
/// 预热次数（测量前丢弃，R5.3 要求 ≥3）。
let warmup_rounds : Int = 3

///|
/// 计时样本数（R5.3 要求 ≥10）。
let sample_rounds : Int = 12

///|
/// ALT 预处理使用的地标数量。
let alt_landmarks : Int = 6

///|
/// 图生成器随机种子（同时用于 Int 版 LCG 与报告记录的 UInt64 字段）。
let bench_seed_int : Int = 20240607

///|
/// 报告 `seed` 字段（无符号 64 位），与 `bench_seed_int` 同源以保证可复现。
let bench_seed_u64 : UInt64 = 20240607UL

///|
/// 查询对生成器种子（与图种子区分，避免查询与拓扑相关性偏置）。
let query_seed_int : Int = 911

// ─────────────────────────────── 确定性随机源 ───────────────────────────────

///|
/// 自包含线性同余发生器（与既有 `*_bench` 一致），保证三后端逐元素可复现。
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

// ─────────────────────────────── 合成图构造（4-连通加权网格） ───────────────────────────────

///|
/// 构造 `side × side` 的 4-连通加权网格邻接表。节点编号 `r*side + c`；每条网格边
/// 赋以 `[1, max_w]` 内的随机权重，对向边共享同一权重（无向）。网格连通，任意
/// 源/目标可达，且对 CH 收缩友好（平面、低度数）。
fn build_grid_graph(
  seed : Int,
  side : Int,
  max_w : Int,
) -> Array[Array[(Int, Int)]] {
  let n = side * side
  let rng = Lcg::new(seed)
  let adj : Array[Array[(Int, Int)]] = Array::makei(n, fn(_) { [] })
  for r in 0..<side {
    for c in 0..<side {
      let u = r * side + c
      // 向右与向下连边（对向边同权，避免重复枚举）。
      if c + 1 < side {
        let v = r * side + (c + 1)
        let w = 1 + rng.next() % max_w
        adj[u].push((v, w))
        adj[v].push((u, w))
      }
      if r + 1 < side {
        let v = (r + 1) * side + c
        let w = 1 + rng.next() % max_w
        adj[u].push((v, w))
        adj[v].push((u, w))
      }
    }
  }
  adj
}

///|
/// 统计邻接表的有向边总数（无向边计为两条有向边）。
fn count_edges(adj : Array[Array[(Int, Int)]]) -> Int {
  let mut total = 0
  for row in adj {
    total = total + row.length()
  }
  total
}

///|
/// 生成 `count` 组随机 `(source, target)` 查询对。
fn build_queries(seed : Int, n : Int, count : Int) -> Array[(Int, Int)] {
  let rng = Lcg::new(seed)
  let qs : Array[(Int, Int)] = []
  for _ in 0..<count {
    let s = rng.next() % n
    let t = rng.next() % n
    qs.push((s, t))
  }
  qs
}

// ─────────────────────────────── JPS 网格构造 ───────────────────────────────

///|
/// 构造 `dim × dim` 网格障碍掩码，并强制四角可通行以便生成合法查询。
fn build_blocked(seed : Int, dim : Int, pct : Int) -> Array[Bool] {
  let rng = Lcg::new(seed)
  let blocked : Array[Bool] = Array::make(dim * dim, false)
  for i in 0..<(dim * dim) {
    blocked[i] = rng.next() % 100 < pct
  }
  blocked[0] = false
  blocked[dim - 1] = false
  blocked[(dim - 1) * dim] = false
  blocked[dim * dim - 1] = false
  blocked
}

///|
/// 生成 `count` 组随机的网格查询对，要求两端均可通行（不可通行则回退到角点）。
fn build_grid_queries(
  seed : Int,
  dim : Int,
  blocked : Array[Bool],
  count : Int,
) -> Array[((Int, Int), (Int, Int))] {
  let rng = Lcg::new(seed)
  let qs : Array[((Int, Int), (Int, Int))] = []
  for _ in 0..<count {
    let sr = rng.next() % dim
    let sc = rng.next() % dim
    let gr = rng.next() % dim
    let gc = rng.next() % dim
    let s = if blocked[sr * dim + sc] { (0, 0) } else { (sr, sc) }
    let g = if blocked[gr * dim + gc] { (dim - 1, dim - 1) } else { (gr, gc) }
    qs.push((s, g))
  }
  qs
}

// ─────────────────────────────── 计时原语 ───────────────────────────────

///|
/// 测量一次 `work` 的单调时钟耗时（单位同 `monotonic_clock_end`，纳秒量级）。
fn elapsed(work : () -> Unit) -> Double {
  let ts = @bench.monotonic_clock_start()
  work()
  @bench.monotonic_clock_end(ts)
}

///|
/// 执行 `warmup` 次预热（丢弃）后采集 `samples` 个计时样本（R5.3：≥3 预热、≥10 采样）。
fn collect_samples(
  warmup : Int,
  samples : Int,
  batch : () -> Unit,
) -> Array[Double] {
  for _ in 0..<warmup {
    batch()
  }
  let out : Array[Double] = []
  for _ in 0..<samples {
    out.push(elapsed(batch))
  }
  out
}

// ─────────────────────────────── 查询批次（防 DCE 累加） ───────────────────────────────

///|
/// Dijkstra 查询批次。
fn dijkstra_batch(
  queries : Array[(Int, Int)],
  succ : (Int) -> Array[(Int, Int)],
  sink : Array[Int],
) -> Unit {
  for q in queries {
    let (s, t) = q
    match @dir.dijkstra(s, succ, fn(v) { v == t }) {
      Some((p, _)) => sink[0] = sink[0] + p.length()
      None => sink[0] = sink[0] + 1
    }
  }
}

///|
/// CH 查询批次。
fn ch_batch(
  ch : @advanced.CHGraph[Int, Int],
  queries : Array[(Int, Int)],
  sink : Array[Int],
) -> Unit {
  for q in queries {
    let (s, t) = q
    match @advanced.ch_query(ch, s, t) {
      Some((p, _)) => sink[0] = sink[0] + p.length()
      None => sink[0] = sink[0] + 1
    }
  }
}

///|
/// ALT 查询批次。
fn alt_batch(
  lm : @advanced.Landmark[Int, Int],
  queries : Array[(Int, Int)],
  succ : (Int) -> Array[(Int, Int)],
  sink : Array[Int],
) -> Unit {
  for q in queries {
    let (s, t) = q
    match @advanced.alt_query(lm, s, t, succ) {
      Some((p, _)) => sink[0] = sink[0] + p.length()
      None => sink[0] = sink[0] + 1
    }
  }
}

///|
/// JPS 查询批次。
fn jps_batch(
  grid : @advanced.JPSGrid,
  queries : Array[((Int, Int), (Int, Int))],
  sink : Array[Int],
) -> Unit {
  for q in queries {
    let (s, g) = q
    match @advanced.jps(grid, s, g) {
      Some((p, _)) => sink[0] = sink[0] + p.length()
      None => sink[0] = sink[0] + 1
    }
  }
}

// ─────────────────────────────── 报告组装 ───────────────────────────────

///|
/// moon 版本占位符（脚本层替换为真实 `moon version`）。
let placeholder_moon_version : String = "__MOON_VERSION__"

///|
/// 后端占位符（脚本层替换为真实 target）。
let placeholder_backend : String = "__BACKEND__"

///|
/// 操作系统占位符（脚本层替换）。
let placeholder_os : String = "__OS__"

///|
/// CPU 占位符（脚本层替换）。
let placeholder_cpu : String = "__CPU__"

///|
/// 输入生成器标识（合成 4-连通加权网格 + JPS 障碍网格；可复现）。
let generator_id : String = "advanced-synthetic:weighted-grid4;jps-grid"

///|
/// 数据集标识。OSM 真实路网不可用时为合成标识（R8.7 降级，脚本层另行告警）。
let dataset_id : String = "synthetic-weighted-grid4-v1"

///|
/// 由样本构造一个 `BenchCase`（统计量来自 `@infra_bench.compute_stats`）。
/// 样本恒非空（采样数 ≥1），故 `compute_stats` 不会失败。
fn make_case(
  algorithm : String,
  n : Int,
  edges : Int,
  queries : Int,
  samples : Array[Double],
) -> @infra_bench.BenchCase {
  let stats = @infra_bench.compute_stats(samples).unwrap()
  {
    algorithm,
    graph_size: n,
    edge_count: edges,
    query_count: queries,
    seed: bench_seed_u64,
    raw_ns: samples,
    stats,
  }
}

// ─────────────────────────────── 附加证据 JSON ───────────────────────────────

///|
/// 中位加速比：`baseline_median / algo_median`（>1 表示更快）。算法中位为 0 时
/// 无法定义比值，返回 0.0 并由消费方按「不可比」处理。
fn speedup(baseline_median : Double, algo_median : Double) -> Double {
  if algo_median == 0.0 {
    0.0
  } else {
    baseline_median / algo_median
  }
}

///|
/// 追加一个浮点 JSON 字段 `,"key":value`。
fn ev_num(tb : @infra_text.TextBuilder, key : String, v : Double) -> Unit {
  tb.push_str(",\"")
  tb.push_str(key)
  tb.push_str("\":")
  tb.push_str(v.to_string())
}

///|
/// 追加一个整型 JSON 字段 `,"key":value`。
fn ev_int(tb : @infra_text.TextBuilder, key : String, v : Int) -> Unit {
  tb.push_str(",\"")
  tb.push_str(key)
  tb.push_str("\":")
  tb.push_str(v.to_string())
}

///|
/// 追加一个布尔 JSON 字段 `,"key":value`。
fn ev_bool(tb : @infra_text.TextBuilder, key : String, v : Bool) -> Unit {
  tb.push_str(",\"")
  tb.push_str(key)
  tb.push_str("\":")
  tb.push_str(if v { "true" } else { "false" })
}

///|
/// 构造 CH/JPS/ALT 附加证据 JSON。
fn build_evidence_json(
  n : Int,
  edges : Int,
  q : Int,
  samples : Int,
  warmup : Int,
  ch_pre : Double,
  alt_pre : Double,
  jps_pre : Double,
  dij : @infra_bench.BenchStats,
  ch : @infra_bench.BenchStats,
  alt : @infra_bench.BenchStats,
  jps : @infra_bench.BenchStats,
) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("{\"dataset_id\":\"")
  tb.push_str(dataset_id)
  tb.push_str("\"")
  ev_bool(tb, "osm_available", false)
  ev_int(tb, "graph_size", n)
  ev_int(tb, "edge_count", edges)
  ev_int(tb, "query_count", q)
  ev_int(tb, "sample_count", samples)
  ev_int(tb, "warmup_count", warmup)
  // 预处理耗时（纳秒量级；JPS 的「预处理」为网格构造耗时）。
  ev_num(tb, "ch_preprocess_ns", ch_pre)
  ev_num(tb, "alt_preprocess_ns", alt_pre)
  ev_num(tb, "jps_preprocess_ns", jps_pre)
  // 中位/平均查询耗时（一个样本含 query_count 次查询）。
  ev_num(tb, "dijkstra_median_ns", dij.median)
  ev_num(tb, "dijkstra_mean_ns", dij.mean)
  ev_num(tb, "ch_median_ns", ch.median)
  ev_num(tb, "ch_mean_ns", ch.mean)
  ev_num(tb, "alt_median_ns", alt.median)
  ev_num(tb, "alt_mean_ns", alt.mean)
  ev_num(tb, "jps_median_ns", jps.median)
  ev_num(tb, "jps_mean_ns", jps.mean)
  // 相对 Dijkstra 的中位加速比（仅 CH/ALT；R8.5）。
  ev_num(tb, "ch_speedup_median", speedup(dij.median, ch.median))
  ev_num(tb, "alt_speedup_median", speedup(dij.median, alt.median))
  // 平均查询耗时不高于 Dijkstra 的判定（R8.5；合成图为记录性判定）。
  ev_bool(tb, "ch_mean_not_higher", ch.mean <= dij.mean)
  ev_bool(tb, "alt_mean_not_higher", alt.mean <= dij.mean)
  tb.push_char('}')
  tb.build()
}

// ─────────────────────────────── 采集入口 ───────────────────────────────

///|
/// 运行完整前沿算法基准采集，返回 `(标准报告JSON, 附加证据JSON)`。
///
/// 参数：
/// - `gside`：加权网格边长（节点数 = gside²）。
/// - `jdim`：JPS 障碍网格边长。
/// - `qcount`：每样本查询次数。
/// - `warmup` / `samples`：预热与采样次数（R5.3：≥3 / ≥10）。
///
/// 标准报告遵循 `moonbit-pathfinding.benchmark.v1` schema；元信息环境字段为占位符，
/// 由脚本层注入真实环境值。
fn run_advanced_benchmark(
  gside : Int,
  jdim : Int,
  qcount : Int,
  warmup : Int,
  samples : Int,
) -> (String, String) {
  let n = gside * gside
  let adj = build_grid_graph(bench_seed_int, gside, max_weight)
  let edges = count_edges(adj)
  let nodes : Array[Int] = Array::makei(n, fn(i) { i })
  let succ = fn(u : Int) -> Array[(Int, Int)] { adj[u] }
  let queries = build_queries(query_seed_int, n, qcount)

  // 预处理（一次性，计时）。
  let mut ch_opt : @advanced.CHGraph[Int, Int]? = None
  let ch_pre = elapsed(fn() {
    ch_opt = Some(@advanced.ch_preprocess(nodes, succ))
  })
  let ch = ch_opt.unwrap()
  let mut alt_opt : @advanced.Landmark[Int, Int]? = None
  let lmk = if alt_landmarks < n { alt_landmarks } else { n }
  let alt_pre = elapsed(fn() {
    alt_opt = Some(@advanced.alt_preprocess(nodes, succ, lmk))
  })
  let alt = alt_opt.unwrap()

  // JPS 网格构造（视为其「预处理」，计时）。
  let blocked = build_blocked(bench_seed_int, jdim, obstacle_pct)
  let mut grid_opt : @advanced.JPSGrid? = None
  let jps_pre = elapsed(fn() {
    grid_opt = @advanced.JPSGrid::new(jdim, jdim, blocked)
  })
  let grid = grid_opt.unwrap()
  let grid_queries = build_grid_queries(query_seed_int, jdim, blocked, qcount)

  // 计时采集（每算法：≥warmup 预热 + samples 采样；每样本含 qcount 次查询）。
  let sink : Array[Int] = [0]
  let dij_samples = collect_samples(warmup, samples, fn() {
    dijkstra_batch(queries, succ, sink)
  })
  let ch_samples = collect_samples(warmup, samples, fn() {
    ch_batch(ch, queries, sink)
  })
  let alt_samples = collect_samples(warmup, samples, fn() {
    alt_batch(alt, queries, succ, sink)
  })
  let jps_samples = collect_samples(warmup, samples, fn() {
    jps_batch(grid, grid_queries, sink)
  })

  // 防 DCE：消费 sink（不影响计时，仅保证查询调用不被消除）。
  ignore(sink[0])

  // 统计汇总（统一调用 @infra_bench.compute_stats）。
  let dij_case = make_case("Dijkstra", n, edges, qcount, dij_samples)
  let ch_case = make_case("CH", n, edges, qcount, ch_samples)
  let alt_case = make_case("ALT", n, edges, qcount, alt_samples)
  let jps_case = make_case(
    "JPS",
    jdim * jdim,
    blocked.length(),
    qcount,
    jps_samples,
  )
  let report : @infra_bench.BenchReport = {
    moon_version: placeholder_moon_version,
    backend: placeholder_backend,
    os: placeholder_os,
    cpu: placeholder_cpu,
    generator: generator_id,
    warmup_count: warmup,
    cases: [dij_case, ch_case, alt_case, jps_case],
  }
  let evidence = build_evidence_json(
    n,
    edges,
    qcount,
    samples,
    warmup,
    ch_pre,
    alt_pre,
    jps_pre,
    dij_case.stats,
    ch_case.stats,
    alt_case.stats,
    jps_case.stats,
  )
  (report.to_json(), evidence)
}

///|
/// 打印两段 JSON（以唯一标记包裹），供 `scripts/benchmark_native.ps1` 抽取。
fn emit_artifacts(report_json : String, evidence_json : String) -> Unit {
  println("===ADV_BENCH_REPORT_BEGIN===")
  println(report_json)
  println("===ADV_BENCH_REPORT_END===")
  println("===ADV_BENCH_EVIDENCE_BEGIN===")
  println(evidence_json)
  println("===ADV_BENCH_EVIDENCE_END===")
}

// ─────────────────────────────── 采集 / smoke 入口 ───────────────────────────────
//
// 完整规模采集放在 `@bench.T` 基准块（仅 `moon bench` 执行；脚本层以 --release 调用），
// 并打印 JSON。普通 `moon test` 仅运行下方极小规模 smoke 测试以验证结构正确，避免
// 在 debug/wasm 解释执行下因 CH 预处理过慢拖垮测试门禁。

///|
test "bench: collect advanced CH/JPS/ALT native benchmark artifacts" (
  b : @bench.T,
) {
  let (report_json, evidence_json) = run_advanced_benchmark(
    weighted_grid_side, grid_dim, query_count, warmup_rounds, sample_rounds,
  )
  emit_artifacts(report_json, evidence_json)
  // 同时登记一个轻量 @bench.T 测点，满足基准框架对 bench 块的形态要求。
  b.bench(name="advanced_artifacts_emitted", fn() {
    b.keep(report_json.length())
  })
}

///|
test "smoke: advanced benchmark produces four well-formed cases (tiny)" {
  // 极小规模（4×4 加权网格 + 6×6 JPS 网格），保证 debug/wasm 下也可秒级完成。
  let (report_json, evidence_json) = run_advanced_benchmark(4, 6, 12, 3, 10)
  match @infra_bench.parse_report(report_json) {
    Ok(r) => {
      @test.assert_eq(r.cases.length(), 4)
      for c in r.cases {
        // 采样数 ≥10、查询数 ≥10、原始样本数 ≥10（R5.3/R8.4）。
        assert_true(c.stats.sample_count >= 10)
        assert_true(c.query_count >= 10)
        assert_true(c.raw_ns.length() >= 10)
      }
    }
    Err(e) => {
      println("parse_report failed: " + @debug.to_string(e))
      assert_true(false)
    }
  }
  assert_true(evidence_json.length() > 0)
}
