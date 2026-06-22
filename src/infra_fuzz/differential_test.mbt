// differential_test.mbt —— 跨算法差分验证器 Differential_Tester 的支撑逻辑
// （task 15.1）。
//
// 设计依据（design.md §5.2 Differential_Tester · Requirement 16.1–16.5/16.7）：
//   在「应当等价」的算法对之间对同一随机图实例交叉验证结果，用一种算法反向
//   印证另一种算法的正确性。本文件提供三个等价类（`EquivClass`）的逐实例
//   一致性判定与不一致反例报告，作为 task 15.2 属性测试（≥100 随机实例 +
//   `check_with_shrink` 收缩）的复用支撑。
//
//   * BfsVsDijkstraUnit      —— 单位权图：BFS 跳数 == Dijkstra 代价（整数精确，
//     eps=0 · R16.1）。
//   * DijkstraVsBellmanFord  —— 非负权图：Dijkstra 与 Bellman-Ford 单源最短距离
//     逐点偏差 ≤1e-9（R16.2）；两者判不可达时一致缺失（R16.4）。
//   * FloydWarshallVsJohnson —— 整数权图：Floyd-Warshall 与 Johnson 全对最短
//     距离矩阵逐元素相等（整数精确，落在 ≤1e-9 容差内 · R16.3）；两者判不可达
//     时一致（R16.4）。
//
// 设计哲学：
//   * 本文件为黑盒测试文件（`_test.mbt`），仅依赖本包公开 API（`FuzzGraph` /
//     `EquivClass` / `approx_eq` / `default_eps`）与测试期算法包
//     （@dir=@directed / @uw=@unweighted）；生产代码不受影响（包依赖控制 · R22）。
//   * 一切「FuzzGraph → 算法输入」的转换都先以 `diff_in_range` 过滤端点越界的
//     边，使三个等价类对**同一组**合法边运算，杜绝因输入口径差异引入的伪反例
//     （收缩 `remove_node` 后编号紧凑，端点恒在范围内，过滤为额外安全护栏）。
//   * 全函数（total）实现：无 `abort`/`todo!`/`panic` 占位；不可达统一以
//     `Option`/`infinity` 精确表达；report 用 `TextBuilder` 构建（禁止循环内
//     字符串 `+` 拼接 · R22.4）。
//   * 整数权换算 `diff_to_int` 夹取到 `[0, diff_int_weight_max]`：保证非负
//     （供 FW/Johnson 在无负环前提下结果一致）且路径累加不溢出
//     （n≤500、权≤1e6 时单条简单路径距离 ≤ 5e8 < Int 上限）。

///|
/// 差分比对的浮点容差（R16.2/16.3）：复用本包公开常量 `default_eps`（1e-9）。
let diff_eps : Double = default_eps

///|
/// 单位权等价类（R16.1）中赋予每条边的整数权：恒为 1，使 Dijkstra 代价即跳数。
let diff_unit_weight : Int = 1

///|
/// 整数权差分（FW↔Johnson）的权重上限（与 R16.5 的权值上限 1e6 一致）。下限为 0
/// （非负），保证两算法在「无负环」前提下结果一致，且路径累加不溢出 Int。
let diff_int_weight_max : Int = 1000000

///|
/// 差分比对默认源点：单源等价类（BFS↔Dijkstra / Dijkstra↔Bellman-Ford）固定
/// 自节点 0 出发，对全部目标节点逐一比对（含可达/不可达），覆盖 R16.4。
let diff_source : Int = 0

