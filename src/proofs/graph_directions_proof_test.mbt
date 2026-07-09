// graph_directions_proof_test.mbt —— 图方向家族（unweighted / undirected /
// directed / playground / road_service）证明谓词的真实实现接地测试
// （INFRA 第十二批）。此前 src/proofs 尚未直接以这些包的真实实现驱动
// 谓词，本批补齐：
//   * unweighted：随机无向连通图上 BFS 路径合法（is_valid_path）且
//     长度等于 BfsTree 层号 + 1（最短性一致）；
//   * undirected：Kruskal 与 Prim 在随机连通图上总权一致（MST 唯一
//     总权），连通分量划分守恒（count_conserved 语义）；
//   * directed：随机 DAG 拓扑序尊重全部边（build_order_respects_deps
//     复用为通用拓扑不变量）；
//   * playground：pg_* 会话在随机网格上算出的最终路径起终点正确、
//     相邻步长为曼哈顿邻接（is_valid_path 网格后继）；
//   * road_service：链式路网 route 命中时输出路径首尾等于起终点。

///|
fn gd_edges_gen() -> @infra_pbt.Gen[(Int, Array[(Int, Int)])] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 9)
    let edges : Array[(Int, Int)] = []
    // 链式骨架保证连通，再叠加随机额外边。
    for i in 1..<n {
      edges.push((i - 1, i))
    }
    let extra = rng.next_range(0, n)
    for _k in 0..<extra {
      let u = rng.next_range(0, n - 1)
      let v = rng.next_range(0, n - 1)
      if u != v {
        edges.push((u, v))
      }
    }
    (n, edges)
  })
}

///|
fn gd_neighbors(n : Int, edges : Array[(Int, Int)]) -> (Int) -> Array[Int] {
  fn(u : Int) -> Array[Int] {
    let out : Array[Int] = []
    for e in edges {
      if e.0 == u && e.1 < n {
        out.push(e.1)
      }
      if e.1 == u && e.0 < n {
        out.push(e.0)
      }
    }
    out
  }
}

///|
test "unweighted bfs returns valid shortest paths on random connected graphs" {
  let ok = @infra_pbt.holds_for_all(
    gd_edges_gen(),
    fn(input : (Int, Array[(Int, Int)])) -> Bool {
      let (n, edges) = input
      let succ = gd_neighbors(n, edges)
      let goal = n - 1
      match @unweighted.bfs(0, succ, fn(u) { u == goal }) {
        Some(path) => {
          let tree = @unweighted.bfs_all(0, succ)
          is_valid_path(path, 0, succ) &&
          path[path.length() - 1] == goal &&
          tree.distance_to(goal) == Some(path.length() - 1)
        }
        None => false
      }
    },
    iters=128,
  )
  assert_true(ok)
}

///|
fn gd_mst_weight(msf : Array[(Int, Int, Int)]) -> Int {
  let mut acc = 0
  for e in msf {
    acc += e.2
  }
  acc
}

///|
test "kruskal and prim agree on total mst weight over random connected graphs" {
  let ok = @infra_pbt.holds_for_all(
    gd_edges_gen(),
    fn(input : (Int, Array[(Int, Int)])) -> Bool {
      let (n, edges) = input
      let nodes : Array[Int] = []
      for i in 0..<n {
        nodes.push(i)
      }
      // 以确定函数派生对称权重（与端点顺序无关），保持纯性。
      let weighted : Array[(Int, Int, Int)] = []
      for e in edges {
        let lo = if e.0 < e.1 { e.0 } else { e.1 }
        let hi = if e.0 < e.1 { e.1 } else { e.0 }
        weighted.push((e.0, e.1, 1 + (lo * 7 + hi * 3) % 13))
      }
      let k = @undirected.kruskal_mst(nodes, weighted)
      let adj = fn(u : Int) -> Array[(Int, Int)] {
        let out : Array[(Int, Int)] = []
        for e in weighted {
          if e.0 == u {
            out.push((e.1, e.2))
          }
          if e.1 == u {
            out.push((e.0, e.2))
          }
        }
        out
      }
      let p = @undirected.prim_mst(nodes, adj)
      k.length() == n - 1 &&
      p.length() == n - 1 &&
      gd_mst_weight(k) == gd_mst_weight(p)
    },
    iters=128,
  )
  assert_true(ok)
}

