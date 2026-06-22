// Feature: championship-v1-upgrade, Property 15: 循环不变式成立
//
// prop_loop_invariant_test.mbt —— 循环不变式属性测试（任务 12.2）。
//
//   Property 15: 循环不变式成立
//   ------------------------------------------------------------------
//   *对任意* 随机生成的输入图：
//     * Dijkstra 主循环按弹出顺序记录的「已确定距离」序列单调非降——即
//       `dijkstra_pop_monotonic(popped)` 在每次成功弹出后恒为真（R10.3）；
//     * BFS 主循环中，每次将节点加入队列后，队列内任意两节点的层级差绝对值
//       ≤1——即 `bfs_level_invariant(pending)` 恒为真（R10.4）。
//   若某次迭代后不变式求值为假，立即终止该测试用例并报告被违反的不变式名称
//   与迭代序号（R10.6）；测试以 ≥100 个随机图驱动（R10.5）。
//
//   本测试在测试期独立复刻 Dijkstra / BFS 主循环（与 `src/directed/dijkstra.mbt`、
//   `src/unweighted/bfs.mbt` 的生产实现同构），在每次迭代「插桩」记录弹出顺序
//   距离序列 / 当前队列层级序列，并用 `loop_invariants.mbt`（任务 12.1）中的
//   `dijkstra_pop_monotonic` 与 `bfs_level_invariant` 谓词在运行时断言不变式。
//   复刻而非直接调用算法包，是因为生产函数仅返回路径/代价、不暴露弹出顺序与
//   队列层级这两条「内部循环状态」；复刻保证插桩点与生产主循环逐行对应。
//
// **Validates: Requirements 10.3, 10.4, 10.5, 10.6**

///|
/// 循环不变式校验结果（R10.6 报告载体）。
///
///   * `Held` —— 整个主循环每次迭代后不变式均成立；
///   * `Violated(name, iter)` —— 在第 `iter` 次迭代后名为 `name` 的不变式被
///     违反，主循环已立即终止。`name` / `iter` 即 R10.6 要求报告的「被违反的
///     不变式名称与迭代序号」。
enum LoopInvariantOutcome {
  Held
  Violated(String, Int)
} derive(Eq)

///|
/// 手动实现 `Show`（供 `inspect` 使用），避免 `derive(Show)` 的弃用告警。
/// `Held` 渲染为 `Held`，`Violated` 渲染为 `Violated("名称", 序号)`。
impl Show for LoopInvariantOutcome with fn output(self, logger) {
  match self {
    Held => logger.write_string("Held")
    Violated(name, iter) =>
      logger.write_string("Violated(\{name.escape()}, \{iter})")
  }
}

///|
/// 将校验结果渲染为人类可读报告字符串（R10.6 报告呈现）。
///
/// 仅做单次字符串插值，不在循环内拼接，符合质量约束（禁止 O(n²) 字符串拼接）。
fn outcome_report(o : LoopInvariantOutcome) -> String {
  match o {
    Held => "all loop invariants held"
    Violated(name, iter) => "invariant \{name} violated at iteration \{iter}"
  }
}

///|
/// 由确定性随机源 `rng` 构造节点为 `0..<k` 的随机**带权有向图**（Dijkstra 用），
/// 邻接表 `Map[Int, Array[(Int, Int)]]`（节点 → `[(目标, 权重)]`）。
///
/// 每节点出度 ∈ `[0, k]`，目标取自 `[0, k)` 并去重；权重取自 `[0, 20]` 的
/// **非负**整数（Dijkstra 前置条件），且远低于 `Weight for Int` 的饱和阈值，
/// 保证弹出单调性成立。
fn li_build_weighted_graph(
  rng : @infra_pbt.Rng,
  k : Int,
) -> Map[Int, Array[(Int, Int)]] {
  let adj : Map[Int, Array[(Int, Int)]] = Map([])
  for u in 0..<k {
    let outs : Array[(Int, Int)] = []
    let seen : Array[Int] = []
    let deg = rng.next_range(0, k)
    for _e in 0..<deg {
      let v = rng.next_below(k)
      if !seen.contains(v) {
        seen.push(v)
        let w = rng.next_range(0, 20)
        outs.push((v, w))
      }
    }
    adj[u] = outs
  }
  adj
}

///|
/// 由确定性随机源 `rng` 构造节点为 `0..<k` 的随机**无权有向图**（BFS 用），
/// 邻接表 `Map[Int, Array[Int]]`（节点 → `[目标]`）。
///
/// 每节点出度 ∈ `[0, k]`，目标取自 `[0, k)` 并去重，覆盖汇点到稠密节点全谱。
fn li_build_unweighted_graph(
  rng : @infra_pbt.Rng,
  k : Int,
) -> Map[Int, Array[Int]] {
  let adj : Map[Int, Array[Int]] = Map([])
  for u in 0..<k {
    let outs : Array[Int] = []
    let seen : Array[Int] = []
    let deg = rng.next_range(0, k)
    for _e in 0..<deg {
      let v = rng.next_below(k)
      if !seen.contains(v) {
        seen.push(v)
        outs.push(v)
      }
    }
    adj[u] = outs
  }
  adj
}