///|
/// 将整数夹取到闭区间 `[lo, hi]`（本黑盒测试文件的本地工具，避免依赖包内私有
/// 实现；语义与 gen.mbt 的同名私有 `clamp_int` 一致）。
fn diff_clamp(v : Int, lo : Int, hi : Int) -> Int {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// 边端点合法性：源/目标均落在 `[0, g.n)`。过滤越界边使三个等价类对同一组
/// 合法边运算，避免伪反例。
fn diff_in_range(g : FuzzGraph, u : Int, v : Int) -> Bool {
  u >= 0 && u < g.n && v >= 0 && v < g.n
}

///|
/// 节点全集 `[0, 1, ..., g.n-1]`。供 Bellman-Ford / Floyd-Warshall / Johnson
/// 的 `nodes` 参数使用。
fn diff_nodes(g : FuzzGraph) -> Array[Int] {
  let ns : Array[Int] = []
  for i in 0..<g.n {
    ns.push(i)
  }
  ns
}

///|
/// 邻接表（仅目标节点）：供 BFS 的 `successors : (N) -> Array[N]` 使用。
/// 保留平行边（同一目标多次出现）与自环，BFS 自身去重处理，不影响跳数。
fn diff_adj_targets(g : FuzzGraph) -> Map[Int, Array[Int]] {
  let adj : Map[Int, Array[Int]] = Map([])
  for i in 0..<g.n {
    adj[i] = []
  }
  for e in g.edges {
    let (u, v, _w) = e
    if diff_in_range(g, u, v) {
      adj.get(u).unwrap().push(v)
    }
  }
  adj
}

///|
/// 邻接表（目标 + 单位整数权 1）：供 Dijkstra 在单位权等价类下使用，使其代价
/// 与 BFS 跳数精确相等（R16.1）。
fn diff_adj_unit_weighted(g : FuzzGraph) -> Map[Int, Array[(Int, Int)]] {
  let adj : Map[Int, Array[(Int, Int)]] = Map([])
  for i in 0..<g.n {
    adj[i] = []
  }
  for e in g.edges {
    let (u, v, _w) = e
    if diff_in_range(g, u, v) {
      adj.get(u).unwrap().push((v, diff_unit_weight))
    }
  }
  adj
}

///|
/// 邻接表（目标 + 原始非负 Double 权）：供 Dijkstra 在 Dijkstra↔Bellman-Ford
/// 等价类下使用（R16.2/16.6 要求非负权生成器）。
fn diff_adj_weighted(g : FuzzGraph) -> Map[Int, Array[(Int, Double)]] {
  let adj : Map[Int, Array[(Int, Double)]] = Map([])
  for i in 0..<g.n {
    adj[i] = []
  }
  for e in g.edges {
    let (u, v, w) = e
    if diff_in_range(g, u, v) {
      adj.get(u).unwrap().push((v, w))
    }
  }
  adj
}

///|
/// 合法边表（Double 权）：供 Bellman-Ford 的 `edges` 参数使用。
fn diff_edges_double(g : FuzzGraph) -> Array[(Int, Int, Double)] {
  let es : Array[(Int, Int, Double)] = []
  for e in g.edges {
    let (u, v, w) = e
    if diff_in_range(g, u, v) {
      es.push((u, v, w))
    }
  }
  es
}

///|
/// 将 Double 权换算为非负整数权，夹取到 `[0, diff_int_weight_max]`。
/// `to_int` 向零截断（对非负输入即向下取整），夹取保证非负且不溢出。
fn diff_to_int(w : Double) -> Int {
  diff_clamp(w.to_int(), 0, diff_int_weight_max)
}

///|
/// 合法边表（整数权）：供 Floyd-Warshall 与 Johnson 共用，确保两者对**逐位
/// 相同**的整数边集运算（FW↔Johnson 等价类 · R16.3）。
fn diff_edges_int(g : FuzzGraph) -> Array[(Int, Int, Int)] {
  let es : Array[(Int, Int, Int)] = []
  for e in g.edges {
    let (u, v, w) = e
    if diff_in_range(g, u, v) {
      es.push((u, v, diff_to_int(w)))
    }
  }
  es
}

///|
/// 整数权「不可达」哨兵：等于 `@core` 为 Int 定义的 `Weight::infinity()`。
/// Floyd-Warshall 以该值标记不可达点对；据此与 Johnson 的「缺失即不可达」对齐。
fn diff_int_unreachable() -> Int {
  @core.Weight::infinity()
}

///|
/// 等价类 1：单位权图上 BFS 与 Dijkstra 的单源最短代价精确相等（R16.1）。
///
/// 自 `diff_source` 出发对全部目标逐一比对：两者同为可达且跳数相等，或同为
/// 不可达（R16.4）；否则不一致。空图（n=0）无查询，平凡一致。
fn diff_bfs_dijkstra_unit_consistent(g : FuzzGraph) -> Bool {
  if g.n == 0 {
    return true
  }
  let adj_t = diff_adj_targets(g)
  let adj_w = diff_adj_unit_weighted(g)
  let bfs_tree = @uw.bfs_all(diff_source, fn(u) { adj_t.get(u).unwrap_or([]) })
  let dij_tree = @dir.dijkstra_all(diff_source, fn(u) {
    adj_w.get(u).unwrap_or([])
  })
  for v in 0..<g.n {
    match (bfs_tree.distance_to(v), dij_tree.distance_to(v)) {
      (Some(bd), Some(dd)) => if bd != dd { return false }
      (None, None) => ()
      // 一侧可达、一侧不可达 → 不一致（违反 R16.4）。
      _ => return false
    }
  }
  true
}

///|
/// 等价类 2：非负权图上 Dijkstra 与 Bellman-Ford 的单源最短距离逐点偏差
/// ≤1e-9（R16.2）；两者判不可达时一致缺失（R16.4）。
///
/// 调用方须以非负权生成器供图（R16.6）。非负权下 Bellman-Ford 不应报负环；
/// 若返回 `Err` 视为不一致（交由报告暴露）。空图平凡一致。
fn diff_dijkstra_bellman_consistent(g : FuzzGraph) -> Bool {
  if g.n == 0 {
    return true
  }
  let adj_w = diff_adj_weighted(g)
  let dij_tree = @dir.dijkstra_all(diff_source, fn(u) {
    adj_w.get(u).unwrap_or([])
  })
  match @dir.bellman_ford(diff_nodes(g), diff_edges_double(g), diff_source) {
    Err(_) => false
    Ok(dist) => {
      for v in 0..<g.n {
        match (dij_tree.distance_to(v), dist.get(v)) {
          (Some(dd), Some(bd)) =>
            if !approx_eq(dd, bd, diff_eps) {
              return false
            }
          (None, None) => ()
          _ => return false
        }
      }
      true
    }
  }
}

///|
/// 等价类 3：整数权图上 Floyd-Warshall 与 Johnson 的全对最短距离矩阵逐元素
/// 相等（R16.3）；两者判不可达时一致（R16.4）。
///
/// Floyd-Warshall 返回全部点对（不可达记为 `infinity`、自身为 0）；Johnson 仅
/// 返回可达点对（不可达缺失）。逐 (u,v) 对齐：
///   * Johnson 有值 → FW 必有限且相等；
///   * Johnson 缺失 → FW 必为 `infinity`（同判不可达）；
///   * FW 缺失（不应发生，FW 含全部点对）→ 不一致。
/// 非负权下 Johnson 不应报负环；若返回 `Err` 视为不一致。空图平凡一致。
fn diff_floyd_johnson_consistent(g : FuzzGraph) -> Bool {
  let nodes = diff_nodes(g)
  let edges = diff_edges_int(g)
  let fw = @dir.floyd_warshall(nodes, edges)
  let inf = diff_int_unreachable()
  match @dir.johnson(nodes, edges) {
    Err(_) => false
    Ok(jo) =>
      (fn() {
        for u in 0..<g.n {
          for v in 0..<g.n {
            match (fw.get((u, v)), jo.get((u, v))) {
              (Some(fd), Some(jd)) => if fd == inf || fd != jd { return false }
              (Some(fd), None) => if fd != inf { return false }
              (None, _) => return false
            }
          }
        }
        true
      })()
  }
}

///|
/// 统一分发：按等价类判定图实例 `g` 上两算法是否一致（一致返回 `true`）。
///
/// 作为 `@infra_pbt.holds_for_all` / `check_with_shrink` 的谓词 `prop` 使用：
/// `prop(g) == true` 表示通过、`false` 表示发现差分反例。
fn differential_consistent(cls : EquivClass, g : FuzzGraph) -> Bool {
  match cls {
    BfsVsDijkstraUnit => diff_bfs_dijkstra_unit_consistent(g)
    DijkstraVsBellmanFord => diff_dijkstra_bellman_consistent(g)
    FloydWarshallVsJohnson => diff_floyd_johnson_consistent(g)
  }
}

///|
/// 等价类中文标识（用于报告标题）。
fn diff_class_name(cls : EquivClass) -> String {
  match cls {
    BfsVsDijkstraUnit => "BFS↔Dijkstra（单位权精确相等）"
    DijkstraVsBellmanFord => "Dijkstra↔Bellman-Ford（≤1e-9）"
    FloydWarshallVsJohnson =>
      "Floyd-Warshall↔Johnson（全对矩阵 ≤1e-9）"
  }
}

///|
/// 向报告缓冲渲染图实例（节点数 / 边数 / 边集）。以 `TextBuilder` 逐块 push，
/// 禁止循环内字符串 `+` 拼接（R22.4）。
fn diff_render_graph(tb : @infra_text.TextBuilder, g : FuzzGraph) -> Unit {
  tb.push_str("  图实例：n=")
  tb.push_str(g.n.to_string())
  tb.push_str("，m=")
  tb.push_str(g.edges.length().to_string())
  tb.push_char('\n')
  tb.push_str("  边集(源,目标,权)：")
  for e in g.edges {
    let (u, v, w) = e
    tb.push_str(" (")
    tb.push_str(u.to_string())
    tb.push_char(',')
    tb.push_str(v.to_string())
    tb.push_char(',')
    tb.push_str(w.to_string())
    tb.push_char(')')
  }
  tb.push_char('\n')
}

///|
/// 向报告缓冲渲染一个 `Int?` 距离（不可达渲染为 ∞）。
fn diff_render_opt_int(tb : @infra_text.TextBuilder, o : Int?) -> Unit {
  match o {
    Some(x) => tb.push_str(x.to_string())
    None => tb.push_char('\u{221E}') // ∞
  }
}

///|
/// 向报告缓冲渲染一个 `Double?` 距离（不可达渲染为 ∞）。
fn diff_render_opt_double(tb : @infra_text.TextBuilder, o : Double?) -> Unit {
  match o {
    Some(x) => tb.push_str(x.to_string())
    None => tb.push_char('\u{221E}') // ∞
  }
}

///|
/// 渲染 BFS↔Dijkstra 两侧单源距离向量（自 `diff_source`）。
fn diff_render_bfs_dijkstra(
  tb : @infra_text.TextBuilder,
  g : FuzzGraph,
) -> Unit {
  let adj_t = diff_adj_targets(g)
  let adj_w = diff_adj_unit_weighted(g)
  let bfs_tree = @uw.bfs_all(diff_source, fn(u) { adj_t.get(u).unwrap_or([]) })
  let dij_tree = @dir.dijkstra_all(diff_source, fn(u) {
    adj_w.get(u).unwrap_or([])
  })
  tb.push_str("  两侧输出（源点 src=")
  tb.push_str(diff_source.to_string())
  tb.push_str("，节点→[BFS|Dijkstra]）：")
  for v in 0..<g.n {
    tb.push_char(' ')
    tb.push_str(v.to_string())
    tb.push_str("→[")
    diff_render_opt_int(tb, bfs_tree.distance_to(v))
    tb.push_char('|')
    diff_render_opt_int(tb, dij_tree.distance_to(v))
    tb.push_char(']')
  }
  tb.push_char('\n')
}

///|
/// 渲染 Dijkstra↔Bellman-Ford 两侧单源距离向量（自 `diff_source`）。
fn diff_render_dijkstra_bellman(
  tb : @infra_text.TextBuilder,
  g : FuzzGraph,
) -> Unit {
  let adj_w = diff_adj_weighted(g)
  let dij_tree = @dir.dijkstra_all(diff_source, fn(u) {
    adj_w.get(u).unwrap_or([])
  })
  tb.push_str("  两侧输出（源点 src=")
  tb.push_str(diff_source.to_string())
  tb.push_str("，节点→[Dijkstra|Bellman-Ford]）：")
  match @dir.bellman_ford(diff_nodes(g), diff_edges_double(g), diff_source) {
    Err(_) =>
      tb.push_str(" Bellman-Ford 返回 Err（非负权下不应发生）")
    Ok(dist) =>
      for v in 0..<g.n {
        tb.push_char(' ')
        tb.push_str(v.to_string())
        tb.push_str("→[")
        diff_render_opt_double(tb, dij_tree.distance_to(v))
        tb.push_char('|')
        diff_render_opt_double(tb, dist.get(v))
        tb.push_char(']')
      }
  }
  tb.push_char('\n')
}

///|
/// 渲染 Floyd-Warshall↔Johnson 两侧全对距离矩阵（仅渲染存在差异或可达的点对，
/// 以控制输出规模；不可达且两侧一致的点对省略）。
fn diff_render_floyd_johnson(
  tb : @infra_text.TextBuilder,
  g : FuzzGraph,
) -> Unit {
  let nodes = diff_nodes(g)
  let edges = diff_edges_int(g)
  let fw = @dir.floyd_warshall(nodes, edges)
  let inf = diff_int_unreachable()
  tb.push_str(
    "  两侧输出（点对(u,v)→[FW|Johnson]，省略两侧均不可达者）：",
  )
  match @dir.johnson(nodes, edges) {
    Err(_) => tb.push_str(" Johnson 返回 Err（非负权下不应发生）")
    Ok(jo) =>
      for u in 0..<g.n {
        for v in 0..<g.n {
          let fwd = fw.get((u, v))
          let jod = jo.get((u, v))
          // 省略 FW=∞ 且 Johnson 缺失（两侧一致不可达）的点对。
          let omit = (fwd is Some(d) && d == inf) && jod is None
          if !omit {
            tb.push_str(" (")
            tb.push_str(u.to_string())
            tb.push_char(',')
            tb.push_str(v.to_string())
            tb.push_str(")→[")
            match fwd {
              Some(d) =>
                if d == inf {
                  tb.push_char('\u{221E}')
                } else {
                  tb.push_str(d.to_string())
                }
              None => tb.push_str("缺失")
            }
            tb.push_char('|')
            diff_render_opt_int(tb, jod)
            tb.push_char(']')
          }
        }
      }
  }
  tb.push_char('\n')
}

///|
/// 不一致反例报告（R16.7）：给定等价类、（收缩后的）图实例与随机种子，构建
/// 包含「等价类标识 / 随机种子 / 图实例 / 两侧输出」的诊断字符串。
///
/// 「经收缩得到的最小反例」由调用方（task 15.2）以 `@infra_pbt.check_with_shrink`
/// 配合 `shrink_fuzz_graph` 求得后，将该最小图与对应种子传入本函数即可。
/// 全程以 `TextBuilder` 构建，禁止循环内字符串 `+` 拼接（R22.4）。
fn differential_report(
  cls : EquivClass,
  g : FuzzGraph,
  seed : UInt64,
) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("差分不一致反例 · 等价类：")
  tb.push_str(diff_class_name(cls))
  tb.push_char('\n')
  tb.push_str("  随机种子(seed)：")
  tb.push_str(seed.to_string())
  tb.push_char('\n')
  diff_render_graph(tb, g)
  match cls {
    BfsVsDijkstraUnit => diff_render_bfs_dijkstra(tb, g)
    DijkstraVsBellmanFord => diff_render_dijkstra_bellman(tb, g)
    FloydWarshallVsJohnson => diff_render_floyd_johnson(tb, g)
  }
  tb.build()
}

