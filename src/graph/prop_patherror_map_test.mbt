// Feature: championship-v1-upgrade, Property 20: 错误条件映射到正确 PathError 变体且图不变
//
// 本文件以属性测试（property-based test）校验「方向 4」新增的结构化错误入口
// `typed_shortest_path` / `typed_bfs_path`（typed_query.mbt）满足 design.md
// §「Property 20」/ Requirement 13.2~13.6 的核心不变量：
//
//   对任意触发某一失败原因的查询，新增入口返回携带「对应且唯一」PathError
//   变体的失败结果；其中「源缺失 / 目标缺失 / 非法参数」三类情形下，输入图
//   （以 `nodes` 数组承载的节点空间）在调用前后内容保持不变。
//
// 五类互斥失败原因与变体映射（Requirement 13.2~13.6）：
//   * 源缺失（source ∉ nodes）          → Err(SourceNotFound)
//   * 目标缺失（target ∉ nodes）        → Err(TargetNotFound)
//   * 非法参数（nodes 为空）            → Err(InvalidArgument(_))
//   * 不可达（源与目标分属不同连通分量）→ Err(Unreachable)
//   * 负权环（源到目标路径上含负权环）  → Err(NegativeCycle)
//
// 图不变性说明：`successors` 以纯函数闭包给出，函数实现只读取 `nodes` 与闭包，
// 不修改任何入参；因此对「源缺失 / 目标缺失 / 非法参数」三类场景，调用前后
// 对 `nodes` 内容做快照对比即可佐证输入图不被修改（Requirement 13.2/13.3/13.6）。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。每条属性迭代 128 次（≥100 基线）。

// ──────────────────────────────────────────────────────────────────────────
// 通用辅助
// ──────────────────────────────────────────────────────────────────────────

///|
/// 判定两个 `Int` 数组是否逐元素相等（用于 `nodes` 调用前后快照对比）。
fn p20_arr_eq(a : Array[Int], b : Array[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// 为 `nodes` 数组构造一份内容快照（值拷贝），便于调用后对比是否被修改。
fn p20_snapshot(a : Array[Int]) -> Array[Int] {
  let s : Array[Int] = []
  for x in a {
    s.push(x)
  }
  s
}

///|
/// 向带权邻接表追加一条有向边（节点已预初始化，None 分支仅作健壮性兜底）。
fn p20_add_w(
  adj : Map[Int, Array[(Int, Int)]],
  u : Int,
  v : Int,
  w : Int,
) -> Unit {
  match adj.get(u) {
    Some(arr) => arr.push((v, w))
    None => adj[u] = [(v, w)]
  }
}

///|
/// 由带权邻接表得到 `typed_shortest_path` 所需的 successor 闭包（纯只读）。
fn p20_succ_w(adj : Map[Int, Array[(Int, Int)]]) -> (Int) -> Array[(Int, Int)] {
  fn(u) {
    match adj.get(u) {
      Some(arr) => arr
      None => []
    }
  }
}

///|
/// 向无权邻接表追加一条有向后继边（节点已预初始化）。
fn p20_add_u(adj : Map[Int, Array[Int]], u : Int, v : Int) -> Unit {
  match adj.get(u) {
    Some(arr) => arr.push(v)
    None => adj[u] = [v]
  }
}

///|
/// 由无权邻接表得到 `typed_bfs_path` 所需的 successor 闭包（纯只读）。
fn p20_succ_u(adj : Map[Int, Array[Int]]) -> (Int) -> Array[Int] {
  fn(u) {
    match adj.get(u) {
      Some(arr) => arr
      None => []
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────
// 场景生成器：携带 nodes / source / target / 邻接表的随机用例
// ──────────────────────────────────────────────────────────────────────────

///|
/// 源缺失场景（带权）：随机图 + source 取一个保证不在 nodes 的负值。
fn p20_gen_source_missing() -> @infra_pbt.Gen[
  (Array[Int], Int, Int, Map[Int, Array[(Int, Int)]]),
] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 6) // 1..5 个节点，保证非空
    let nodes : Array[Int] = []
    for i in 0..<n {
      nodes.push(i)
    }
    let source = -1 - rng.next_below(100) // 负值，必不在 [0,n) 中
    let target = nodes[rng.next_below(n)]
    let adj : Map[Int, Array[(Int, Int)]] = Map([])
    for u in nodes {
      adj[u] = []
    }
    let e = rng.next_below(n * 2 + 1)
    for _i in 0..<e {
      let u = nodes[rng.next_below(n)]
      let v = nodes[rng.next_below(n)]
      let w = rng.next_range(0, 10)
      p20_add_w(adj, u, v, w)
    }
    (nodes, source, target, adj)
  })
}

///|
/// 目标缺失场景（带权）：source ∈ nodes，target 取一个保证不在 nodes 的负值。
fn p20_gen_target_missing() -> @infra_pbt.Gen[
  (Array[Int], Int, Int, Map[Int, Array[(Int, Int)]]),
] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 6)
    let nodes : Array[Int] = []
    for i in 0..<n {
      nodes.push(i)
    }
    let source = nodes[rng.next_below(n)]
    let target = -1 - rng.next_below(100) // 负值，必不在 [0,n) 中
    let adj : Map[Int, Array[(Int, Int)]] = Map([])
    for u in nodes {
      adj[u] = []
    }
    let e = rng.next_below(n * 2 + 1)
    for _i in 0..<e {
      let u = nodes[rng.next_below(n)]
      let v = nodes[rng.next_below(n)]
      let w = rng.next_range(0, 10)
      p20_add_w(adj, u, v, w)
    }
    (nodes, source, target, adj)
  })
}

