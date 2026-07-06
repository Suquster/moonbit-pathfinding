// osm_alt_bench.mbt —— 真实 OSM 路网上的稠密快路径 ALT（@directed.AltLandmarks）
// vs 零启发式双向 Dijkstra 基准。
//
// 合成随机图（expander 结构）上 ALT 下界退化为 ~0（实验证伪，见
// benches/results），但真实路网具有低速增长的度量结构，地标三角
// 不等式下界紧，ALT 才是正收益场景——本基准补齐该正面证据：
// 同一批查询上对比 `dijkstra_bidirectional_ctx`（大权自动走堆式
// 双向）与 `astar_bidirectional_ctx` + ALT 下界，代价全量对拍守卫。

///|
/// 解析嵌入 OSM 负载为 @directed.WeightedCsr（权重取整数分米）。
fn build_osm_weighted_csr(
  n : Int,
  edge_count : Int,
  payload : Array[String],
) -> (@dir.WeightedCsr, @dir.WeightedCsr) {
  let edges : Array[(Int, Int, Int)] = Array::make(edge_count, (0, 0, 0))
  let redges : Array[(Int, Int, Int)] = Array::make(edge_count, (0, 0, 0))
  let mut ei = 0
  let mut field = 0
  let mut acc = 0
  let mut src = 0
  let mut dst = 0
  for chunk in payload {
    for ch in chunk {
      let c = ch.to_int()
      if c == ','.to_int() {
        if field == 0 {
          src = acc
        } else {
          dst = acc
        }
        field = field + 1
        acc = 0
      } else if c == ';'.to_int() {
        edges[ei] = (src, dst, acc)
        redges[ei] = (dst, src, acc)
        ei = ei + 1
        field = 0
        acc = 0
      } else {
        acc = acc * 10 + (c - '0'.to_int())
      }
    }
  }
  edges[ei] = (src, dst, acc)
  redges[ei] = (dst, src, acc)
  (
    @dir.WeightedCsr::from_edges(n, edges),
    @dir.WeightedCsr::from_edges(n, redges),
  )
}