// ===========================================================================
// 锚点单元测试：以确定的小图验证三个等价类的一致性判定与报告构建。
// （≥100 次随机实例的属性测试见 task 15.2 `prop_differential_test.mbt`。）
// ===========================================================================

///|
/// 锚点：链 0→1→2→3（单位权）上 BFS 与 Dijkstra 一致；节点 4 孤立（两侧不可达）。
test "Feature: championship-v1-upgrade, task 15.1: BFS vs Dijkstra unit anchor" {
  let g : FuzzGraph = {
    n: 5,
    edges: [(0, 1, 1.0), (1, 2, 1.0), (2, 3, 1.0), (0, 2, 5.0)],
  }
  // 单位权下 0→2 的「直接边」与「0→1→2」同为 2 跳 vs 1 跳：Dijkstra 取 1 跳，
  // BFS 亦 1 跳（边视为单位）；两者对全部目标一致。
  assert_true(diff_bfs_dijkstra_unit_consistent(g))
  assert_true(differential_consistent(BfsVsDijkstraUnit, g))
  // 含自环 + 平行边的图仍一致。
  let g2 : FuzzGraph = {
    n: 3,
    edges: [(0, 0, 2.0), (0, 1, 3.0), (0, 1, 7.0), (1, 2, 1.0)],
  }
  assert_true(differential_consistent(BfsVsDijkstraUnit, g2))
  // 空图与单节点图平凡一致。
  assert_true(differential_consistent(BfsVsDijkstraUnit, { n: 0, edges: [] }))
  assert_true(differential_consistent(BfsVsDijkstraUnit, { n: 1, edges: [] }))
}