///|
test "connected components partition conserves the node count" {
  let ok = @infra_pbt.holds_for_all(
    gd_edges_gen(),
    fn(input : (Int, Array[(Int, Int)])) -> Bool {
      let (n, edges) = input
      let nodes : Array[Int] = []
      for i in 0..<n {
        nodes.push(i)
      }
      let comps = @undirected.connected_components(
        nodes,
        gd_neighbors(n, edges),
      )
      let sizes : Array[Int] = []
      for c in comps {
        sizes.push(c.length())
      }
      let mut total = 0
      for s in sizes {
        total += s
      }
      total == n
    },
    iters=128,
  )
  assert_true(ok)
}

///|
test "directed topological order respects every edge on random dags" {
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.Gen::new(fn(rng) {
      let n = rng.next_range(2, 10)
      let edges : Array[(Int, Int)] = []
      let m = rng.next_range(0, 2 * n)
      for _k in 0..<m {
        let u = rng.next_range(1, n - 1)
        let v = rng.next_range(0, u - 1)
        edges.push((u, v)) // u > v：天然无环（u 依赖 v）。
      }
      (n, edges)
    }),
    fn(input : (Int, Array[(Int, Int)])) -> Bool {
      let (n, edges) = input
      let nodes : Array[Int] = []
      for i in 0..<n {
        nodes.push(i)
      }
      // 边 (u, v) 语义为「u 依赖 v」；交给 topological_sort 的后继函数
      // 取反向 v→u，使被依赖方 v 排在依赖方 u 之前，与
      // build_order_respects_deps 的约定（pos[v] < pos[u]）对齐。
      let succ = fn(u : Int) -> Array[Int] {
        let out : Array[Int] = []
        for e in edges {
          if e.1 == u {
            out.push(e.0)
          }
        }
        out
      }
      match @directed.topological_sort(nodes, succ) {
        Ok(order) => {
          let pos : Array[Int] = []
          for _i in 0..<n {
            pos.push(0)
          }
          let mut idx = 0
          for u in order {
            pos[u] = idx
            idx += 1
          }
          // topological_sort 保证每条边 (u, v) 中 u 先于 v；谓词边为
          // （依赖方, 被依赖方），此处 u 依赖 v ⇒ v 应更早，直接匹配。
          build_order_respects_deps(pos, edges)
        }
        Err(_) => false
      }
    },
    iters=128,
  )
  assert_true(ok)
}

///|
test "playground session computes valid grid paths end to end" {
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.Gen::new(fn(rng) {
      let rows = rng.next_range(2, 6)
      let cols = rng.next_range(2, 6)
      (rows, cols)
    }),
    fn(dims : (Int, Int)) -> Bool {
      let (rows, cols) = dims
      if @playground.pg_reset(rows, cols) != 0 {
        return false
      }
      if @playground.pg_set_start(0) != 0 {
        return false
      }
      let goal = rows * cols - 1
      if @playground.pg_set_goal(goal) != 0 {
        return false
      }
      if @playground.pg_select_algo(0) != 0 {
        return false
      }
      if @playground.pg_compute() <= 0 {
        return false
      }
      let len = @playground.pg_final_path_len()
      if len != rows - 1 + cols - 1 + 1 {
        return false
      }
      let path : Array[Int] = []
      for i in 0..<len {
        path.push(@playground.pg_final_path_at(i))
      }
      let succ = fn(cell : Int) -> Array[Int] {
        let r = cell / cols
        let c = cell % cols
        let out : Array[Int] = []
        if r > 0 {
          out.push(cell - cols)
        }
        if r < rows - 1 {
          out.push(cell + cols)
        }
        if c > 0 {
          out.push(cell - 1)
        }
        if c < cols - 1 {
          out.push(cell + 1)
        }
        out
      }
      is_valid_path(path, 0, succ) && path[path.length() - 1] == goal
    },
    iters=64,
  )
  assert_true(ok)
}

///|
test "road service routes hit both endpoints on chain networks" {
  let lines = ["a b 3", "b c 4", "c d 5"]
  let (net, errs) = @road_service.parse_road_network(lines)
  assert_true(errs.length() == 0)
  let svc = @road_service.RoadService::build(net)
  match svc.route("a", "d", 0, 1000) {
    RouteFound(path, cost) => {
      assert_true(path.length() >= 2)
      assert_true(path[0] == "a" && path[path.length() - 1] == "d")
      assert_true(cost == 12)
    }
    _ => abort("expected Routed outcome")
  }
}
