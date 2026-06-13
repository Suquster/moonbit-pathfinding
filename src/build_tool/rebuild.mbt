// rebuild.mbt —— 脏传播与最小重建集（旗舰深化，旁路新增）。
//
// paper-to-code（design.md §4.4 / §「算法说明」）：对应 Mokhov, Mitchell,
// Peyton Jones《Build Systems à la Carte》的 **rebuilder** 维——决定「是否
// 重建某目标」。脏传播以**前向可达传递闭包**（图可达性）实现：沿依赖边
// `(u, v)`（`v` 依赖 `u`）从脏输入 `u` 走向其下游 `v`，收集全部受影响目标。
//
// 该结果同时满足**充分性**（每个从脏输入前向可达的目标都被包含，R5.5）与
// **最小性**（每个被包含目标都可由某脏输入到达，R5.6）——二者是同一可达闭包
// 的两面（正确性属性 5、6）。脏检查复用冻结的 `is_dirty`（mtime + 内容哈希），
// 重建调度复用冻结的 `schedule`，不重写既有逻辑（R13）。
//
// 三后端一致：可达集以 `Map[Target, Bool]` 标记、输出按 `g.nodes` 原序导出，
// 不依赖哈希表遍历顺序。

///|
/// 数组是否含某目标。
fn list_contains_target(arr : Array[Target], x : Target) -> Bool {
  for t in arr {
    if t == x {
      return true
    }
  }
  false
}

///|
/// 由缓存计算脏输入集合：`is_dirty` 为真的目标（复用冻结 `is_dirty`）。
pub fn dirty_targets(g : BuildGraph, cache : BuildCache) -> Array[Target] {
  let out : Array[Target] = []
  for n in g.nodes {
    if is_dirty(n, cache) {
      out.push(n)
    }
  }
  out
}

///|
/// 沿依赖边前向传播：脏输入 ∪ 其全部传递下游（前向可达闭包，R5.1）。
///
/// 输出按 `g.nodes` 原序导出以保证三后端确定性；不在节点集中的脏输入（防御性）
/// 追加在末尾。
pub fn propagate_dirty(
  g : BuildGraph,
  dirty_inputs : Array[Target],
) -> Array[Target] {
  let reachable : Map[Target, Bool] = Map([])
  let stack : Array[Target] = []
  for d in dirty_inputs {
    if !reachable.contains(d) {
      reachable[d] = true
      stack.push(d)
    }
  }
  while stack.length() > 0 {
    let cur = stack.pop().unwrap()
    for edge in g.edges {
      let (u, v) = edge
      if u == cur && !reachable.contains(v) {
        reachable[v] = true
        stack.push(v)
      }
    }
  }
  let out : Array[Target] = []
  for n in g.nodes {
    if reachable.contains(n) {
      out.push(n)
    }
  }
  // 防御：脏输入不在节点集时仍纳入（可达定义下自身可达）。
  for d in dirty_inputs {
    if !list_contains_target(g.nodes, d) && !list_contains_target(out, d) {
      out.push(d)
    }
  }
  out
}

///|
/// 最小重建集 = 脏输入及其传递下游目标的并集（R5.2）。等于 `propagate_dirty`
/// 的结果，既充分（R5.5）又最小（R5.6）。
pub fn minimal_rebuild_set(
  g : BuildGraph,
  dirty_inputs : Array[Target],
) -> Array[Target] {
  propagate_dirty(g, dirty_inputs)
}

///|
/// 仅对重建集内目标按拓扑序产出调度，重建集外目标不参与（R5.4）。
///
/// 先取重建集导出子图（仅含重建集内节点与两端皆在集内的边），再复用冻结
/// `schedule` 产出批次，保证拓扑不变量与批内独立。
pub fn rebuild_schedule(
  g : BuildGraph,
  dirty_inputs : Array[Target],
  jobs : Int,
) -> Array[Array[Target]] {
  let set = minimal_rebuild_set(g, dirty_inputs)
  let inset : Map[Target, Bool] = Map([])
  for t in set {
    inset[t] = true
  }
  let sub_edges : Array[(Target, Target)] = []
  for edge in g.edges {
    let (u, v) = edge
    if inset.contains(u) && inset.contains(v) {
      sub_edges.push(edge)
    }
  }
  schedule(BuildGraph::new(set, sub_edges), jobs)
}