///|
/// 锚点：非负权图上 Dijkstra 与 Bellman-Ford 一致（含「绕路更短」与不可达节点）。
test "Feature: championship-v1-upgrade, task 15.1: Dijkstra vs Bellman-Ford anchor" {
  let g : FuzzGraph = {
    n: 5,
    edges: [(0, 1, 4.0), (0, 2, 1.0), (2, 1, 1.0), (1, 3, 1.0), (2, 3, 5.0)],
  }
  // 0→3 经 0-2-1-3 = 3 优于 0-1-3 = 5；4 不可达。两算法应一致。
  assert_true(diff_dijkstra_bellman_consistent(g))
  assert_true(differential_consistent(DijkstraVsBellmanFord, g))
  // 小数权（0.01 级）与平行边。
  let g2 : FuzzGraph = {
    n: 3,
    edges: [(0, 1, 0.01), (0, 1, 0.50), (1, 2, 2.25)],
  }
  assert_true(differential_consistent(DijkstraVsBellmanFord, g2))
  assert_true(
    differential_consistent(DijkstraVsBellmanFord, { n: 0, edges: [] }),
  )
}

///|
/// 锚点：整数权图上 Floyd-Warshall 与 Johnson 全对距离一致（含多连通分量）。
test "Feature: championship-v1-upgrade, task 15.1: Floyd-Warshall vs Johnson anchor" {
  let g : FuzzGraph = {
    n: 5,
    edges: [(0, 1, 3.0), (1, 2, 4.0), (0, 2, 10.0), (3, 4, 2.0)],
  }
  // 分量 {0,1,2} 与 {3,4} 互不连通：跨分量点对两侧一致判不可达。
  assert_true(diff_floyd_johnson_consistent(g))
  assert_true(differential_consistent(FloydWarshallVsJohnson, g))
  // 自环 + 平行边（取最小权）一致。
  let g2 : FuzzGraph = {
    n: 3,
    edges: [(0, 0, 1.0), (0, 1, 5.0), (0, 1, 2.0), (1, 2, 3.0)],
  }
  assert_true(differential_consistent(FloydWarshallVsJohnson, g2))
  assert_true(
    differential_consistent(FloydWarshallVsJohnson, { n: 0, edges: [] }),
  )
  assert_true(
    differential_consistent(FloydWarshallVsJohnson, { n: 1, edges: [] }),
  )
}