///|
/// 在随机带权有向图上运行**插桩版 Dijkstra 主循环**，校验弹出单调性不变式
/// （R10.3）。
///
/// 主循环与 `src/directed/dijkstra.mbt` 同构：二叉最小堆 + 陈旧条目惰性跳过；
/// 目标谓词恒为假，故遍历全部可达节点，得到完整弹出序列。每次成功弹出（非陈旧）
/// 后将该已确定距离追加到 `popped` 并立即对其求 `dijkstra_pop_monotonic`——
/// 若为假则立即返回 `Violated("dijkstra-pop-monotonic", iter)`（R10.6）。
fn li_run_dijkstra(rng : @infra_pbt.Rng) -> LoopInvariantOutcome {
  let k = rng.next_range(1, 8)
  let adj = li_build_weighted_graph(rng, k)
  let start = rng.next_below(k)
  let dist : Map[Int, Int] = Map([])
  let pq : @core.PQueue[Int, Int] = @core.PQueue::new()
  dist[start] = 0
  pq.push(0, start)
  let popped : Array[Int] = []
  let mut iter = 0
  while !pq.is_empty() {
    let (d, u) = pq.pop().unwrap()
    // 跳过陈旧条目：被更优更新覆盖的旧键不计入弹出序列（与生产实现一致）。
    let stale = match dist.get(u) {
      Some(cur) => d > cur
      None => true
    }
    if stale {
      continue
    }
    iter += 1
    popped.push(d)
    // 不变式（R10.3）：弹出序列单调非降。违反即报告名称与迭代序号。
    if !dijkstra_pop_monotonic(popped) {
      return Violated("dijkstra-pop-monotonic", iter)
    }
    let outs = match adj.get(u) {
      Some(xs) => xs
      None => []
    }
    for pair in outs {
      let (v, w) = pair
      let nd = d + w
      let improve = match dist.get(v) {
        Some(existing) => nd < existing
        None => true
      }
      if improve {
        dist[v] = nd
        pq.push(nd, v)
      }
    }
  }
  Held
}

///|
/// 在随机无权有向图上运行**插桩版 BFS 主循环**，校验层序不变式（R10.4）。
///
/// 主循环与 `src/unweighted/bfs.mbt` 同构：FIFO 队列（`head` 游标）+ `visited`
/// 去重；目标谓词恒为假，故遍历整个可达子图。每次将节点加入队列后，收集当前
/// 待扩展区间 `queue[head..]` 内各节点层级并立即对其求 `bfs_level_invariant`
/// ——若为假则立即返回 `Violated("bfs-level-invariant", iter)`（R10.6）。
fn li_run_bfs(rng : @infra_pbt.Rng) -> LoopInvariantOutcome {
  let k = rng.next_range(1, 8)
  let adj = li_build_unweighted_graph(rng, k)
  let start = rng.next_below(k)
  let queue : Array[Int] = [start]
  let level : Map[Int, Int] = Map([])
  let visited : Map[Int, Bool] = Map([])
  level[start] = 0
  visited[start] = true
  let mut head = 0
  let mut iter = 0
  while head < queue.length() {
    let cur = queue[head]
    head += 1
    let lcur = match level.get(cur) {
      Some(l) => l
      None => 0
    }
    let outs = match adj.get(cur) {
      Some(xs) => xs
      None => []
    }
    for next in outs {
      if visited.contains(next) {
        continue
      }
      visited[next] = true
      level[next] = lcur + 1
      queue.push(next)
      iter += 1
      // 收集当前待扩展队列 queue[head..] 各节点的层级。
      let pending : Array[Int] = []
      let mut j = head
      while j < queue.length() {
        match level.get(queue[j]) {
          Some(l) => pending.push(l)
          None => ()
        }
        j += 1
      }
      // 不变式（R10.4）：队列内任意两节点层级差绝对值 ≤1。违反即报告。
      if !bfs_level_invariant(pending) {
        return Violated("bfs-level-invariant", iter)
      }
    }
  }
  Held
}

///|
/// 单次随机场景：先后在两张独立随机图上运行插桩 Dijkstra 与 BFS。任一不变式
/// 被违反则返回对应 `Violated`；两者均成立才返回 `Held`。
fn li_scenario(rng : @infra_pbt.Rng) -> LoopInvariantOutcome {
  match li_run_dijkstra(rng) {
    Held => li_run_bfs(rng)
    violated => violated
  }
}

///|
/// Feature: championship-v1-upgrade, Property 15: 循环不变式成立
/// （holds_for_all 模板，iters ≥ 100；每次迭代各跑一张随机带权图与无权图）
///
/// **Validates: Requirements 10.3, 10.4, 10.5, 10.6**
test "Feature: championship-v1-upgrade, Property 15: Dijkstra pop-order distances are monotonic non-decreasing and BFS queue levels differ by at most 1 across random graphs" {
  let gen = @infra_pbt.Gen::new(fn(rng) { li_scenario(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(o) { o is Held }, iters=100))
}

// --- 报告机制与具体实例的单元测试（R10.6 报告格式 + 不变式在具体图上成立）---

///|
test "outcome_report renders Held and Violated with invariant name and iteration index" {
  inspect(outcome_report(Held), content="all loop invariants held")
  inspect(
    outcome_report(Violated("dijkstra-pop-monotonic", 7)),
    content="invariant dijkstra-pop-monotonic violated at iteration 7",
  )
  inspect(
    outcome_report(Violated("bfs-level-invariant", 3)),
    content="invariant bfs-level-invariant violated at iteration 3",
  )
}

///|
test "instrumented Dijkstra holds pop-monotonicity on a seeded random graph" {
  let rng = @infra_pbt.rng_new(0x5151_2025_UL)
  inspect(li_run_dijkstra(rng), content="Held")
}

///|
test "instrumented BFS holds level-invariant on a seeded random graph" {
  let rng = @infra_pbt.rng_new(0x7a7a_2025_UL)
  inspect(li_run_bfs(rng), content="Held")
}