///|
/// 不可达场景（带权、非负权）：构造两个互不连通的分量，源、目标分属其一。
fn p20_gen_unreachable() -> @infra_pbt.Gen[
  (Array[Int], Int, Int, Map[Int, Array[(Int, Int)]]),
] {
  @infra_pbt.Gen::new(fn(rng) {
    // 分量 A = [0, k)；分量 B = [k, k+m)；两分量之间无任何边。
    let k = rng.next_range(1, 4) // A 含 1..3 节点
    let m = rng.next_range(1, 4) // B 含 1..3 节点
    let total = k + m
    let nodes : Array[Int] = []
    for i in 0..<total {
      nodes.push(i)
    }
    let adj : Map[Int, Array[(Int, Int)]] = Map([])
    for u in nodes {
      adj[u] = []
    }
    // 仅在分量 A 内部连边。
    let ea = rng.next_below(k * 2 + 1)
    for _i in 0..<ea {
      let u = rng.next_below(k)
      let v = rng.next_below(k)
      p20_add_w(adj, u, v, rng.next_range(0, 10))
    }
    // 仅在分量 B 内部连边（节点编号在 [k, total)）。
    let eb = rng.next_below(m * 2 + 1)
    for _i in 0..<eb {
      let u = k + rng.next_below(m)
      let v = k + rng.next_below(m)
      p20_add_w(adj, u, v, rng.next_range(0, 10))
    }
    let source = rng.next_below(k) // ∈ A
    let target = k + rng.next_below(m) // ∈ B，从 A 不可达
    (nodes, source, target, adj)
  })
}

///|
/// 负权环场景（带权）：源到目标的路径上嵌入一个净权为负的二元环。
///
/// 结构：0 ->(a) 1 ->(b) 2 ->(c) 1（与 1->2 构成负权环），2 ->(d) 3。
/// 取 b + c < 0 保证 1<->2 为负权环；该环从源 0 可达且可经 2->3 抵达目标 3。
fn p20_gen_negative_cycle() -> @infra_pbt.Gen[
  (Array[Int], Int, Int, Map[Int, Array[(Int, Int)]]),
] {
  @infra_pbt.Gen::new(fn(rng) {
    let nodes : Array[Int] = [0, 1, 2, 3]
    let adj : Map[Int, Array[(Int, Int)]] = Map([])
    for u in nodes {
      adj[u] = []
    }
    let a = rng.next_below(10) // 0->1，非负
    let b = rng.next_range(-5, 5) // 1->2，任意
    // 选取 c 使 b + c <= -1，确保 1<->2 净权为负（负权环）。
    let neg = 1 + rng.next_below(5) // 1..5
    let c = -b - neg // b + c = -neg < 0
    let d = rng.next_below(10) // 2->3，非负
    p20_add_w(adj, 0, 1, a)
    p20_add_w(adj, 1, 2, b)
    p20_add_w(adj, 2, 1, c)
    p20_add_w(adj, 2, 3, d)
    (nodes, 0, 3, adj)
  })
}

// ──────────────────────────────────────────────────────────────────────────
// 属性 1：源缺失 → Err(SourceNotFound) 且 nodes 不变
// ──────────────────────────────────────────────────────────────────────────

