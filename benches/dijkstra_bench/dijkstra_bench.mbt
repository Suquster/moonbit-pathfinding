// benches/dijkstra_bench — native benchmark and smoke guard for `@dir.dijkstra`.
//
// Uses the same 1k-node sparse graph construction as `bfs_bench.mbt`, but
// attaches a non-negative integer weight to every edge so Dijkstra has
// something to relax on. The LCG block is intentionally duplicated so each
// benchmark package stays self-contained.
//
// _Requirements: 14.1, 14.2_

///|
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

///|
/// 1 000-node adjacency with `(neighbor, weight)` pairs. Weights are
/// uniformly sampled from `[1, max_w]` to avoid zero-weight ties that make
/// tie-breaking dominate the wall-clock measurement.
fn build_sparse_weighted_adj(
  seed : Int,
  n : Int,
  density : Double,
  max_w : Int,
) -> Array[Array[(Int, Int)]] {
  let rng = Lcg::new(seed)
  let adj : Array[Array[(Int, Int)]] = Array::makei(n, fn(_) { [] })
  for u in 0..<n {
    for v in 0..<n {
      if u == v {
        continue
      }
      let r = rng.next().to_double() / 2147483648.0
      if r < density {
        // w ∈ [1, max_w]
        let w = 1 + rng.next() % max_w
        adj[u].push((v, w))
      }
    }
  }
  adj
}

///|
/// Smoke guard: Dijkstra from node 0 to node n-1 on a 1k-node, ~1%-density
/// weighted digraph with edge weights in [1, 10].
test "smoke: dijkstra on 1k-node sparse weighted graph (density 1%)" {
  let n = 1000
  let adj = build_sparse_weighted_adj(7, n, 0.01, 10)
  let result = @dir.dijkstra(0, fn(u) { adj[u] }, fn(v) { v == n - 1 })
  match result {
    Some((p, cost)) => {
      assert_true(p.length() >= 1)
      assert_true(p[0] == 0)
      assert_true(p[p.length() - 1] == n - 1)
      // Non-negative weights ⇒ non-negative cost.
      assert_true(cost >= 0)
    }
    None => assert_true(true)
  }
}

///|
/// Native benchmark: measure only repeated Dijkstra calls over a prebuilt graph.
test "bench: dijkstra on 1k-node sparse weighted graph (density 1%)" (
  b : @bench.T,
) {
  let n = 1000
  let adj = build_sparse_weighted_adj(7, n, 0.01, 10)
  b.bench(name="dijkstra_1k_sparse_density_1pct", fn() {
    b.keep(@dir.dijkstra(0, fn(u) { adj[u] }, fn(v) { v == n - 1 }))
  })
}

///|
test "bench: indexed flat-array dijkstra/bfs vs generic Map-based (n=1000, deg=16, 100 queries)" (
  b : @bench.T,
) {
  // Rust 对比矩阵同款负载：n=1000、平均出度 16、100 条随机查询。
  // indexed 版：CSR 邻接 + 扁平 dist/parent 数组 + 编码二叉堆（无哈希
  // 无装箱）；generic 版：Map[N,W] + 泛型 PQueue（本库通用 API）。
  let n = 1000
  let m = n * 16
  let mut seed = 0x123456789ABCDEFUL
  fn nxt() -> UInt64 {
    seed = seed ^ (seed << 13)
    seed = seed ^ (seed >> 7)
    seed = seed ^ (seed << 17)
    seed
  }

  let edges3 : Array[(Int, Int, Int)] = []
  for _ in 0..<m {
    let u = (nxt() % 1000UL).to_int()
    let mut v = (nxt() % 1000UL).to_int()
    if v == u {
      v = (u + 1) % n
    }
    edges3.push((u, v, 1 + (nxt() % 100UL).to_int()))
  }
  let queries : Array[(Int, Int)] = []
  for _ in 0..<100 {
    queries.push(((nxt() % 1000UL).to_int(), (nxt() % 1000UL).to_int()))
  }
  let g = @dir.WeightedCsr::from_edges(n, edges3)
  let adj : Array[Array[(Int, Int)]] = Array::makei(n, fn(_i) { [] })
  for e in edges3 {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  let ug = @uw.CsrGraph::from_edges(
    n,
    edges3.map(fn(e) {
      let (u, v, _) = e
      (u, v)
    }),
  )
  let uadj : Array[Array[Int]] = Array::makei(n, fn(_i) { [] })
  for e in edges3 {
    let (u, v, _) = e
    uadj[u].push(v)
  }
  b.bench(name="dijkstra_indexed_1000x16_100q", fn() {
    let mut acc = 0
    for q in queries {
      let (s, t) = q
      match @dir.dijkstra_indexed(g, s, t) {
        Some((_, c)) => acc = acc + c
        None => acc = acc - 1
      }
    }
    b.keep(acc)
  })
  b.bench(name="dijkstra_generic_1000x16_100q", fn() {
    let mut acc = 0
    for q in queries {
      let (s, t) = q
      match @dir.dijkstra(s, fn(node) { adj[node] }, fn(node) { node == t }) {
        Some((_, c)) => acc = acc + c
        None => acc = acc - 1
      }
    }
    b.keep(acc)
  })
  b.bench(name="bfs_indexed_1000x16_100q", fn() {
    let mut acc = 0
    for q in queries {
      let (s, t) = q
      match @uw.bfs_indexed(ug, s, t) {
        Some(p) => acc = acc + p.length()
        None => acc = acc - 1
      }
    }
    b.keep(acc)
  })
  b.bench(name="bfs_generic_1000x16_100q", fn() {
    let mut acc = 0
    for q in queries {
      let (s, t) = q
      match @uw.bfs(s, fn(node) { uadj[node] }, fn(node) { node == t }) {
        Some(p) => acc = acc + p.length()
        None => acc = acc - 1
      }
    }
    b.keep(acc)
  })
}