///|
/// 真实路网 ALT vs 双向 Dijkstra 采集主体：返回（Markdown 证据, 中位加速比）。
fn run_osm_alt_benchmark_on(
  dataset : String,
  n : Int,
  edge_count : Int,
  payload : Array[String],
  qcount : Int,
  warmup : Int,
  samples : Int,
  k : Int,
) -> (String, Double) {
  let (g, rg) = build_osm_weighted_csr(n, edge_count, payload)
  let qrng = Lcg::new(query_seed_int)
  let queries : Array[(Int, Int)] = []
  for _ in 0..<qcount {
    queries.push((qrng.next() % n, qrng.next() % n))
  }
  let mut ch_opt : @dir.ContractionHierarchy? = None
  let ch_pre_us = elapsed(fn() {
    ch_opt = Some(@dir.ContractionHierarchy::build(g))
  })
  let ch = ch_opt.unwrap()
  let mut hl_opt : @dir.HubLabels? = None
  let hl_pre_us = elapsed(fn() { hl_opt = Some(@dir.HubLabels::build(ch)) })
  let hl = hl_opt.unwrap()
  let mut alt_opt : @dir.AltLandmarks? = None
  let pre_us = elapsed(fn() {
    alt_opt = Some(@dir.AltLandmarks::build(g, rg, k))
  })
  let alt = alt_opt.unwrap()
  let cf = @dir.SearchCtx::new(n)
  let cb = @dir.SearchCtx::new(n)
  // 代价全量对拍守卫。
  let mut parity_ok = true
  for q in queries {
    let (s, t) = q
    let a = @dir.dijkstra_bidirectional_ctx(g, rg, cf, cb, s, t)
    let b = @dir.astar_bidirectional_ctx(
      g,
      rg,
      cf,
      cb,
      s,
      t,
      alt.h_to_closure(t),
      alt.h_from_closure(s),
    )
    let c = ch.query(s, t)
    match (a, b, c) {
      (Some((_, x)), Some((_, y)), Some((_, z))) =>
        if x != y || x != z {
          parity_ok = false
        }
      (None, None, None) => ()
      _ => parity_ok = false
    }
    match (a, hl.query(s, t)) {
      (Some((_, x)), Some(d)) => if x.to_int64() != d { parity_ok = false }
      (None, None) => ()
      _ => parity_ok = false
    }
  }
  let sink : Array[Int] = [0]
  let uni_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match @dir.dijkstra_indexed_ctx(g, cf, q.0, q.1) {
        Some((_, c)) => sink[0] = sink[0] + c
        None => ()
      }
    }
  })
  let dij_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match @dir.dijkstra_bidirectional_ctx(g, rg, cf, cb, q.0, q.1) {
        Some((_, c)) => sink[0] = sink[0] + c
        None => ()
      }
    }
  })
  let alt_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      let (s, t) = q
      match
        @dir.astar_bidirectional_ctx(
          g,
          rg,
          cf,
          cb,
          s,
          t,
          alt.h_to_closure(t),
          alt.h_from_closure(s),
        ) {
        Some((_, c)) => sink[0] = sink[0] + c
        None => ()
      }
    }
  })
  let ch_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match ch.query(q.0, q.1) {
        Some((_, c)) => sink[0] = sink[0] + c
        None => ()
      }
    }
  })
  let sink64 : Array[Int64] = [0L]
  let hl_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match hl.query(q.0, q.1) {
        Some(d) => sink64[0] = sink64[0] + d
        None => ()
      }
    }
  })
  // 一到全 SSSP：PHAST vs 全量 Dijkstra（各 16 源，同源集）。
  let sssp_src : Array[Int] = []
  for i in 0..<16 {
    sssp_src.push(queries[i % queries.length()].0)
  }
  let dist_a = Array::make(n, 0L)
  let dist_b = Array::make(n, 0L)
  let mut sssp_parity = true
  for s in sssp_src {
    @dir.dijkstra_one_to_all(g, s, dist_a)
    ch.one_to_all(s, dist_b)
    for v in 0..<n {
      if dist_a[v] != dist_b[v] {
        sssp_parity = false
        break
      }
    }
  }
  let full_dij_samples = collect_samples(warmup, samples, fn() {
    for s in sssp_src {
      @dir.dijkstra_one_to_all(g, s, dist_a)
      sink64[0] = sink64[0] + dist_a[n - 1]
    }
  })
  let phast_samples = collect_samples(warmup, samples, fn() {
    for s in sssp_src {
      ch.one_to_all(s, dist_b)
      sink64[0] = sink64[0] + dist_b[n - 1]
    }
  })
  ignore(sink[0])
  ignore(sink64[0])
  let full_dij_med = csr_bench_median(full_dij_samples)
  let phast_med = csr_bench_median(phast_samples)
  let hl_med = csr_bench_median(hl_samples)
  let ch_med = csr_bench_median(ch_samples)
  let uni_med = csr_bench_median(uni_samples)
  let dij_med = csr_bench_median(dij_samples)
  let alt_med = csr_bench_median(alt_samples)
  let speedup = if alt_med > 0.0 { dij_med / alt_med } else { 0.0 }
  let qd = qcount.to_double()
  let tb = @infra_text.TextBuilder::new()
  tb.push_str(
    "# ALT(indexed) vs 双向 Dijkstra — 真实 OSM 路网基准（\{dataset}）\n\n",
  )
  tb.push_str(
    "- 数据集: OpenStreetMap \{dataset}（osmnx 提取，权重=道路分米）\n",
  )
  tb.push_str(
    "- 节点数: \{n}; 有向边数: \{edge_count}; 地标数 k=\{k}\n",
  )
  tb.push_str("- 查询对: \{qcount}; 预热: \{warmup}; 采样: \{samples}\n")
  tb.push_str("- 代价对拍全一致: \{parity_ok}\n")
  tb.push_str(
    "- ALT 预处理耗时: \{pre_us / 1.0e3} ms（(2k+1) 次全量 Dijkstra）\n",
  )
  tb.push_str("- 单向 Dijkstra 每查询中位耗时: \{uni_med / qd} µs\n")
  tb.push_str(
    "- 双向 Dijkstra 每查询中位耗时: \{dij_med / qd} µs（大权堆式双向，相对单向 \{uni_med / dij_med}×）\n",
  )
  tb.push_str("- ALT 双向 A* 每查询中位耗时: \{alt_med / qd} µs\n")
  tb.push_str("- 中位加速比: \{speedup}x\n")
  tb.push_str(
    "- CH 预处理耗时: \{ch_pre_us / 1.0e3} ms; CH 每查询中位耗时: \{ch_med / qd} µs（相对双向 Dijkstra \{dij_med / ch_med}×、相对 ALT \{alt_med / ch_med}×）\n",
  )
  tb.push_str(
    "- HL 预处理耗时: \{hl_pre_us / 1.0e3} ms; 平均标签长: \{hl.avg_label_size()}; HL 每查询中位耗时: \{hl_med / qd} µs（相对 CH \{ch_med / hl_med}×、相对双向 Dijkstra \{dij_med / hl_med}×）\n",
  )
  tb.push_str(
    "- 一到全对拍一致: \{sssp_parity}; 全量 Dijkstra 每源: \{full_dij_med / 16.0} µs; PHAST 每源: \{phast_med / 16.0} µs（**\{full_dij_med / phast_med}×**）\n",
  )
  if !parity_ok {
    tb.push_str(
      "\n**警告：代价对拍存在不一致，加速比无效。**\n",
    )
  }
  (tb.build(), speedup)
}

