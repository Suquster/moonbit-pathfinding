// ch_csr_bench.mbt —— 生产级 CSR CH 的大规模路网基准采集（任务 19.1 / R21.1）。
//
// 采集内容（与 `advanced_bench.mbt` 同一执行约定：完整规模仅在 `moon bench`
// 的 `@bench.T` 块中运行；`moon test` 只跑小规模 smoke 验证结构与正确性）：
//   * 数据集：`~10 万节点` 4-连通随机权网格（合成路网，R8.7 降级语义下的
//     `OSM_Roadmap_Dataset` 替身；LCG 确定性生成、三后端可复现）。
//   * 基线：点对点 Dijkstra（CSR 平坦数组 + 世代戳工作区 + 命中目标即停），
//     与 CH 查询共享同一数据布局，保证对比只差算法本身。
//   * 指标：CH 预处理耗时、双方每查询中位耗时（预热 ≥3、采样 ≥12）、
//     中位加速比（R8.5），并给出 `≥100×` 门槛判定（远超 baseline 纲领）。

///|
/// 完整规模网格边长（500² = 250 000 节点，≈「二十五万节点路网」）。
let csr_bench_side : Int = 500

///|
/// 完整规模的查询对数量（每计时样本内重复执行）。
let csr_bench_queries : Int = 24

///|
/// 计时采样数（R5.3：≥10）与预热数（≥3）。
let csr_bench_samples : Int = 12

///|
let csr_bench_warmup : Int = 3

///|
/// 大规模基准的加速比门槛：CH 中位查询耗时须优于基线 100 倍以上。
let csr_bench_speedup_gate : Double = 100.0

///|
/// 构造带确定性随机小整数权的 `side × side` 4-连通无向网格 CSR。
fn build_grid_csr(seed : Int, side : Int) -> @graph.CsrGraph[Double] {
  let rng = Lcg::new(seed)
  let n = side * side
  let edges : Array[(Int, Int, Double)] = []
  for r in 0..<side {
    for c in 0..<side {
      let u = r * side + c
      if c + 1 < side {
        let w = (1 + rng.next() % max_weight).to_double()
        edges.push((u, u + 1, w))
        edges.push((u + 1, u, w))
      }
      if r + 1 < side {
        let w = (1 + rng.next() % max_weight).to_double()
        edges.push((u, u + side, w))
        edges.push((u + side, u, w))
      }
    }
  }
  let cnt : Array[Int] = Array::make(n, 0)
  for e in edges {
    cnt[e.0] = cnt[e.0] + 1
  }
  let row_ptr : Array[Int] = Array::make(n + 1, 0)
  for i in 0..<n {
    row_ptr[i + 1] = row_ptr[i] + cnt[i]
  }
  let m = row_ptr[n]
  let col_idx : Array[Int] = Array::make(m, 0)
  let weights : Array[Double] = Array::make(m, 0.0)
  let fill : Array[Int] = Array::make(n, 0)
  for e in edges {
    let (u, v, w) = e
    let k = row_ptr[u] + fill[u]
    col_idx[k] = v
    weights[k] = w
    fill[u] = fill[u] + 1
  }
  { n, row_ptr, col_idx, weights }
}

///|
/// 点对点 Dijkstra 基线的常驻工作区（与 CH 查询同布局，公平对比）。
priv struct CsrDijkstra {
  g : @graph.CsrGraph[Double]
  dist : Array[Double]
  stamp : Array[Int]
  mut epoch : Int
}

///|
fn CsrDijkstra::new(g : @graph.CsrGraph[Double]) -> CsrDijkstra {
  { g, dist: Array::make(g.n, 0.0), stamp: Array::make(g.n, 0), epoch: 0 }
}

///|
/// 点对点 Dijkstra：平坦数组 + 世代戳 + 命中目标即停（早停使基线尽可能
/// 强，加速比因此是保守下界）。返回最短代价；不可达返回 `None`。
fn CsrDijkstra::query(self : CsrDijkstra, s : Int, t : Int) -> Double? {
  self.epoch = self.epoch + 1
  let ep = self.epoch
  let g = self.g
  let pq : @core.PQueue[Int, Double] = @core.PQueue::new()
  self.dist[s] = 0.0
  self.stamp[s] = ep
  pq.push(0.0, s)
  while !pq.is_empty() {
    let (d, u) = pq.pop().unwrap()
    if self.stamp[u] == ep && d > self.dist[u] {
      continue
    }
    if u == t {
      return Some(d)
    }
    for k in g.row_ptr[u]..<g.row_ptr[u + 1] {
      let v = g.col_idx[k]
      let nd = d + g.weights[k]
      if self.stamp[v] != ep || nd < self.dist[v] {
        self.dist[v] = nd
        self.stamp[v] = ep
        pq.push(nd, v)
      }
    }
  }
  None
}

///|
/// 中位数（拷贝后排序，样本量小、只在汇总期执行一次）。
fn csr_bench_median(xs : Array[Double]) -> Double {
  let ys = xs.copy()
  ys.sort()
  let n = ys.length()
  if n == 0 {
    0.0
  } else if n % 2 == 1 {
    ys[n / 2]
  } else {
    (ys[n / 2 - 1] + ys[n / 2]) / 2.0
  }
}

