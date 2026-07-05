// robustness.mbt —— T6.3 鲁棒性回归：缺失输入与并发写冲突的检测与确定性报错。
//
// 与既有环检测（`detect_cycle`，Property 13）合并构成三类前置校验：
//   1. 循环依赖   —— `detect_cycle`（既有，Tarjan SCC）；
//   2. 缺失输入   —— `missing_inputs`：动作声明的输入既非任何动作的产物、
//                    也不在宿主提供的「已存在源文件」集合中；
//   3. 并发写竞争 —— `write_conflicts`：两个无依赖序约束的动作（可能被排入
//                    同一波并行执行）声明了同一产物。
//
// 全部报告按（id 升序、路径升序）排序输出，跨运行 / 跨后端逐项一致
// （确定性报错）。校验为纯函数，不执行任何动作。

///|
/// 缺失输入检测：返回 `(动作 id, 缺失输入路径)` 列表，按 id 升序、并列按
/// 路径升序。输入被视为「可满足」当且仅当它是某个动作的产物，或包含在
/// `sources`（宿主声明的既有源文件）中。空返回即校验通过。
pub fn missing_inputs(
  actions : Array[Action],
  sources : Array[String],
) -> Array[(String, String)] {
  let producible : Map[String, Bool] = Map([])
  for a in actions {
    for o in a.outputs {
      producible[o] = true
    }
  }
  for s in sources {
    producible[s] = true
  }
  let report : Array[(String, String)] = []
  for a in actions {
    for i in a.inputs {
      if !producible.contains(i) {
        report.push((a.id, i))
      }
    }
  }
  report.sort()
  report
}

///|
/// 并发写竞争检测：返回 `(动作 id₁, 动作 id₂, 冲突产物)` 列表（id₁ < id₂），
/// 按字典序排序。两个动作构成写竞争当且仅当它们声明了同一产物**且**依赖边
/// 的传递闭包未在二者之间建立执行先后序——此时它们可能被排入同一并行波，
/// 产物写入结果取决于执行时序（race）。空返回即校验通过。
pub fn write_conflicts(
  actions : Array[Action],
  edges : Array[(String, String)],
) -> Array[(String, String, String)] {
  // 传递闭包：reach[u] = u 可达的动作 id 集（DFS，O(V·(V+E)) 上界；
  // 动作集规模为构建规则量级，可接受）。
  let adj : Map[String, Array[String]] = Map([])
  for e in edges {
    let (from_id, to_id) = e
    let lst = adj.get(from_id).unwrap_or([])
    lst.push(to_id)
    adj[from_id] = lst
  }
  fn reaches(src : String, dst : String) -> Bool {
    let visited : Map[String, Bool] = Map([])
    let stack : Array[String] = [src]
    while stack.length() > 0 {
      let cur = stack.unsafe_pop()
      if cur == dst {
        return true
      }
      if visited.contains(cur) {
        continue
      }
      visited[cur] = true
      for nxt in adj.get(cur).unwrap_or([]) {
        stack.push(nxt)
      }
    }
    false
  }

  // 产物 → 声明该产物的动作 id 列表。
  let writers : Map[String, Array[String]] = Map([])
  let outputs_in_order : Array[String] = []
  for a in actions {
    for o in a.outputs {
      match writers.get(o) {
        Some(lst) => lst.push(a.id)
        None => {
          writers[o] = [a.id]
          outputs_in_order.push(o)
        }
      }
    }
  }
  let report : Array[(String, String, String)] = []
  for o in outputs_in_order {
    let ids = writers.get(o).unwrap_or([])
    if ids.length() < 2 {
      continue
    }
    for i in 0..<ids.length() {
      for j in (i + 1)..<ids.length() {
        let a = if ids[i] < ids[j] { ids[i] } else { ids[j] }
        let b = if ids[i] < ids[j] { ids[j] } else { ids[i] }
        // 二者之间存在任一方向的先后序即无竞争。
        if !reaches(a, b) && !reaches(b, a) {
          report.push((a, b, o))
        }
      }
    }
  }
  report.sort()
  report
}

///|
/// 构建前置校验：按「环 → 缺失输入 → 写竞争」顺序给出首个失败类别的确定性
/// 报告；全部通过返回 `Ok(())`。报告为单行文本，跨运行逐字节一致。
pub fn validate_build(
  actions : Array[Action],
  edges : Array[(String, String)],
  sources : Array[String],
) -> Result[Unit, String] {
  // 1. 循环依赖：复用既有 detect_cycle。
  let nodes : Array[Target] = []
  for a in actions {
    nodes.push(Target::new(a.id))
  }
  let graph_edges : Array[(Target, Target)] = []
  for e in edges {
    let (from_id, to_id) = e
    graph_edges.push((Target::new(from_id), Target::new(to_id)))
  }
  match detect_cycle(BuildGraph::new(nodes, graph_edges)) {
    Some(cycle) => {
      let names : Array[String] = []
      for t in cycle {
        names.push(t.name)
      }
      names.sort()
      return Err("cycle: " + names.join(" -> "))
    }
    None => ()
  }
  // 2. 缺失输入。
  let missing = missing_inputs(actions, sources)
  if missing.length() > 0 {
    let parts : Array[String] = []
    for m in missing {
      let (id, path) = m
      parts.push(id + " requires " + path)
    }
    return Err("missing inputs: " + parts.join("; "))
  }
  // 3. 并发写竞争。
  let conflicts = write_conflicts(actions, edges)
  if conflicts.length() > 0 {
    let parts : Array[String] = []
    for c in conflicts {
      let (a, b, o) = c
      parts.push(a + " and " + b + " both write " + o)
    }
    return Err("write conflicts: " + parts.join("; "))
  }
  Ok(())
}
