// osm_showcase_bench.mbt —— 真实 OSM 路网端到端 showcase（数据→CH→路径→逐边校验）。
//
// 与 osm_ch_bench.mbt 的"代价对拍"不同，本切片验证的是**路径级**闭环：
//   1. 嵌入的真实厦门驾车网负载解析为 CSR；
//   2. CH 预处理后 `ch_csr_query` 展开完整节点路径；
//   3. 每条路径逐边核验：相邻节点间的边必须真实存在于原图 CSR，
//      且逐边权重求和与查询代价、与 Dijkstra 独立代价三方一致；
//   4. 汇总输出 Markdown 证据（路径条数、总跳数、最长路径样例）。
// 这补齐了"真实数据端到端"证据链中从代价到可行驶路径的最后一环。

///|
/// 在原图 CSR 中查 u→v 的最小边权；不存在返回 None。
fn csr_edge_weight(g : @graph.CsrGraph[Double], u : Int, v : Int) -> Double? {
  let mut best : Double? = None
  for k in g.row_ptr[u]..<g.row_ptr[u + 1] {
    if g.col_idx[k] == v {
      match best {
        Some(b) => if g.weights[k] < b { best = Some(g.weights[k]) }
        None => best = Some(g.weights[k])
      }
    }
  }
  best
}

///|
/// 端到端 showcase 主体：返回（Markdown 证据, 全部路径校验通过）。
fn run_osm_showcase() -> (String, Bool) {
  let g = build_osm_csr()
  let n = g.n
  let ch = @advanced.ch_csr_preprocess(g)
  let dij = CsrDijkstra::new(g)
  let qrng = Lcg::new(query_seed_int)
  let qcount = 32
  let mut ok = true
  let mut reachable = 0
  let mut total_hops = 0
  let mut max_hops = 0
  let mut max_pair = (0, 0)
  let mut max_cost = 0.0
  for _ in 0..<qcount {
    let s = qrng.next() % n
    let t = qrng.next() % n
    match @advanced.ch_csr_query(ch, s, t) {
      Some((path, cost)) => {
        reachable = reachable + 1
        // 路径端点正确。
        if path.length() < 1 || path[0] != s || path[path.length() - 1] != t {
          ok = false
        }
        // 逐边存在性 + 权重求和。
        let mut sum = 0.0
        for i in 0..<(path.length() - 1) {
          match csr_edge_weight(g, path[i], path[i + 1]) {
            Some(w) => sum = sum + w
            None => ok = false
          }
        }
        if sum != cost {
          ok = false
        }
        // 与独立 Dijkstra 代价三方一致。
        match dij.query(s, t) {
          Some(d) => if d != cost { ok = false }
          None => ok = false
        }
        let hops = path.length() - 1
        total_hops = total_hops + hops
        if hops > max_hops {
          max_hops = hops
          max_pair = (s, t)
          max_cost = cost
        }
      }
      None =>
        // CH 不可达必须与 Dijkstra 不可达一致。
        if dij.query(s, t) is Some(_) {
          ok = false
        }
    }
  }
  let tb = @infra_text.TextBuilder::new()
  tb.push_str(
    "# 真实 OSM 路网端到端 showcase（厦门驾车网，路径级校验）\n\n",
  )
  tb.push_str(
    "- 数据集: OpenStreetMap 厦门驾车网（osmnx 提取，权重=道路分米）\n",
  )
  tb.push_str("- 节点数: \{n}; 有向边数: \{g.col_idx.length()}\n")
  tb.push_str("- 随机查询对: \{qcount}; 可达: \{reachable}\n")
  tb.push_str(
    "- 路径级校验（端点/逐边存在/权重求和=代价=Dijkstra）: \{ok}\n",
  )
  tb.push_str("- 可达路径总跳数: \{total_hops}\n")
  tb.push_str(
    "- 最长路径样例: \{max_pair.0}→\{max_pair.1}，\{max_hops} 跳，代价 \{max_cost} 分米（约 \{max_cost / 10000.0} km）\n",
  )
  (tb.build(), ok)
}

///|
test "bench: real OSM end-to-end path showcase" (b : @bench.T) {
  let (md, ok) = run_osm_showcase()
  println("===OSM_SHOWCASE_EVIDENCE_BEGIN===")
  println(md)
  println("===OSM_SHOWCASE_EVIDENCE_END===")
  assert_true(ok)
  b.bench(name="osm_showcase_emitted", fn() { b.keep(md.length()) })
}
