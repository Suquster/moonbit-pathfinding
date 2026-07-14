// main.mbt —— MoonBit（「本库」）侧对比采集器（Requirement 6）。
//
// 与 Rust 侧 `bench_rust/src/main.rs` 共享逐位一致的随机源（复用既有
// `@infra_pbt.Rng`，xorshift64）与完全相同的确定性图/查询生成算法，保证
// 「相同 64 位种子 → 逐元素相同的图与查询集」（R6.2）。
//
// 输出经 stdout 标记段（与既有 benchmark_native.ps1 的标记段抽取模式一致）：
//   * golden 模式：===MOONSIDE_GOLDEN_BEGIN=== ... ===MOONSIDE_GOLDEN_END===
//   * bench  模式：===MOONSIDE_BENCH_BEGIN===  ... ===MOONSIDE_BENCH_END===

///|
/// 权重取值闭区间下界（与 Rust 侧 WEIGHT_MIN 一致）。
let weight_min : Int = 1

///|
/// 权重取值闭区间上界（与 Rust 侧 WEIGHT_MAX 一致）。
let weight_max : Int = 100

///|
/// 一个确定性生成的工作负载：节点数、有向带权边、查询对。
struct Workload {
  n : Int
  edges : Array[(Int, Int, Int)]
  queries : Array[(Int, Int)]
}

///|
/// 与 Rust 侧逐元素一致的确定性生成算法（取数顺序：每边 u,v,w；每查询 s,t）。
fn generate(
  seed : UInt64,
  n : Int,
  avg_out_degree : Int,
  num_queries : Int,
) -> Workload {
  let rng = @pbt.rng_new(seed)
  let m = n * avg_out_degree
  let edges : Array[(Int, Int, Int)] = []
  let mut i = 0
  while i < m {
    let u = rng.next_below(n)
    let mut v = rng.next_below(n)
    if v == u {
      v = if n > 0 { (u + 1) % n } else { u }
    }
    let w = rng.next_range(weight_min, weight_max)
    edges.push((u, v, w))
    i += 1
  }
  let queries : Array[(Int, Int)] = []
  let mut q = 0
  while q < num_queries {
    let s = rng.next_below(n)
    let t = rng.next_below(n)
    queries.push((s, t))
    q += 1
  }
  { n, edges, queries }
}

///|
/// 由边集构建带权 CSR（indexed 快路径，供 Dijkstra / A* 复用）。
fn build_weighted_adjacency(w : Workload) -> @directed.WeightedCsr {
  @directed.WeightedCsr::from_edges(w.n, w.edges)
}

///|
/// 逆图加权 CSR（双向 Dijkstra 的反向前沿沿入边推进）。
fn build_weighted_reverse_adjacency(w : Workload) -> @directed.WeightedCsr {
  let redges : Array[(Int, Int, Int)] = []
  for e in w.edges {
    let (u, v, wt) = e
    redges.push((v, u, wt))
  }
  @directed.WeightedCsr::from_edges(w.n, redges)
}

///|
/// 由边集构建无权 CSR（indexed 快路径，供 BFS 复用，忽略权重）。
fn build_unweighted_adjacency(w : Workload) -> @unweighted.CsrGraph {
  let pairs : Array[(Int, Int)] = []
  for e in w.edges {
    let (u, v, _wt) = e
    pairs.push((u, v))
  }
  @unweighted.CsrGraph::from_edges(w.n, pairs)
}

///|
/// 逆图无权 CSR（双向 BFS 的反向前沿沿入边推进）。
fn build_unweighted_reverse_adjacency(w : Workload) -> @unweighted.CsrGraph {
  let pairs : Array[(Int, Int)] = []
  for e in w.edges {
    let (u, v, _wt) = e
    pairs.push((v, u))
  }
  @unweighted.CsrGraph::from_edges(w.n, pairs)
}

///|
/// BFS 跳数签名（单向，与 Rust `pathfinding::bfs` 同算法）：可达取边数，
/// 不可达取 -1。这是「同算法对齐」主对比路径（R6.1）。
fn bfs_uni_signatures(
  g : @unweighted.CsrGraph,
  queries : Array[(Int, Int)],
) -> Array[Int] {
  let ctx = @unweighted.BfsCtx::new(g.node_count())
  let out : Array[Int] = []
  for qr in queries {
    let (s, t) = qr
    let res = @unweighted.bfs_indexed_ctx(g, ctx, s, t)
    match res {
      Some(path) => out.push(path.length() - 1)
      None => out.push(-1)
    }
  }
  out
}

