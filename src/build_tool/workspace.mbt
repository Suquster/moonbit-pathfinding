// workspace.mbt —— 多包工作区模型 `Workspace`（G-A1，对拍 moon 语义）。
//
// paper-to-code：moon 的多包工作区（module = 多 package + moon.pkg 依赖声明）
// 与 Cargo workspace / Go module graph 的共同语义内核：
//   * 包依赖图（package → 其 import 的包），必须无环；
//   * 构建顺序 = 依赖图的拓扑序（被依赖者先建）；
//   * 增量构建计划 = 「变更包 + 其全部反向传递依赖（dependents）」，
//     未受影响的包零重建（对拍 `moon build` 的最小重建承诺）；
//   * 发布顺序 = 拓扑序（mooncakes 发布时被依赖包必须先可见）。
//
// 复用既有 `BuildGraph` / `topo_order` / `detect_cycle`：把「包」映射为
// `Target`、「u 被 v 依赖」映射为边 `(u, v)`，语义与目标级构建图同构，
// 差分测试直接对拍二者。

///|
/// 工作区包声明：名称 + 其依赖的包名列表（对应 moon.pkg 的 import 段）。
pub struct WorkspacePackage {
  name : String
  deps : Array[String]
}

///|
/// 由名称与依赖列表构造包声明。
pub fn WorkspacePackage::new(
  name : String,
  deps : Array[String],
) -> WorkspacePackage {
  { name, deps }
}

///|
/// 多包工作区：包声明集合（名称唯一）。
pub struct Workspace {
  packages : Array[WorkspacePackage]
}

///|
/// 由包声明集合构造工作区。
pub fn Workspace::new(packages : Array[WorkspacePackage]) -> Workspace {
  { packages, }
}

///|
/// 工作区合法性校验：包名唯一、依赖均指向工作区内已声明的包。
/// 返回首个违规的诊断消息；合法返回 None。
pub fn Workspace::validate(self : Workspace) -> String? {
  let seen : Map[String, Bool] = Map([])
  for p in self.packages {
    if seen.get(p.name) is Some(_) {
      return Some("duplicate package: " + p.name)
    }
    seen.set(p.name, true)
  }
  for p in self.packages {
    for d in p.deps {
      if seen.get(d) is None {
        return Some("unknown dependency: " + p.name + " -> " + d)
      }
    }
  }
  None
}

///|
/// 把工作区降到目标级构建图（包 → Target；「d 被 p 依赖」→ 边 (d, p)）。
/// 拓扑 / 环检测 / 调度与目标级构建图共用同一实现（语义同构）。
pub fn Workspace::to_build_graph(self : Workspace) -> BuildGraph {
  let nodes : Array[Target] = []
  let edges : Array[(Target, Target)] = []
  for p in self.packages {
    nodes.push(Target::new(p.name))
  }
  for p in self.packages {
    for d in p.deps {
      edges.push((Target::new(d), Target::new(p.name)))
    }
  }
  BuildGraph::new(nodes, edges)
}

///|
/// 构建顺序（= 发布顺序）：依赖图拓扑序，被依赖包先行；有环返回 Err。
pub fn Workspace::build_order(self : Workspace) -> Result[Array[String], Cycle] {
  match topo_order(self.to_build_graph()) {
    Ok(ts) => {
      let out : Array[String] = []
      for t in ts {
        out.push(t.name)
      }
      Ok(out)
    }
    Err(c) => Err(c)
  }
}

///|
/// 传递依赖闭包：`name` 直接与间接依赖的全部包名（不含自身），
/// 按 BFS 层序去重返回。未知包名返回空数组。
pub fn Workspace::transitive_deps(
  self : Workspace,
  name : String,
) -> Array[String] {
  let dep_map : Map[String, Array[String]] = Map([])
  for p in self.packages {
    dep_map.set(p.name, p.deps)
  }
  let out : Array[String] = []
  let visited : Map[String, Bool] = Map([])
  let queue : Array[String] = []
  match dep_map.get(name) {
    None => return out
    Some(ds) =>
      for d in ds {
        queue.push(d)
      }
  }
  let mut head = 0
  while head < queue.length() {
    let cur = queue[head]
    head = head + 1
    if visited.get(cur) is Some(_) {
      continue
    }
    visited.set(cur, true)
    out.push(cur)
    match dep_map.get(cur) {
      Some(ds) =>
        for d in ds {
          queue.push(d)
        }
      None => ()
    }
  }
  out
}

///|
/// 反向传递依赖（dependents）：直接或间接依赖 `name` 的全部包名
/// （不含自身），BFS 层序去重。
pub fn Workspace::dependents(self : Workspace, name : String) -> Array[String] {
  let rev : Map[String, Array[String]] = Map([])
  for p in self.packages {
    for d in p.deps {
      match rev.get(d) {
        Some(arr) => arr.push(p.name)
        None => rev.set(d, [p.name])
      }
    }
  }
  let out : Array[String] = []
  let visited : Map[String, Bool] = Map([])
  let queue : Array[String] = []
  match rev.get(name) {
    None => return out
    Some(us) =>
      for u in us {
        queue.push(u)
      }
  }
  let mut head = 0
  while head < queue.length() {
    let cur = queue[head]
    head = head + 1
    if visited.get(cur) is Some(_) {
      continue
    }
    visited.set(cur, true)
    out.push(cur)
    match rev.get(cur) {
      Some(us) =>
        for u in us {
          queue.push(u)
        }
      None => ()
    }
  }
  out
}

///|
/// 增量构建计划：给定变更包集合，返回「需重建的包」按构建顺序排列
/// （= 变更包 ∪ 其全部 dependents，取拓扑序中该子集的相对顺序）。
/// 未受影响的包不出现（零重建，最小重建承诺）；有环返回 Err。
pub fn Workspace::rebuild_plan(
  self : Workspace,
  changed : Array[String],
) -> Result[Array[String], Cycle] {
  let affected : Map[String, Bool] = Map([])
  for c in changed {
    affected.set(c, true)
    for d in self.dependents(c) {
      affected.set(d, true)
    }
  }
  match self.build_order() {
    Ok(order) => {
      let out : Array[String] = []
      for name in order {
        if affected.get(name) is Some(_) {
          out.push(name)
        }
      }
      Ok(out)
    }
    Err(c) => Err(c)
  }
}
