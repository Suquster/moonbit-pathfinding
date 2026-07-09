// family14_proof_test.mbt —— 查询算法族代价等价扩展接地（INFRA 第十四批）。
// 第十三批接地了 advanced 的 CH / ALT；本批补齐剩余查询加速面：
//   * JPS：随机障碍栅格上 jps / jps_batch 与 8 向 Dijkstra 参考（基数步 1、
//     对角步 1.4142135，对角只要求目标格开放，与模块内 A* 参考同口径）
//     逐对代价一致；
//   * CH-CSR：synthetic_grid_csr 合成栅格图上 ch_csr_query / ch_csr_query_cost
//     与逐邻接 Dijkstra 参考代价一致（cost_agrees_with_reference）；
//   * bidirectional_dijkstra：随机带权有向图上与单向 Dijkstra 逐对代价一致
//     （双向搜索的会合正确性护栏）。

// ---------------------------------------------------------------------------
// JPS：随机障碍栅格 vs 8 向 Dijkstra 参考
// ---------------------------------------------------------------------------

///|
/// 随机栅格生成器：width/height ∈ [3,7]，约 1/5 概率置障；起点 (0,0) 与
/// 终点 (h-1,w-1) 强制开放（可达性交由参考实现共同判定，含双 None 情形）。
fn f14_grid_gen() -> @infra_pbt.Gen[(Int, Int, Array[Bool])] {
  @infra_pbt.Gen::new(fn(rng) {
    let w = rng.next_range(3, 7)
    let h = rng.next_range(3, 7)
    let blocked : Array[Bool] = []
    for _i in 0..<(w * h) {
      blocked.push(rng.next_below(5) == 0)
    }
    blocked[0] = false
    blocked[w * h - 1] = false
    (w, h, blocked)
  })
}

///|
/// 8 向栅格后继（与 JPS 及模块内 A* 参考同口径）：基数步代价 1.0，对角步
/// 1.4142135；对角移动只要求目标格开放（允许切角）。
fn f14_grid_succ(
  w : Int,
  h : Int,
  blocked : Array[Bool],
) -> ((Int, Int)) -> Array[((Int, Int), Double)] {
  let open = fn(r : Int, c : Int) -> Bool {
    r >= 0 && r < h && c >= 0 && c < w && !blocked[r * w + c]
  }
  fn(cell : (Int, Int)) -> Array[((Int, Int), Double)] {
    let (r, c) = cell
    let out : Array[((Int, Int), Double)] = []
    let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    for d in dirs {
      if open(r + d.0, c + d.1) {
        out.push(((r + d.0, c + d.1), 1.0))
      }
    }
    let diags = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    for d in diags {
      if open(r + d.0, c + d.1) {
        out.push(((r + d.0, c + d.1), 1.4142135))
      }
    }
    out
  }
}

///|
/// 把 Double 代价量化到 2^-20 网格：JPS 以「对角步数×1.4142135 + 直行步数」
/// 聚合计费，参考 Dijkstra 逐步累加，两种求和次序在最后一两个 ulp 上可能
/// 有舍入差；量化后严格相等比较即恢复良定义（网格远粗于舍入差、远细于
/// 任何真实代价差 ≥ 0.4142135）。
fn f14_quantize(
  result : (Array[(Int, Int)], Double)?,
) -> (Array[(Int, Int)], Double)? {
  match result {
    Some((path, c)) => Some((path, (c * 1048576.0).round() / 1048576.0))
    None => None
  }
}

