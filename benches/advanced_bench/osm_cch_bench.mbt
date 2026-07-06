// osm_cch_bench.mbt —— 真实 OSM 路网上的 Customizable CH 基准。
//
// CCH 的卖点不是查询更快（其骨架无 witness 剪枝、比 CH 密），而是
// **换权重只需 customization 而非整套重建**。本基准量三件事：
//   1. 度量无关构建耗时（一次性，可跨权重复用）；
//   2. customization 耗时（换权成本）vs CH 全量重建耗时（对比项）；
//   3. CCH 查询耗时 vs CH / 双向 Dijkstra（代价全量对拍护栏，含换权
//      后再 customize 的第二轮对拍）。
// 执行约定与 osm_alt_bench.mbt 一致（预热/采样/中位数）。

///|
/// 单数据集采集主体：返回 Markdown 证据。
fn run_osm_cch_benchmark_on(
  dataset : String,
  n : Int,
  edge_count : Int,
  payload : Array[String],
  qcount : Int,
  warmup : Int,
  samples : Int,
) -> String {
  let (g, rg) = build_osm_weighted_csr(n, edge_count, payload)
  let qrng = Lcg::new(query_seed_int)
  let queries : Array[(Int, Int)] = []
  for _ in 0..<qcount {
    queries.push((qrng.next() % n, qrng.next() % n))
  }
  // CH 全量重建耗时（换权时 CH 的必付成本，对比项）。
  let mut ch_opt : @dir.ContractionHierarchy? = None
  let ch_pre_us = elapsed(fn() {
    ch_opt = Some(@dir.ContractionHierarchy::build(g))
  })
  let ch = ch_opt.unwrap()
  // CCH 度量无关构建（含首次 customize）。
  let mut cch_opt : @dir.CustomizableCch? = None
  let cch_build_us = elapsed(fn() {
    cch_opt = Some(@dir.CustomizableCch::build(g))
  })
  let cch = cch_opt.unwrap()
  // 换权成本：customization 单独计时（中位数）。
  let cust_samples = collect_samples(warmup, samples, fn() { cch.customize(g) })
  let cust_med = csr_bench_median(cust_samples)
  // 代价全量对拍护栏（原权重）。
  let cf = @dir.SearchCtx::new(n)
  let cb = @dir.SearchCtx::new(n)
  let mut parity_ok = true
  for q in queries {
    let (s, t) = q
    let a = @dir.dijkstra_bidirectional_ctx(g, rg, cf, cb, s, t)
    match (a, cch.query_dist(s, t), ch.query(s, t)) {
      (Some((_, x)), Some(y), Some((_, z))) =>
        if x.to_int64() != y || x != z {
          parity_ok = false
        }
      (None, None, None) => ()
      _ => parity_ok = false
    }
  }
  // 查询耗时：双向 Dijkstra / CH / CCH。
  let sink : Array[Int64] = [0L]
  let dij_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match @dir.dijkstra_bidirectional_ctx(g, rg, cf, cb, q.0, q.1) {
        Some((_, c)) => sink[0] = sink[0] + c.to_int64()
        None => ()
      }
    }
  })
  let ch_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match ch.query(q.0, q.1) {
        Some((_, c)) => sink[0] = sink[0] + c.to_int64()
        None => ()
      }
    }
  })
  let cch_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match cch.query_dist(q.0, q.1) {
        Some(c) => sink[0] = sink[0] + c
        None => ()
      }
    }
  })
  let dij_med = csr_bench_median(dij_samples)
  let ch_med = csr_bench_median(ch_samples)
  let cch_med = csr_bench_median(cch_samples)
  let qd = qcount.to_double()
  // 换权重（全边权 ×3+7 扰动）后 customize，再对拍守卫语义。
  let edges2 : Array[(Int, Int, Int)] = []
  let mask = (1L << 21) - 1L
  for u in 0..<n {
    let stop = g.offsets[u + 1]
    for ei = g.offsets[u]; ei < stop; ei = ei + 1 {
      let pe = g.packed[ei]
      let v = (pe & mask).to_int()
      let w = (pe >> 21).to_int()
      edges2.push((u, v, w * 3 + 7))
    }
  }
  let g2 = @dir.WeightedCsr::from_edges(n, edges2)
  let rg2edges : Array[(Int, Int, Int)] = []
  for e in edges2 {
    rg2edges.push((e.1, e.0, e.2))
  }
  let rg2 = @dir.WeightedCsr::from_edges(n, rg2edges)
  let recust_us = elapsed(fn() { cch.customize(g2) })
  let mut parity2_ok = true
  for q in queries {
    let (s, t) = q
    let a = @dir.dijkstra_bidirectional_ctx(g2, rg2, cf, cb, s, t)
    match (a, cch.query_dist(s, t)) {
      (Some((_, x)), Some(y)) => if x.to_int64() != y { parity2_ok = false }
      (None, None) => ()
      _ => parity2_ok = false
    }
  }
  cch.customize(g)
  // 嵌套剖分收缩序变体：对比填充规模 / customization / 查询。
  let mut cch_nd_opt : @dir.CustomizableCch? = None
  let nd_build_us = elapsed(fn() {
    cch_nd_opt = Some(
      @dir.CustomizableCch::build_with_order(g, @dir.cch_nd_order(g)),
    )
  })
  let cch_nd = cch_nd_opt.unwrap()
  let nd_cust_samples = collect_samples(warmup, samples, fn() {
    cch_nd.customize(g)
  })
  let nd_cust_med = csr_bench_median(nd_cust_samples)
  let mut parity_nd_ok = true
  for q in queries {
    let (s, t) = q
    let a = @dir.dijkstra_bidirectional_ctx(g, rg, cf, cb, s, t)
    match (a, cch_nd.query_dist(s, t)) {
      (Some((_, x)), Some(y)) => if x.to_int64() != y { parity_nd_ok = false }
      (None, None) => ()
      _ => parity_nd_ok = false
    }
  }
  let nd_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match cch_nd.query_dist(q.0, q.1) {
        Some(c) => sink[0] = sink[0] + c
        None => ()
      }
    }
  })
  let nd_med = csr_bench_median(nd_samples)
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("### \{dataset}（节点 \{n}，边 \{edge_count}）CCH\n\n")
  tb.push_str(
    "- 代价对拍一致（原权重）: \{parity_ok}; 换权重后: \{parity2_ok}\n",
  )
  tb.push_str(
    "- CH 全量重建: \{ch_pre_us / 1.0e3} ms; CCH 度量无关构建（含首次 customize）: \{cch_build_us / 1.0e3} ms\n",
  )
  tb.push_str(
    "- **customization（换权成本）中位: \{cust_med / 1.0e3} ms（相对 CH 重建 \{ch_pre_us / cust_med}×）**; 实测换权再绑: \{recust_us / 1.0e3} ms\n",
  )
  tb.push_str(
    "- 每查询中位: 双向 Dijkstra \{dij_med / qd} µs; CH \{ch_med / qd} µs; CCH \{cch_med / qd} µs（相对双向 Dijkstra \{dij_med / cch_med}×、相对 CH \{cch_med / ch_med}× 慢因子）\n",
  )
  tb.push_str(
    "- ND 收缩序变体: 对拍一致 \{parity_nd_ok}; 构建 \{nd_build_us / 1.0e3} ms; 骨架边 \{cch_nd.edge_count()}（min-degree \{cch.edge_count()}）; customization 中位 \{nd_cust_med / 1.0e3} ms; 每查询 \{nd_med / qd} µs\n",
  )
  if !parity_ok || !parity2_ok || !parity_nd_ok {
    tb.push_str(
      "\n**警告：代价对拍存在不一致，数字无效。**\n",
    )
  }
  tb.build()
}