///|
/// Feature: championship-v1-upgrade, Property 20: 源缺失映射到 SourceNotFound 且图不变
///
/// **Validates: Requirements 13.2**
test "Feature: championship-v1-upgrade, Property 20: source missing maps to SourceNotFound and graph unchanged" {
  let ok = @infra_pbt.holds_for_all(
    p20_gen_source_missing(),
    fn(case_) {
      let (nodes, source, target, adj) = case_
      let before = p20_snapshot(nodes)
      let result = typed_shortest_path(nodes, source, target, p20_succ_w(adj))
      // 变体映射正确。
      let variant_ok = match result {
        Err(SourceNotFound) => true
        _ => false
      }
      // 图（nodes 内容）调用前后不变。
      variant_ok && p20_arr_eq(before, nodes)
    },
    iters=128,
  )
  assert_true(ok)
}

// ──────────────────────────────────────────────────────────────────────────
// 属性 2：目标缺失 → Err(TargetNotFound) 且 nodes 不变
// ──────────────────────────────────────────────────────────────────────────

///|
/// Feature: championship-v1-upgrade, Property 20: 目标缺失映射到 TargetNotFound 且图不变
///
/// **Validates: Requirements 13.3**
test "Feature: championship-v1-upgrade, Property 20: target missing maps to TargetNotFound and graph unchanged" {
  let ok = @infra_pbt.holds_for_all(
    p20_gen_target_missing(),
    fn(case_) {
      let (nodes, source, target, adj) = case_
      let before = p20_snapshot(nodes)
      let result = typed_shortest_path(nodes, source, target, p20_succ_w(adj))
      let variant_ok = match result {
        Err(TargetNotFound) => true
        _ => false
      }
      variant_ok && p20_arr_eq(before, nodes)
    },
    iters=128,
  )
  assert_true(ok)
}

// ──────────────────────────────────────────────────────────────────────────
// 属性 3：非法参数（nodes 为空）→ Err(InvalidArgument(_)) 且 nodes 不变
// ──────────────────────────────────────────────────────────────────────────

///|
/// Feature: championship-v1-upgrade, Property 20: 非法参数映射到 InvalidArgument 且图不变
///
/// nodes 为空时不论 source/target 取值，恒返回 `InvalidArgument(_)`；空数组在
/// 调用前后仍为空（图不变）。
///
/// **Validates: Requirements 13.6**
test "Feature: championship-v1-upgrade, Property 20: empty nodes maps to InvalidArgument and graph unchanged" {
  let gen : @infra_pbt.Gen[(Int, Int)] = @infra_pbt.Gen::new(fn(rng) {
    (rng.next_range(-50, 50), rng.next_range(-50, 50))
  })
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(pair) {
      let (source, target) = pair
      let nodes : Array[Int] = []
      let before = p20_snapshot(nodes)
      let adj : Map[Int, Array[(Int, Int)]] = Map([])
      let result = typed_shortest_path(nodes, source, target, p20_succ_w(adj))
      let variant_ok = match result {
        Err(InvalidArgument(_)) => true
        _ => false
      }
      variant_ok && p20_arr_eq(before, nodes) && nodes.length() == 0
    },
    iters=128,
  )
  assert_true(ok)
}

// ──────────────────────────────────────────────────────────────────────────
// 属性 4：不可达（分离分量）→ Err(Unreachable)
// ──────────────────────────────────────────────────────────────────────────

///|
/// Feature: championship-v1-upgrade, Property 20: 不可达映射到 Unreachable
///
/// 源与目标均在图中但分属不连通的两个分量，恒返回 `Unreachable`。
///
/// **Validates: Requirements 13.4**
test "Feature: championship-v1-upgrade, Property 20: disjoint components map to Unreachable" {
  let ok = @infra_pbt.holds_for_all(
    p20_gen_unreachable(),
    fn(case_) {
      let (nodes, source, target, adj) = case_
      let result = typed_shortest_path(nodes, source, target, p20_succ_w(adj))
      match result {
        Err(Unreachable) => true
        _ => false
      }
    },
    iters=128,
  )
  assert_true(ok)
}

// ──────────────────────────────────────────────────────────────────────────
// 属性 5：负权环 → Err(NegativeCycle)
// ──────────────────────────────────────────────────────────────────────────

///|
/// Feature: championship-v1-upgrade, Property 20: 负权环映射到 NegativeCycle
///
/// 源到目标的可达路径上存在净权为负的环，恒返回 `NegativeCycle`。
///
/// **Validates: Requirements 13.5**
test "Feature: championship-v1-upgrade, Property 20: negative cycle on path maps to NegativeCycle" {
  let ok = @infra_pbt.holds_for_all(
    p20_gen_negative_cycle(),
    fn(case_) {
      let (nodes, source, target, adj) = case_
      let result = typed_shortest_path(nodes, source, target, p20_succ_w(adj))
      match result {
        Err(NegativeCycle) => true
        _ => false
      }
    },
    iters=128,
  )
  assert_true(ok)
}