///|
/// JPS 返回的是跳点序列（相邻跳点间为直线/对角线段），代价与参考最短距离
/// 一致但节点序列非逐步路径，故本批只护栏**代价等价**（cost_agrees 家族），
/// 与谓词文档「只比较代价」的判定语义一致。
test "jps cost agrees with 8-direction dijkstra reference on random grids" {
  let ok = @infra_pbt.holds_for_all(
    f14_grid_gen(),
    fn(input : (Int, Int, Array[Bool])) -> Bool {
      let (w, h, blocked) = input
      match @advanced.JPSGrid::new(w, h, blocked) {
        Some(grid) => {
          let succ = f14_grid_succ(w, h, blocked)
          let goal = (h - 1, w - 1)
          let fast = f14_quantize(@advanced.jps(grid, (0, 0), goal))
          let reference = f14_quantize(
            @directed.dijkstra((0, 0), succ, fn(cell) { cell == goal }),
          )
          if !cost_agrees_with_reference(fast, reference) {
            return false
          }
          // 批量接口与逐点参考一一对应。
          let pairs = [((0, 0), goal), (goal, (0, 0))]
          let batch : Array[(Array[(Int, Int)], Double)?] = []
          for r in @advanced.jps_batch(grid, pairs) {
            batch.push(f14_quantize(r))
          }
          let refs : Array[(Array[(Int, Int)], Double)?] = []
          for p in pairs {
            refs.push(
              f14_quantize(
                @directed.dijkstra(p.0, succ, fn(cell) { cell == p.1 }),
              ),
            )
          }
          batch_cost_agrees(batch, refs)
        }
        None => false
      }
    },
    iters=96,
  )
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// CH-CSR：合成栅格图 vs 逐邻接 Dijkstra 参考
// ---------------------------------------------------------------------------

///|
/// 由 CSR 三数组派生逐邻接后继函数（定义式参考实现的输入口径）。
fn f14_csr_succ(g : @graph.CsrGraph[Double]) -> (Int) -> Array[(Int, Double)] {
  fn(u : Int) -> Array[(Int, Double)] {
    let out : Array[(Int, Double)] = []
    for k in g.row_ptr[u]..<g.row_ptr[u + 1] {
      out.push((g.col_idx[k], g.weights[k]))
    }
    out
  }
}

///|
test "ch csr query cost agrees with dijkstra reference on synthetic grids" {
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.Gen::new(fn(rng) {
      (rng.next_range(2, 5), rng.next_range(2, 5), rng.next_range(0, 999))
    }),
    fn(input : (Int, Int, Int)) -> Bool {
      let (rows, cols, seed) = input
      // 权重取二进制精确可表示的 0.25 步进（和的任意结合次序均精确），
      // 避免 CH shortcut 累加次序引入的浮点舍入差破坏严格相等比较。
      match
        @graph.synthetic_grid_csr(
          rows,
          cols,
          1.0 + (seed % 8).to_double() * 0.25,
        ) {
        Ok(g) => {
          let ch = @advanced.ch_csr_preprocess(g)
          let succ = f14_csr_succ(g)
          let pairs = [(0, g.n - 1), (g.n - 1, 0), (0, g.n / 2)]
          for p in pairs {
            let fast = @advanced.ch_csr_query(ch, p.0, p.1)
            let reference = @directed.dijkstra(p.0, succ, fn(u) { u == p.1 })
            if !cost_agrees_with_reference(fast, reference) {
              return false
            }
            // 代价专用接口与完整查询接口自洽。
            match (fast, @advanced.ch_csr_query_cost(ch, p.0, p.1)) {
              (Some((_, c1)), Some(c2)) => if c1 != c2 { return false }
              (None, None) => ()
              _ => return false
            }
          }
          true
        }
        Err(_) => false
      }
    },
    iters=48,
  )
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// bidirectional_dijkstra：随机带权有向图 vs 单向 Dijkstra
// ---------------------------------------------------------------------------

///|
/// 复用第十三批的带权有向图生成器形态：链式骨架 + 随机额外边，权重由端点
/// 确定函数派生（正权）。
fn f14_wgraph_gen() -> @infra_pbt.Gen[(Int, Array[(Int, Int, Int)])] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 9)
    let edges : Array[(Int, Int, Int)] = []
    for i in 1..<n {
      edges.push((i - 1, i, 1 + ((i - 1) * 3 + i * 5) % 11))
    }
    let extra = rng.next_range(0, n)
    for _k in 0..<extra {
      let u = rng.next_range(0, n - 1)
      let v = rng.next_range(0, n - 1)
      if u != v {
        edges.push((u, v, 1 + (u * 13 + v * 7) % 11))
      }
    }
    (n, edges)
  })
}

///|
test "bidirectional dijkstra cost agrees with unidirectional reference" {
  let ok = @infra_pbt.holds_for_all(
    f14_wgraph_gen(),
    fn(input : (Int, Array[(Int, Int, Int)])) -> Bool {
      let (n, edges) = input
      let succ = fn(u : Int) -> Array[(Int, Int)] {
        let out : Array[(Int, Int)] = []
        for e in edges {
          if e.0 == u {
            out.push((e.1, e.2))
          }
        }
        out
      }
      let pred = fn(u : Int) -> Array[(Int, Int)] {
        let out : Array[(Int, Int)] = []
        for e in edges {
          if e.1 == u {
            out.push((e.0, e.2))
          }
        }
        out
      }
      let pairs = [(0, n - 1), (n - 1, 0), (0, n / 2)]
      for p in pairs {
        let fast = @directed.bidirectional_dijkstra(p.0, p.1, succ, pred)
        let reference = @directed.dijkstra(p.0, succ, fn(u) { u == p.1 })
        if !cost_agrees_with_reference(fast, reference) {
          return false
        }
      }
      true
    },
    iters=128,
  )
  assert_true(ok)
}