///|
/// 大规模 CH vs Dijkstra 采集主体：返回（Markdown 证据, 中位加速比）。
fn run_ch_csr_benchmark(
  side : Int,
  qcount : Int,
  warmup : Int,
  samples : Int,
) -> (String, Double) {
  let n = side * side
  let g = build_grid_csr(bench_seed_int, side)
  // 查询对：两两相异的随机端点（LCG 确定性）。
  let qrng = Lcg::new(query_seed_int)
  let queries : Array[(Int, Int)] = []
  for _ in 0..<qcount {
    queries.push((qrng.next() % n, qrng.next() % n))
  }
  // CH 预处理（计时一次）。
  let mut ch_opt : @advanced.ChCsr? = None
  let pre_ns = elapsed(fn() { ch_opt = Some(@advanced.ch_csr_preprocess(g)) })
  let ch = ch_opt.unwrap()
  let dij = CsrDijkstra::new(g)
  // 正确性护栏：采样前先全查询对拍一遍代价。
  let mut parity_ok = true
  for q in queries {
    let (s, t) = q
    let a = dij.query(s, t)
    let b = @advanced.ch_csr_query(ch, s, t)
    let c = @advanced.ch_csr_query_cost(ch, s, t)
    match (a, b, c) {
      (Some(x), Some((_, y)), Some(z)) =>
        if x != y || x != z {
          parity_ok = false
        }
      (None, None, None) => ()
      _ => parity_ok = false
    }
  }
  // 计时采集（每样本 = 整批查询；sink 防 DCE）。
  let sink : Array[Double] = [0.0]
  let dij_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match dij.query(q.0, q.1) {
        Some(c) => sink[0] = sink[0] + c
        None => ()
      }
    }
  })
  // 主指标：代价查询 vs 代价查询（同口径，基线 Dijkstra 亦不构造路径）。
  let ch_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match @advanced.ch_csr_query_cost(ch, q.0, q.1) {
        Some(c) => sink[0] = sink[0] + c
        None => ()
      }
    }
  })
  // 参考指标：含完整路径展开的 CH 查询。
  let ch_path_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match @advanced.ch_csr_query(ch, q.0, q.1) {
        Some((p, c)) => sink[0] = sink[0] + c + p.length().to_double()
        None => ()
      }
    }
  })
  ignore(sink[0])
  let dij_med = csr_bench_median(dij_samples)
  let ch_med = csr_bench_median(ch_samples)
  let ch_path_med = csr_bench_median(ch_path_samples)
  let speedup = if ch_med > 0.0 { dij_med / ch_med } else { 0.0 }
  let qd = qcount.to_double()
  let tb = @infra_text.TextBuilder::new()
  tb.push_str(
    "# CH(CSR) vs Dijkstra — 大规模合成路网基准（任务 19.1）\n\n",
  )
  tb.push_str(
    "- 数据集: synthetic 4-connected weighted grid（R8.7 合成替身）\n",
  )
  tb.push_str(
    "- 节点数: \{n}（side=\{side}）; 有向边数: \{g.col_idx.length()}\n",
  )
  tb.push_str("- 查询对: \{qcount}; 预热: \{warmup}; 采样: \{samples}\n")
  tb.push_str(
    "- CH 层级图边数: up=\{ch.up_row[ch.n]} dn=\{ch.dn_row[ch.n]}\n",
  )
  tb.push_str("- 代价对拍全一致: \{parity_ok}\n")
  // 单调时钟返回微秒（见 core/bench iter_count 的 100000.0 = 100ms 阈值）。
  tb.push_str("- CH 预处理耗时: \{pre_ns / 1.0e3} ms\n")
  tb.push_str("- Dijkstra 每查询中位耗时: \{dij_med / qd} µs\n")
  tb.push_str("- CH 每查询中位耗时（代价）: \{ch_med / qd} µs\n")
  tb.push_str(
    "- CH 每查询中位耗时（含路径展开）: \{ch_path_med / qd} µs\n",
  )
  tb.push_str(
    "- 中位加速比: \{speedup}x（门槛 ≥\{csr_bench_speedup_gate}x: ",
  )
  tb.push_str(if speedup >= csr_bench_speedup_gate { "PASS" } else { "FAIL" })
  tb.push_str("）\n")
  if !parity_ok {
    tb.push_str(
      "\n**警告：代价对拍存在不一致，加速比无效。**\n",
    )
  }
  (tb.build(), speedup)
}

///|
test "bench: collect CH(CSR) large-scale road-network artifacts" (b : @bench.T) {
  let (evidence_md, speedup) = run_ch_csr_benchmark(
    csr_bench_side, csr_bench_queries, csr_bench_warmup, csr_bench_samples,
  )
  println("===CH_CSR_EVIDENCE_BEGIN===")
  println(evidence_md)
  println("===CH_CSR_EVIDENCE_END===")
  b.bench(name="ch_csr_artifacts_emitted", fn() {
    b.keep(evidence_md.length() + speedup.to_int())
  })
}

///|
test "smoke: CH(CSR) 基准采集结构正确（tiny 16×16）" {
  let (evidence_md, speedup) = run_ch_csr_benchmark(16, 8, 1, 3)
  // 结构断言：证据包含全部关键字段；加速比为有限正数（tiny 规模不设门槛）。
  assert_true(evidence_md.contains("CH 预处理耗时"))
  assert_true(evidence_md.contains("中位加速比"))
  assert_true(evidence_md.contains("代价对拍全一致: true"))
  assert_true(speedup > 0.0)
}