// ──────────────────────────────────────────────────────────────────────────
// 属性 6：无权 BFS 入口 typed_bfs_path 的四类变体映射与图不变
// ──────────────────────────────────────────────────────────────────────────

///|
/// 源缺失场景（无权）：随机后继图 + source 取保证不在 nodes 的负值。
fn p20_gen_bfs_source_missing() -> @infra_pbt.Gen[
  (Array[Int], Int, Int, Map[Int, Array[Int]]),
] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 6)
    let nodes : Array[Int] = []
    for i in 0..<n {
      nodes.push(i)
    }
    let source = -1 - rng.next_below(100)
    let target = nodes[rng.next_below(n)]
    let adj : Map[Int, Array[Int]] = Map([])
    for u in nodes {
      adj[u] = []
    }
    let e = rng.next_below(n * 2 + 1)
    for _i in 0..<e {
      p20_add_u(adj, nodes[rng.next_below(n)], nodes[rng.next_below(n)])
    }
    (nodes, source, target, adj)
  })
}

///|
/// Feature: championship-v1-upgrade, Property 20: BFS 入口源缺失映射到 SourceNotFound 且图不变
///
/// **Validates: Requirements 13.2**
test "Feature: championship-v1-upgrade, Property 20: bfs source missing maps to SourceNotFound and graph unchanged" {
  let ok = @infra_pbt.holds_for_all(
    p20_gen_bfs_source_missing(),
    fn(case_) {
      let (nodes, source, target, adj) = case_
      let before = p20_snapshot(nodes)
      let result = typed_bfs_path(nodes, source, target, p20_succ_u(adj))
      let variant_ok = match result {
        Err(SourceNotFound) => true
        _ => false
      }
      variant_ok && p20_arr_eq(before, nodes)
    },
    iters=128,
  )
  assert_true(ok)
}

///|
/// 不可达场景（无权）：两个分离分量，源、目标分属其一。
fn p20_gen_bfs_unreachable() -> @infra_pbt.Gen[
  (Array[Int], Int, Int, Map[Int, Array[Int]]),
] {
  @infra_pbt.Gen::new(fn(rng) {
    let k = rng.next_range(1, 4)
    let m = rng.next_range(1, 4)
    let total = k + m
    let nodes : Array[Int] = []
    for i in 0..<total {
      nodes.push(i)
    }
    let adj : Map[Int, Array[Int]] = Map([])
    for u in nodes {
      adj[u] = []
    }
    let ea = rng.next_below(k * 2 + 1)
    for _i in 0..<ea {
      p20_add_u(adj, rng.next_below(k), rng.next_below(k))
    }
    let eb = rng.next_below(m * 2 + 1)
    for _i in 0..<eb {
      p20_add_u(adj, k + rng.next_below(m), k + rng.next_below(m))
    }
    (nodes, rng.next_below(k), k + rng.next_below(m), adj)
  })
}

///|
/// Feature: championship-v1-upgrade, Property 20: BFS 入口不可达映射到 Unreachable
///
/// **Validates: Requirements 13.4**
test "Feature: championship-v1-upgrade, Property 20: bfs disjoint components map to Unreachable" {
  let ok = @infra_pbt.holds_for_all(
    p20_gen_bfs_unreachable(),
    fn(case_) {
      let (nodes, source, target, adj) = case_
      let result = typed_bfs_path(nodes, source, target, p20_succ_u(adj))
      match result {
        Err(Unreachable) => true
        _ => false
      }
    },
    iters=128,
  )
  assert_true(ok)
}

///|
/// Feature: championship-v1-upgrade, Property 20: BFS 入口空 nodes 映射到 InvalidArgument 且图不变
///
/// **Validates: Requirements 13.6**
test "Feature: championship-v1-upgrade, Property 20: bfs empty nodes maps to InvalidArgument and graph unchanged" {
  let gen : @infra_pbt.Gen[(Int, Int)] = @infra_pbt.Gen::new(fn(rng) {
    (rng.next_range(-50, 50), rng.next_range(-50, 50))
  })
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(pair) {
      let (source, target) = pair
      let nodes : Array[Int] = []
      let before = p20_snapshot(nodes)
      let adj : Map[Int, Array[Int]] = Map([])
      let result = typed_bfs_path(nodes, source, target, p20_succ_u(adj))
      let variant_ok = match result {
        Err(InvalidArgument(_)) => true
        _ => false
      }
      variant_ok && p20_arr_eq(before, nodes) && nodes.length() == 0
    },
    iters=128,
  )
  assert_true(ok)
}
