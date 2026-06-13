// dynamic.mbt —— 动态依赖发现与重新调度（旗舰深化，旁路新增）。
//
// paper-to-code（design.md §4.6）：构建动作执行后才确定的依赖（如编译时扫描出
// 的头文件）并入图后重新调度，对标 Ninja 的 `depfile` / Bazel 的动态依赖。
// 追加保持图不可变（旁路扩展契约 R13.5）：`add_dynamic_deps` 返回新图，既有图
// 不变；`reschedule_with_dynamic` 复用冻结的 `detect_cycle`（Tarjan SCC）与
// `schedule`，引入环时返回 `Err(Cycle)` 并拒绝调度（R8.3）。

///|
/// 为目标追加动态依赖：登记缺失节点、追加边 `(dyn_dep, target)`（动态依赖须在
/// 目标之前构建），返回**新图**（不可变，既有图不变，R8.1）。
pub fn add_dynamic_deps(
  g : BuildGraph,
  target : Target,
  dyn_deps : Array[Target],
) -> BuildGraph {
  let nodes : Array[Target] = []
  let seen : Map[Target, Bool] = Map([])
  fn ensure(t : Target) -> Unit {
    if !seen.contains(t) {
      seen[t] = true
      nodes.push(t)
    }
  }

  for n in g.nodes {
    ensure(n)
  }
  ensure(target)
  for d in dyn_deps {
    ensure(d)
  }
  let edges : Array[(Target, Target)] = []
  for e in g.edges {
    edges.push(e)
  }
  for d in dyn_deps {
    edges.push((d, target))
  }
  BuildGraph::new(nodes, edges)
}

///|
/// 并入动态依赖后重新调度（R8.2）；若追加引入依赖环，经 `detect_cycle` 报告
/// 构成环的目标序列并拒绝产出调度（返回 `Err(Cycle)`，R8.3）。
pub fn reschedule_with_dynamic(
  g : BuildGraph,
  target : Target,
  dyn_deps : Array[Target],
  jobs : Int,
) -> Result[Array[Array[Target]], Cycle] {
  let g2 = add_dynamic_deps(g, target, dyn_deps)
  match detect_cycle(g2) {
    Some(nodes) => Err(Cycle::new(nodes))
    None => Ok(schedule(g2, jobs))
  }
}