///|
/// 锚点：差分一致性在非负权生成器图上对单源等价类成立（生成器侧抽样烟囱测试，
/// 完整 ≥100 迭代属性测试见 task 15.2）。
test "Feature: championship-v1-upgrade, task 15.1: generators feed differential checks" {
  let rng = @infra_pbt.rng_new(0x9E37_79B9_7F4A_7C15)
  let gen = fuzz_graph_nonneg_gen(40, 200)
  for _ in 0..<32 {
    let g = gen.generate(rng)
    assert_true(differential_consistent(BfsVsDijkstraUnit, g))
    assert_true(differential_consistent(DijkstraVsBellmanFord, g))
  }
}

///|
/// 锚点：差分一致性与 `check_with_shrink` 协作——真实算法对随机图恒一致，
/// 故谓词全通过、无反例（passed=true, counterexample=None）。
test "Feature: championship-v1-upgrade, task 15.1: differential prop passes under shrink driver" {
  let gen = fuzz_graph_nonneg_gen(30, 150)
  let result = @infra_pbt.check_with_shrink(
    gen,
    fn(g) { differential_consistent(DijkstraVsBellmanFord, g) },
    shrink_fuzz_graph,
    iters=128,
  )
  assert_true(result.passed)
  assert_true(result.counterexample is None)
}