///|
/// Dijkstra 代价签名（单向，与 Rust `pathfinding::dijkstra` 同算法）。
fn dijkstra_uni_signatures(
  g : @directed.WeightedCsr,
  queries : Array[(Int, Int)],
) -> Array[Int] {
  let ctx = @directed.SearchCtx::new(g.node_count())
  let out : Array[Int] = []
  for qr in queries {
    let (s, t) = qr
    let res = @directed.dijkstra_indexed_ctx(g, ctx, s, t)
    match res {
      Some((_path, cost)) => out.push(cost)
      None => out.push(-1)
    }
  }
  out
}

///|
/// A*（零启发式，单向，与 Rust `pathfinding::astar` 同算法）。
fn astar_uni_signatures(
  g : @directed.WeightedCsr,
  queries : Array[(Int, Int)],
) -> Array[Int] {
  let ctx = @directed.SearchCtx::new(g.node_count())
  let out : Array[Int] = []
  for qr in queries {
    let (s, t) = qr
    let res = @directed.astar_indexed_ctx(g, ctx, s, t, fn(_node) { 0 })
    match res {
      Some((_path, cost)) => out.push(cost)
      None => out.push(-1)
    }
  }
  out
}

///|
/// BFS 跳数签名（双向，本库独有能力，Rust `pathfinding` crate 无对应 API；
/// 仅作为 library-capability bonus 上报，不进入同算法加速比）。
fn bfs_signatures(
  g : @unweighted.CsrGraph,
  rg : @unweighted.CsrGraph,
  queries : Array[(Int, Int)],
) -> Array[Int] {
  let ctx = @unweighted.BiBfsCtx::new(g.node_count())
  let out : Array[Int] = []
  for qr in queries {
    let (s, t) = qr
    let res = @unweighted.bfs_bidirectional_ctx(g, rg, ctx, s, t)
    match res {
      Some(path) => out.push(path.length() - 1)
      None => out.push(-1)
    }
  }
  out
}

///|
/// Dijkstra 代价签名：可达取路径代价，不可达取 -1。
fn dijkstra_signatures(
  g : @directed.WeightedCsr,
  rg : @directed.WeightedCsr,
  queries : Array[(Int, Int)],
) -> Array[Int] {
  let ctx_f = @directed.SearchCtx::new(g.node_count())
  let ctx_b = @directed.SearchCtx::new(g.node_count())
  let out : Array[Int] = []
  for qr in queries {
    let (s, t) = qr
    let res = @directed.dijkstra_bidirectional_ctx(g, rg, ctx_f, ctx_b, s, t)
    match res {
      Some((_path, cost)) => out.push(cost)
      None => out.push(-1)
    }
  }
  out
}

///|
/// A*（零启发式）代价签名：可达取路径代价，不可达取 -1。零启发式在一般图上
/// 可采纳（admissible），等价一致代价搜索，与 Rust 侧完全一致。
fn astar_signatures(
  g : @directed.WeightedCsr,
  rg : @directed.WeightedCsr,
  queries : Array[(Int, Int)],
) -> Array[Int] {
  let ctx_f = @directed.SearchCtx::new(g.node_count())
  let ctx_b = @directed.SearchCtx::new(g.node_count())
  let out : Array[Int] = []
  for qr in queries {
    let (s, t) = qr
    let res = @directed.astar_bidirectional_ctx(
      g,
      rg,
      ctx_f,
      ctx_b,
      s,
      t,
      fn(_node) { 0 },
      fn(_node) { 0 },
    )
    match res {
      Some((_path, cost)) => out.push(cost)
      None => out.push(-1)
    }
  }
  out
}

///|
/// 防消除累加器（black-hole）：累计被测结果以阻止编译器消除计算，保证计时可信。
let blackhole : Ref[Int] = { val: 0 }