///|
test "bench: collect real OSM road-network ALT artifacts" (b : @bench.T) {
  let (xm_md, xm_speedup) = run_osm_alt_benchmark_on(
    "厦门驾车网", osm_xiamen_node_count, osm_xiamen_edge_count, osm_xiamen_payload,
    osm_bench_queries, csr_bench_warmup, csr_bench_samples, 8,
  )
  let (bj_md, bj_speedup) = run_osm_alt_benchmark_on(
    "北京驾车网", osm_beijing_node_count, osm_beijing_edge_count, osm_beijing_payload,
    osm_bench_queries, csr_bench_warmup, csr_bench_samples, 16,
  )
  println("===OSM_ALT_EVIDENCE_BEGIN===")
  println(xm_md)
  println(bj_md)
  println("===OSM_ALT_EVIDENCE_END===")
  b.bench(name="osm_alt_artifacts_emitted", fn() {
    b.keep(xm_md.length() + bj_md.length() + (xm_speedup + bj_speedup).to_int())
  })
}

///|
test "guard: 真实 OSM 路网 ALT 代价对拍（前 8 组）" {
  let (g, rg) = build_osm_weighted_csr(
    osm_xiamen_node_count, osm_xiamen_edge_count, osm_xiamen_payload,
  )
  let alt = @dir.AltLandmarks::build(g, rg, 4)
  let cf = @dir.SearchCtx::new(osm_xiamen_node_count)
  let cb = @dir.SearchCtx::new(osm_xiamen_node_count)
  let qrng = Lcg::new(query_seed_int)
  for _ in 0..<8 {
    let s = qrng.next() % osm_xiamen_node_count
    let t = qrng.next() % osm_xiamen_node_count
    let a = @dir.dijkstra_bidirectional_ctx(g, rg, cf, cb, s, t)
    let b = @dir.astar_bidirectional_ctx(
      g,
      rg,
      cf,
      cb,
      s,
      t,
      fn(v) { alt.h_to(v, t) },
      fn(v) { alt.h_from(v, s) },
    )
    let same = match (a, b) {
      (Some((_, x)), Some((_, y))) => x == y
      (None, None) => true
      _ => false
    }
    assert_true(same)
  }
}
