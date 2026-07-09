// graph_bench_proof_test.mbt —— 图容器/基准统计/模糊收缩/文档生成家族
// 证明谓词的真实实现接地测试。
//
// 以 @graph / @infra_bench / @infra_fuzz / @docgen 的真实包实现驱动
// graph_bench_proof.mbt 中的谓词（跨包驱动只发生在测试期）：
//   * synthetic_grid_csr：CSR 边端点封闭在 [0, n)（多尺寸网格）；
//   * fuzz_graph_gen：随机图端点封闭；shrink_fuzz_graph：收缩良基
//     （每个候选规模严格递减，PBT 驱动）；
//   * compute_stats：min ≤ median ≤ p95 ≤ max 排序律 + mean 夹逼；
//   * BenchReport：to_json ∘ from_json 往返恒等；
//   * complexity_table：包含全部注册算法名（contains_all 复用）。

// --- graph：CSR 端点封闭 ---

///|
fn gb_csr_edges(g : @graph.CsrGraph[Double]) -> Array[(Int, Int)] {
  let edges : Array[(Int, Int)] = []
  for u in 0..<g.n {
    let mut i = g.row_ptr[u]
    while i < g.row_ptr[u + 1] {
      edges.push((u, g.col_idx[i]))
      i += 1
    }
  }
  edges
}

///|
test "synthetic grid CSR endpoints stay within the node domain" {
  for dims in [(1, 1), (2, 3), (4, 4), (5, 2)] {
    let (rows, cols) = dims
    match @graph.synthetic_grid_csr(rows, cols, 1.5) {
      Ok(g) => assert_true(endpoints_in_range(gb_csr_edges(g), g.n))
      Err(e) => abort("grid \{rows}x\{cols}: \{e.message()}")
    }
  }
}

///|
test "endpoints_in_range rejects an out-of-domain endpoint" {
  assert_false(endpoints_in_range([(0, 3)], 3))
  assert_false(endpoints_in_range([(-1, 0)], 3))
}

// --- infra_fuzz：随机图端点封闭 + 收缩良基 ---

///|
fn gb_fuzz_size(g : @infra_fuzz.FuzzGraph) -> Int {
  g.n + g.edges.length()
}

///|
fn gb_prop_fuzz_graph_invariants(g : @infra_fuzz.FuzzGraph) -> Bool {
  let endpoints : Array[(Int, Int)] = []
  for e in g.edges {
    endpoints.push((e.0, e.1))
  }
  if !endpoints_in_range(endpoints, g.n) {
    return false
  }
  // 收缩良基：每个候选规模严格小于原件。
  let sizes : Array[Int] = []
  for cand in @infra_fuzz.shrink_fuzz_graph(g) {
    sizes.push(gb_fuzz_size(cand))
  }
  all_strictly_less(sizes, gb_fuzz_size(g))
}

///|
test "fuzz graphs are well-formed and shrinking is well-founded" {
  let ok = @infra_pbt.holds_for_all(
    @infra_fuzz.fuzz_graph_gen(12, 30),
    gb_prop_fuzz_graph_invariants,
    iters=128,
  )
  assert_true(ok)
}

///|
test "all_strictly_less rejects a non-shrinking candidate" {
  assert_false(all_strictly_less([4, 5], 5))
}

// --- infra_bench：统计量排序律 + 报告 JSON 往返 ---

///|
fn gb_samples_gen() -> @infra_pbt.Gen[Array[Double]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 48)
    let out : Array[Double] = []
    for _i in 0..<n {
      out.push(rng.next_range(1, 1_000_000).to_double())
    }
    out
  })
}

///|
fn gb_prop_stats_ordered(samples : Array[Double]) -> Bool {
  match @infra_bench.compute_stats(samples) {
    Ok(s) =>
      non_decreasing_f([s.min, s.median, s.p95, s.max]) &&
      s.mean >= s.min &&
      s.mean <= s.max &&
      s.stddev >= 0.0 &&
      s.sample_count == samples.length()
    Err(_) => false
  }
}

///|
test "bench stats satisfy ordering laws over random samples" {
  let ok = @infra_pbt.holds_for_all(
    gb_samples_gen(),
    gb_prop_stats_ordered,
    iters=128,
  )
  assert_true(ok)
}

///|
test "BenchReport to_json/from_json round-trips" {
  let stats = match @infra_bench.compute_stats([100.0, 200.0, 300.0]) {
    Ok(s) => s
    Err(e) => abort(e.message())
  }
  let report : @infra_bench.BenchReport = {
    moon_version: "0.1.20260703",
    backend: "native",
    os: "linux",
    cpu: "x86_64",
    generator: "grid",
    warmup_count: 3,
    cases: [
      {
        algorithm: "dijkstra",
        graph_size: 100,
        edge_count: 360,
        query_count: 10,
        seed: 42,
        raw_ns: [100.0, 200.0, 300.0],
        stats,
      },
    ],
  }
  assert_true(
    round_trip_eq(
      report,
      fn(r : @infra_bench.BenchReport) -> String { r.to_json() },
      fn(json : String) -> @infra_bench.BenchReport? {
        match @infra_bench.BenchReport::from_json(json) {
          Ok(r) => Some(r)
          Err(_) => None
        }
      },
    ),
  )
}

// --- docgen：复杂度表完备性 ---

///|
test "complexity table mentions every registered algorithm" {
  let metas = @docgen.algorithm_metadata()
  let names : Array[String] = []
  for m in metas {
    names.push(m.name)
  }
  match @docgen.complexity_table(metas) {
    Ok(table) => assert_true(contains_all(table, names))
    Err(e) => abort(e.message())
  }
}
