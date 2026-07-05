// osm_ch_bench.mbt —— 真实 OSM 路网（厦门驾车网）上的 CH vs Dijkstra 基准。
//
// 与 ch_csr_bench.mbt 同一执行约定与统计口径（预热 ≥3、采样 ≥12、中位加速比、
// 全查询代价对拍护栏），但数据集换成 **真实 OpenStreetMap 驾车路网**
// （benches/osm/download.sh 经 osmnx 提取，权重为道路米长 ×10 的整数分米），
// 补齐 R21.1 的「真实路网」证据缺口（合成网格证据见 ch_csr_bench.mbt）。

///|
/// 真实路网查询对数量。
let osm_bench_queries : Int = 48

///|
/// 解析嵌入负载为 CSR（`src,dst,分米` 分号分隔；跨块字符串无缝拼接）。
fn build_osm_csr() -> @graph.CsrGraph[Double] {
  let n = osm_xiamen_node_count
  let srcs : Array[Int] = Array::make(osm_xiamen_edge_count, 0)
  let dsts : Array[Int] = Array::make(osm_xiamen_edge_count, 0)
  let ws : Array[Double] = Array::make(osm_xiamen_edge_count, 0.0)
  let mut ei = 0
  let mut field = 0 // 0=src 1=dst 2=weight
  let mut acc = 0
  for chunk in osm_xiamen_payload {
    for ch in chunk {
      let c = ch.to_int()
      if c == ','.to_int() {
        if field == 0 {
          srcs[ei] = acc
        } else {
          dsts[ei] = acc
        }
        field = field + 1
        acc = 0
      } else if c == ';'.to_int() {
        ws[ei] = acc.to_double()
        ei = ei + 1
        field = 0
        acc = 0
      } else {
        acc = acc * 10 + (c - '0'.to_int())
      }
    }
  }
  // 末条边无结尾分号。
  ws[ei] = acc.to_double()
  ei = ei + 1
  let cnt : Array[Int] = Array::make(n, 0)
  for k in 0..<ei {
    cnt[srcs[k]] = cnt[srcs[k]] + 1
  }
  let row_ptr : Array[Int] = Array::make(n + 1, 0)
  for i in 0..<n {
    row_ptr[i + 1] = row_ptr[i] + cnt[i]
  }
  let m = row_ptr[n]
  let col_idx : Array[Int] = Array::make(m, 0)
  let weights : Array[Double] = Array::make(m, 0.0)
  let fill : Array[Int] = Array::make(n, 0)
  for k in 0..<ei {
    let u = srcs[k]
    let pos = row_ptr[u] + fill[u]
    col_idx[pos] = dsts[k]
    weights[pos] = ws[k]
    fill[u] = fill[u] + 1
  }
  { n, row_ptr, col_idx, weights }
}

///|
/// 真实路网 CH vs Dijkstra 采集主体：返回（Markdown 证据, 中位加速比）。
fn run_osm_ch_benchmark(
  qcount : Int,
  warmup : Int,
  samples : Int,
) -> (String, Double) {
  let g = build_osm_csr()
  let n = g.n
  let qrng = Lcg::new(query_seed_int)
  let queries : Array[(Int, Int)] = []
  for _ in 0..<qcount {
    queries.push((qrng.next() % n, qrng.next() % n))
  }
  let mut ch_opt : @advanced.ChCsr? = None
  let pre_us = elapsed(fn() { ch_opt = Some(@advanced.ch_csr_preprocess(g)) })
  let ch = ch_opt.unwrap()
  let dij = CsrDijkstra::new(g)
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
  let sink : Array[Double] = [0.0]
  let dij_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match dij.query(q.0, q.1) {
        Some(c) => sink[0] = sink[0] + c
        None => ()
      }
    }
  })
  let ch_samples = collect_samples(warmup, samples, fn() {
    for q in queries {
      match @advanced.ch_csr_query_cost(ch, q.0, q.1) {
        Some(c) => sink[0] = sink[0] + c
        None => ()
      }
    }
  })
  ignore(sink[0])
  let dij_med = csr_bench_median(dij_samples)
  let ch_med = csr_bench_median(ch_samples)
  let speedup = if ch_med > 0.0 { dij_med / ch_med } else { 0.0 }
  let qd = qcount.to_double()
  let tb = @infra_text.TextBuilder::new()
  tb.push_str(
    "# CH(CSR) vs Dijkstra — 真实 OSM 路网基准（厦门驾车网，R21.1）\n\n",
  )
  tb.push_str(
    "- 数据集: OpenStreetMap 厦门驾车路网（osmnx 提取，权重=道路米长）\n",
  )
  tb.push_str("- 节点数: \{n}; 有向边数: \{g.col_idx.length()}\n")
  tb.push_str("- 查询对: \{qcount}; 预热: \{warmup}; 采样: \{samples}\n")
  tb.push_str(
    "- CH 层级图边数: up=\{ch.up_row[ch.n]} dn=\{ch.dn_row[ch.n]}\n",
  )
  tb.push_str("- 代价对拍全一致: \{parity_ok}\n")
  tb.push_str("- CH 预处理耗时: \{pre_us / 1.0e3} ms\n")
  tb.push_str("- Dijkstra 每查询中位耗时: \{dij_med / qd} µs\n")
  tb.push_str("- CH 每查询中位耗时（代价）: \{ch_med / qd} µs\n")
  tb.push_str("- 中位加速比: \{speedup}x\n")
  if !parity_ok {
    tb.push_str(
      "\n**警告：代价对拍存在不一致，加速比无效。**\n",
    )
  }
  (tb.build(), speedup)
}

///|
test "bench: collect real OSM road-network CH artifacts" (b : @bench.T) {
  let (evidence_md, speedup) = run_osm_ch_benchmark(
    osm_bench_queries, csr_bench_warmup, csr_bench_samples,
  )
  println("===OSM_CH_EVIDENCE_BEGIN===")
  println(evidence_md)
  println("===OSM_CH_EVIDENCE_END===")
  b.bench(name="osm_ch_artifacts_emitted", fn() {
    b.keep(evidence_md.length() + speedup.to_int())
  })
}

///|
test "guard: 真实 OSM 路网解析结构 + CH 代价对拍" {
  let g = build_osm_csr()
  assert_true(g.n == osm_xiamen_node_count)
  assert_true(g.col_idx.length() == osm_xiamen_edge_count)
  // 小规模对拍：前 8 组查询代价一致即可（全量对拍在 bench 块）。
  let ch = @advanced.ch_csr_preprocess(g)
  let dij = CsrDijkstra::new(g)
  let qrng = Lcg::new(query_seed_int)
  for _ in 0..<8 {
    let s = qrng.next() % g.n
    let t = qrng.next() % g.n
    let a = dij.query(s, t)
    let c = @advanced.ch_csr_query_cost(ch, s, t)
    let same = match (a, c) {
      (Some(x), Some(y)) => x == y
      (None, None) => true
      _ => false
    }
    assert_true(same)
  }
}
