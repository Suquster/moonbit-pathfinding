// consistency.mbt —— 线性扫描与图着色一致性桥，旗舰深化旁路新增。
//
// paper-to-code：Poletto-Sarnak 1999（线性扫描）与图着色在「是否需要溢出」结论
// 上的一致性对照。本文件仅提供纯函数辅助桥，既有 `allocate_linear_scan` 行为
// 完全冻结。
//
// 设计落点（design.md §4.x，R3.3/R3.5）：
//   * `interference_from_intervals`：由活跃区间重叠构造干涉图；
//   * `allocation_has_spill`：判定分配结果是否含 `Spill`，作为「是否需要溢出」
//     结论比较的纯函数辅助（线性扫描与图着色一致性，P5）。

///|
/// 两个活跃区间是否重叠：`a.start <= b.end && b.start <= a.end`。
fn intervals_overlap_c(a : LiveInterval, b : LiveInterval) -> Bool {
  a.start <= b.end && b.start <= a.end
}

///|
/// 由活跃区间集合构造干涉图：区间重叠的变量之间建无向边（较小 id 在前）。
pub fn interference_from_intervals(
  intervals : Array[LiveInterval],
) -> InterferenceGraph {
  let nodes : Array[Var] = []
  let seen : Map[Int, Bool] = Map([])
  for iv in intervals {
    if !(seen.contains(iv.variable.id)) {
      seen[iv.variable.id] = true
      nodes.push(iv.variable)
    }
  }
  let edge_set : Map[(Int, Int), Bool] = Map([])
  for i in 0..<intervals.length() {
    for j in (i + 1)..<intervals.length() {
      let a = intervals[i]
      let b = intervals[j]
      if a.variable.id != b.variable.id && intervals_overlap_c(a, b) {
        let lo = if a.variable.id < b.variable.id {
          a.variable.id
        } else {
          b.variable.id
        }
        let hi = if a.variable.id < b.variable.id {
          b.variable.id
        } else {
          a.variable.id
        }
        edge_set[(lo, hi)] = true
      }
    }
  }
  let edges : Array[(Var, Var)] = []
  for kv in edge_set {
    let ((lo, hi), _) = kv
    edges.push(({ id: lo }, { id: hi }))
  }
  edges.sort_by(fn(e1, e2) {
    let (a1, b1) = e1
    let (a2, b2) = e2
    if a1.id != a2.id {
      a1.id - a2.id
    } else {
      b1.id - b2.id
    }
  })
  // 节点按 id 升序规范化。
  nodes.sort()
  { nodes, edges }
}

///|
/// 分配结果是否含 `Spill`（「是否需要溢出」结论判定）。
pub fn allocation_has_spill(alloc : Map[Var, Location]) -> Bool {
  for kv in alloc {
    let (_, loc) = kv
    match loc {
      Spill(_) => return true
      Reg(_) => ()
    }
  }
  false
}