///|
test "bench: collect real OSM road-network CCH artifacts" (b : @bench.T) {
  let xm_md = run_osm_cch_benchmark_on(
    "厦门驾车网", osm_xiamen_node_count, osm_xiamen_edge_count, osm_xiamen_payload,
    osm_bench_queries, csr_bench_warmup, csr_bench_samples,
  )
  let bj_md = run_osm_cch_benchmark_on(
    "北京驾车网", osm_beijing_node_count, osm_beijing_edge_count, osm_beijing_payload,
    osm_bench_queries, csr_bench_warmup, csr_bench_samples,
  )
  println("===OSM_CCH_EVIDENCE_BEGIN===")
  println(xm_md)
  println(bj_md)
  println("===OSM_CCH_EVIDENCE_END===")
  b.bench(name="osm_cch_artifacts_emitted", fn() {
    b.keep(xm_md.length() + bj_md.length())
  })
}

///|
test "guard: 真实 OSM 路网 CCH 代价对拍（前 8 组，含换权 customize）" {
  let (g, rg) = build_osm_weighted_csr(
    osm_xiamen_node_count, osm_xiamen_edge_count, osm_xiamen_payload,
  )
  let cch = @dir.CustomizableCch::build(g)
  let cf = @dir.SearchCtx::new(osm_xiamen_node_count)
  let cb = @dir.SearchCtx::new(osm_xiamen_node_count)
  let qrng = Lcg::new(query_seed_int)
  for _ in 0..<8 {
    let s = qrng.next() % osm_xiamen_node_count
    let t = qrng.next() % osm_xiamen_node_count
    let a = @dir.dijkstra_bidirectional_ctx(g, rg, cf, cb, s, t)
    match (a, cch.query_dist(s, t)) {
      (Some((_, x)), Some(y)) => assert_eq(x.to_int64(), y)
      (None, None) => ()
      _ => abort("reachability mismatch")
    }
  }
}