///|
/// 测量一次「计算签名」工作的单调时钟耗时并换算为毫秒；结果喂入 black-hole
/// 累加器，防止编译器将被测计算消除（dead-code elimination）。
///
/// 单位说明：MoonBit native 单调时钟（`moonbit_monotonic_clock_stop`）返回
/// **微秒**（经校准：300M 次循环原始读数 ≈ 2.70e6，对应 wall-clock ≈ 2.7s）。
/// 故毫秒 = 原始微秒读数 / 1000。
fn time_once_ms(work : () -> Array[Int]) -> Double {
  let ts = @bench.monotonic_clock_start()
  let sig = work()
  let us = @bench.monotonic_clock_end(ts)
  let mut acc = 0
  for x in sig {
    acc = acc + x
  }
  blackhole.val = blackhole.val + acc
  us / 1_000.0
}

///|
/// 排序后的统计量（毫秒），口径与 Rust 侧 / `@infra_bench.compute_stats` 一致。
struct Stats {
  min_ms : Double
  median_ms : Double
  mean_ms : Double
  p95_ms : Double
  sample_count : Int
}

///|
/// 计算 min / median / mean / p95（p95 用最近秩法）。
fn compute_stats(samples : Array[Double]) -> Stats {
  let sorted = samples.copy()
  sorted.sort()
  let count = sorted.length()
  if count == 0 {
    return {
      min_ms: 0.0,
      median_ms: 0.0,
      mean_ms: 0.0,
      p95_ms: 0.0,
      sample_count: 0,
    }
  }
  let median = if count % 2 == 1 {
    sorted[count / 2]
  } else {
    (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
  }
  let mut sum = 0.0
  for v in sorted {
    sum += v
  }
  let mean = sum / count.to_double()
  // 最近秩 p95：rank = ceil(0.95 * count) = ceil(95*count/100)（整数运算避免浮点）。
  let rank = (95 * count + 99) / 100
  let idx = {
    let r = if rank - 1 < 0 { 0 } else { rank - 1 }
    if r > count - 1 {
      count - 1
    } else {
      r
    }
  }
  {
    min_ms: sorted[0],
    median_ms: median,
    mean_ms: mean,
    p95_ms: sorted[idx],
    sample_count: count,
  }
}

// ─────────────────────────── JSON 构建 ───────────────────────────
//
// 用 Array[String] 缓冲 + join 构建，避免循环内字符串 `+` 拼接（R22.4）。

///|
/// 将整数数组渲染为 JSON 数组字面量。
fn ints_to_json(xs : Array[Int]) -> String {
  let parts : Array[String] = []
  for x in xs {
    parts.push(x.to_string())
  }
  "[" + parts.join(",") + "]"
}

///|
/// 将统计量渲染为 JSON 对象。
fn stats_to_json(s : Stats) -> String {
  let parts : Array[String] = [
    "\"min_ms\":" + s.min_ms.to_string(),
    "\"median_ms\":" + s.median_ms.to_string(),
    "\"mean_ms\":" + s.mean_ms.to_string(),
    "\"p95_ms\":" + s.p95_ms.to_string(),
    "\"sample_count\":" + s.sample_count.to_string(),
  ]
  "{" + parts.join(",") + "}"
}

// ─────────────────────────── 参数解析 ───────────────────────────

///|
/// 从 `@env.args()` 解析 `--key value`；返回查找函数。
fn parse_args() -> Map[String, String] {
  let raw = @env.args()
  let map : Map[String, String] = Map([])
  let mut i = 0
  while i < raw.length() {
    let a = raw[i]
    if a.has_prefix("--") {
      let key = a[2:].to_owned()
      if i + 1 < raw.length() && !raw[i + 1].has_prefix("--") {
        map[key] = raw[i + 1]
        i += 2
      } else {
        map[key] = "true"
        i += 1
      }
    } else {
      i += 1
    }
  }
  map
}

///|
fn arg_str(map : Map[String, String], key : String, default : String) -> String {
  match map.get(key) {
    Some(v) => v
    None => default
  }
}

///|
fn arg_int(map : Map[String, String], key : String, default : Int) -> Int {
  match map.get(key) {
    Some(v) =>
      try @string.parse_int(v) catch {
        _ => default
      } noraise {
        n => n
      }
    None => default
  }
}

///|
/// 解析无符号 64 位种子（十进制）。失败回退默认。
fn arg_u64(map : Map[String, String], key : String, default : UInt64) -> UInt64 {
  match map.get(key) {
    Some(v) =>
      try @string.parse_uint64(v) catch {
        _ => default
      } noraise {
        n => n
      }
    None => default
  }
}

///|
/// 解析逗号分隔的整数列表。
fn arg_list(
  map : Map[String, String],
  key : String,
  default : String,
) -> Array[Int] {
  let raw = arg_str(map, key, default)
  let out : Array[Int] = []
  for piece in raw.split(",") {
    let trimmed = piece.trim()
    out.push(@string.parse_int(trimmed)) catch {
      _ => ()
    }
  }
  out
}

// ─────────────────────────── 模式实现 ───────────────────────────

///|
/// golden 模式：输出黄金 JSON 图样本供两侧逐元素交叉校验。
fn run_golden(map : Map[String, String]) -> Unit {
  let seed = arg_u64(map, "seed", 0x123456789ABCDEF0UL)
  let num_queries = arg_int(map, "queries", 100)
  let sizes = arg_list(map, "golden-sizes", "1000")
  let degrees = arg_list(map, "degrees", "4,16")
  let config_parts : Array[String] = []
  for n in sizes {
    for d in degrees {
      let w = generate(seed, n, d, num_queries)
      let edge_parts : Array[String] = []
      for e in w.edges {
        let (u, v, wt) = e
        edge_parts.push(
          "[" + u.to_string() + "," + v.to_string() + "," + wt.to_string() + "]",
        )
      }
      let query_parts : Array[String] = []
      for qr in w.queries {
        let (s, t) = qr
        query_parts.push("[" + s.to_string() + "," + t.to_string() + "]")
      }
      let parts : Array[String] = [
        "\"seed\":" + seed.to_string(),
        "\"n\":" + n.to_string(),
        "\"avg_out_degree\":" + d.to_string(),
        "\"num_queries\":" + num_queries.to_string(),
        "\"edges\":[" + edge_parts.join(",") + "]",
        "\"queries\":[" + query_parts.join(",") + "]",
      ]
      config_parts.push("{" + parts.join(",") + "}")
    }
  }
  let json = "{\"schema\":\"moonbit-pathfinding.rust-comparison.golden.v1\",\"side\":\"moonbit\",\"configs\":[" +
    config_parts.join(",") +
    "]}"
  println("===MOONSIDE_GOLDEN_BEGIN===")
  println(json)
  println("===MOONSIDE_GOLDEN_END===")
}

///|
/// bench 模式：在工作负载矩阵上采集计时与结果签名。
fn run_bench(map : Map[String, String]) -> Unit {
  let seed = arg_u64(map, "seed", 0x123456789ABCDEF0UL)
  let num_queries = arg_int(map, "queries", 100)
  let warmup = {
    let w = arg_int(map, "warmup", 5)
    if w < 5 {
      5
    } else {
      w
    }
  }
  let samples = {
    let s = arg_int(map, "samples", 30)
    if s < 30 {
      30
    } else {
      s
    }
  }
  let timeout_sec = arg_int(map, "timeout-sec", 60)
  let timeout_ms = timeout_sec.to_double() * 1000.0
  let sizes = arg_list(map, "sizes", "1000,10000,100000")
  let degrees = arg_list(map, "degrees", "4,16")
  let case_parts : Array[String] = []
  for n in sizes {
    for d in degrees {
      let w = generate(seed, n, d, num_queries)
      let edge_count = w.edges.length()
      let query_count = w.queries.length()
      let wadj = build_weighted_adjacency(w)
      let wradj = build_weighted_reverse_adjacency(w)
      let uadj = build_unweighted_adjacency(w)
      let uradj = build_unweighted_reverse_adjacency(w)
      let queries = w.queries
      // 三种算法的「整批查询」工作闭包。
      let algos : Array[(String, () -> Array[Int])] = [
        // 「同算法对齐」主对比：与 Rust 侧完全相同的单向算法（R6.1）。
        ("BFS", fn() { bfs_uni_signatures(uadj, queries) }),
        ("Dijkstra", fn() { dijkstra_uni_signatures(wadj, queries) }),
        ("A*", fn() { astar_uni_signatures(wadj, queries) }),
        // 「库能力 bonus」：双向变体（Rust `pathfinding` crate 无对应 API，
        // 不与 Rust 配对、不进入同算法加速比，仅展示本库额外能力）。
        ("BFS-bidir", fn() { bfs_signatures(uadj, uradj, queries) }),
        ("Dijkstra-bidir", fn() { dijkstra_signatures(wadj, wradj, queries) }),
        ("A*-bidir", fn() { astar_signatures(wadj, wradj, queries) }),
      ]
      for entry in algos {
        let (algo, work) = entry
        // 预热第一拍即检测超时（R6.7），避免大规模用例挂起整套。
        let first = time_once_ms(work)
        if first > timeout_ms {
          let sig = work()
          let parts : Array[String] = [
            "\"algorithm\":\"" + algo + "\"",
            "\"graph_size\":" + n.to_string(),
            "\"avg_out_degree\":" + d.to_string(),
            "\"edge_count\":" + edge_count.to_string(),
            "\"query_count\":" + query_count.to_string(),
            "\"seed\":" + seed.to_string(),
            "\"warmup_count\":" + warmup.to_string(),
            "\"timed_out\":true",
            "\"stats\":" + stats_to_json(compute_stats([first])),
            "\"signatures\":" + ints_to_json(sig),
          ]
          case_parts.push("{" + parts.join(",") + "}")
          continue
        }
        // 余下预热（已用一拍）。
        let mut wi = 1
        while wi < warmup {
          let _ = work()
          wi += 1
        }
        // 采样。
        let times : Array[Double] = []
        let mut timed_out = false
        let mut si = 0
        while si < samples {
          let t = time_once_ms(work)
          times.push(t)
          if t > timeout_ms {
            timed_out = true
            break
          }
          si += 1
        }
        let signatures = work()
        let parts : Array[String] = [
          "\"algorithm\":\"" + algo + "\"",
          "\"graph_size\":" + n.to_string(),
          "\"avg_out_degree\":" + d.to_string(),
          "\"edge_count\":" + edge_count.to_string(),
          "\"query_count\":" + query_count.to_string(),
          "\"seed\":" + seed.to_string(),
          "\"warmup_count\":" + warmup.to_string(),
          "\"timed_out\":" + (if timed_out { "true" } else { "false" }),
          "\"stats\":" + stats_to_json(compute_stats(times)),
          "\"signatures\":" + ints_to_json(signatures),
        ]
        case_parts.push("{" + parts.join(",") + "}")
      }
    }
  }
  let header : Array[String] = [
    "\"schema\":\"moonbit-pathfinding.rust-comparison.bench.v1\"",
    "\"side\":\"moonbit\"",
    "\"library\":\"moonbit-pathfinding\"",
    "\"timeout_sec\":" + timeout_sec.to_string(),
    "\"blackhole\":" + blackhole.val.to_string(),
    "\"methodology\":\"Deterministic xorshift64 shared with Rust side; edges=n*degree (u,v,w order), queries=(s,t); A* uses zero heuristic (admissible) on general graphs; warmup>=5, samples>=30; per-sample = run all queries once; timing via monotonic clock in ms.\"",
  ]
  let json = "{" +
    header.join(",") +
    ",\"cases\":[" +
    case_parts.join(",") +
    "]}"
  println("===MOONSIDE_BENCH_BEGIN===")
  println(json)
  println("===MOONSIDE_BENCH_END===")
}

///|
/// 入口：按 `--mode golden|bench|calibrate` 分派（缺省 bench）。
fn main {
  let map = parse_args()
  let mode = arg_str(map, "mode", "bench")
  if mode == "golden" {
    run_golden(map)
  } else if mode == "bench" {
    run_bench(map)
  } else if mode == "calibrate" {
    // 校准：执行一段确定性重负载并打印单调时钟原始读数，配合外部 wall-clock
    // 验证单调时钟单位（仅诊断用）。
    let iters = arg_int(map, "iters", 100000000)
    let ts = @bench.monotonic_clock_start()
    let mut acc = 0
    let mut i = 0
    while i < iters {
      acc = (acc + i) % 1000003
      i += 1
    }
    let raw = @bench.monotonic_clock_end(ts)
    blackhole.val = blackhole.val + acc
    println(
      "CALIBRATE raw_clock=" +
      raw.to_string() +
      " iters=" +
      iters.to_string() +
      " acc=" +
      acc.to_string(),
    )
  } else {
    println("[moon_side] unknown mode: " + mode)
  }
}
