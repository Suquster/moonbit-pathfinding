// shrink.mbt —— 反例收缩 `shrink_fuzz_graph`：为失败图实例产出「移除任一
// 节点 / 移除任一边」的更小候选集（task 7.2）。
//
// 设计依据（design.md §5.1 Fuzz_Generator · Requirement 17.6）：
//
//   pub fn shrink_fuzz_graph(g : FuzzGraph) -> Array[FuzzGraph]
//
// 设计哲学：
//   * 配合 `@infra_pbt.check_with_shrink(gen, prop, shrink, iters?)` 使用：
//     该组合子在发现失败实例后，反复调用本函数取候选集，挑选「仍然触发失败」
//     的更小候选继续收缩，直至无更小候选仍失败为止——此即「局部最小」：再
//     移除任一节点 / 任一边后失败不再复现（R17.6）。
//   * 终止性保证：候选集中**每个**元素都严格小于原图——要么节点数 -1，要么
//     边数 -1。因「节点数 + 边数」是非负整数且每步至少减 1，收缩必在有限步内
//     终止；配合 `shrink_iters_max`（1000）的迭代上限双重保险（R17.6）。
//   * 空图（n=0 且无边）已是最小，无更小候选 → 返回空数组，使 `check_with_shrink`
//     在此停止收缩。
//   * 全函数（total）实现：纯结构变换，无随机、无 I/O；不使用 abort/todo!/panic
//     占位，三后端结果逐元素一致。
//   * 候选构造避免 O(n²) 复制：以预分配 `Array` + `push` 线性构建每个候选的
//     边集，绝不在循环中做整数组 `+` 拼接。

///|
/// 推荐的收缩迭代上限（R17.6）：`shrink_fuzz_graph` 配合
/// `@infra_pbt.check_with_shrink` 使用时，应以 `iters=shrink_iters_max`
/// 限定收缩迭代次数不超过 1000，避免病态输入下的过长收缩。
///
/// 收缩本身具备终止性（每个候选严格更小），本上限为额外的安全护栏，并作为
/// 命名常量供调用方与属性测试统一引用，替代裸数字 1000。
pub let shrink_iters_max : Int = 1000

///|
/// 移除节点 `v`（`0 <= v < g.n`）后的更小图：节点数 -1，删除所有关联 `v` 的边
/// （源或目标为 `v`），并对编号 `> v` 的节点整体下移 1，使保留节点紧凑映射到
/// `0..g.n-2`。
///
/// 返回图的节点数严格小于原图（`g.n - 1`），故必为合法收缩候选。
fn remove_node(g : FuzzGraph, v : Int) -> FuzzGraph {
  let new_n = g.n - 1
  let kept : Array[(Int, Int, Double)] = []
  for e in g.edges {
    let (u, w, weight) = e
    // 关联被删节点的边一并删除。
    if u == v || w == v {
      continue
    }
    // 编号大于 v 的节点下移 1，维持 0..new_n-1 的紧凑编号。
    let nu = if u > v { u - 1 } else { u }
    let nw = if w > v { w - 1 } else { w }
    kept.push((nu, nw, weight))
  }
  { n: new_n, edges: kept }
}

///|
/// 移除第 `idx` 条边（`0 <= idx < g.edges.length()`）后的更小图：节点数不变，
/// 边集恰好少一条。
///
/// 返回图的边数严格小于原图（`len - 1`），故必为合法收缩候选。
fn remove_edge(g : FuzzGraph, idx : Int) -> FuzzGraph {
  let kept : Array[(Int, Int, Double)] = []
  let mut i = 0
  let len = g.edges.length()
  while i < len {
    if i != idx {
      kept.push(g.edges[i])
    }
    i += 1
  }
  { n: g.n, edges: kept }
}

///|
/// 反例收缩（R17.6）：为失败图实例 `g` 产出收缩候选集，每个候选都是「移除
/// `g` 中任一节点」或「移除任一边」后的更小 `FuzzGraph`。
///
/// 候选集构成：
///   * 移除节点：对每个节点 `v ∈ 0..n-1`，产出删除 `v` 及其关联边、并对
///     剩余节点重新紧凑编号后的图（节点数 -1）。节点移除带来更大幅度的缩减，
///     故优先排在候选集前部，利于 `check_with_shrink` 更快逼近局部最小。
///   * 移除边：对每条边 `idx ∈ 0..m-1`，产出仅去掉该边的图（边数 -1）。
///
/// 终止性：所有候选都严格小于 `g`（节点数或边数减少其一），保证收缩可终止。
/// 空图（`n == 0` 且无边）已无更小候选，返回空数组。
///
/// 与 `@infra_pbt.check_with_shrink(gen, prop, shrink, iters?)` 兼容：作为其
/// `shrink : (T) -> Array[T]` 参数传入即可驱动迭代收缩；局部最小性定义为
/// 「再移除任一节点 / 任一边后失败不再复现」。
pub fn shrink_fuzz_graph(g : FuzzGraph) -> Array[FuzzGraph] {
  let candidates : Array[FuzzGraph] = []
  // 优先产出「移除节点」候选（缩减幅度更大）。
  let mut v = 0
  while v < g.n {
    candidates.push(remove_node(g, v))
    v += 1
  }
  // 再产出「移除单条边」候选。
  let mut idx = 0
  let m = g.edges.length()
  while idx < m {
    candidates.push(remove_edge(g, idx))
    idx += 1
  }
  candidates
}