///|
/// 锚点：不一致报告构建（R16.7）——含等价类标识、种子、图实例与两侧输出。
/// 报告函数本身不判定一致性，对任意图均产出完整诊断；此处验证关键字段齐备。
test "Feature: championship-v1-upgrade, task 15.1: differential report contains key fields" {
  let g : FuzzGraph = { n: 3, edges: [(0, 1, 2.0), (1, 2, 3.0)] }
  let seed : UInt64 = 0xDEAD_BEEF_0000_1234
  let report = differential_report(DijkstraVsBellmanFord, g, seed)
  assert_true(report.length() > 0)
  // 等价类标识。
  assert_true(report.contains("Dijkstra↔Bellman-Ford"))
  // 随机种子（十进制）。
  assert_true(report.contains(seed.to_string()))
  // 图实例规模与边集。
  assert_true(report.contains("n=3"))
  assert_true(report.contains("m=2"))
  // 两侧输出标头。
  assert_true(report.contains("两侧输出"))
  // 另两个等价类的报告同样非空且带正确标识。
  let r_bfs = differential_report(BfsVsDijkstraUnit, g, seed)
  assert_true(r_bfs.contains("BFS↔Dijkstra"))
  let r_fj = differential_report(FloydWarshallVsJohnson, g, seed)
  assert_true(r_fj.contains("Floyd-Warshall↔Johnson"))
}
