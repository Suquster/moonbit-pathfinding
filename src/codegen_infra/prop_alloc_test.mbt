// prop_alloc_test.mbt —— 方向三 Codegen_Infra（R3）寄存器分配干涉不变量属性
// 测试（任务 11.3）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 7，复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all`
// 模板（每条属性 ≥100 次迭代，由 `holds_for_all` 默认 `iters=100` 保证）。
//
// Property 7：寄存器分配干涉不变量
//   对任意由生成器产生的变量干涉图与可用寄存器数量 K，图着色
//   （`allocate_coloring`）与线性扫描（`allocate_linear_scan`）两种策略输出的
//   分配方案中，任意两个相互干涉的变量都不共享同一寄存器。
//
//   * 图着色：干涉关系由干涉图的边显式给出——对每条边 `(a, b)`，若两端均着色
//     为寄存器 `Reg`，则编号必须不同。
//   * 线性扫描：干涉关系由活跃区间是否重叠隐式给出——两区间
//     `[start_a, end_a]` 与 `[start_b, end_b]` 重叠（`start_a <= end_b &&
//     start_b <= end_a`）时即相互干涉；若两者均着色为 `Reg`，编号必须不同。
//     该重叠判定与 `allocate_linear_scan` 内部「终点 `end >= 当前起点` 才视为
//     仍活跃」的过期回收语义一致（终点与下一区间起点相接亦视为重叠）。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`。

// ---------------------------------------------------------------------------
// 生成器（generators）
// ---------------------------------------------------------------------------

///|
/// 随机干涉图 + 寄存器数生成器（interference graph + register count generator）。
///
/// 节点按 `id = 0 .. n-1` 线性编号（`n ∈ [1, 8]`）；对每对 `i < j` 以约 50%
/// 概率加入无向干涉边 `(n_i, n_j)`（较小 id 在前，满足 `InterferenceGraph`
/// 「约定以较小 id 在前由构造者保证」）。寄存器数 `K ∈ [1, 4]`，覆盖「寄存器
/// 充足全部着色」与「寄存器不足触发溢出」两种情形。
///
/// 规模刻意保持较小，以在每次迭代内充分覆盖「孤立点 / 链 / 团 / 多团」等干涉
/// 形态，同时保证三后端测试可在合理时间内完成。
fn gen_interference_case() -> @infra_pbt.Gen[(InterferenceGraph, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 8)
    let nodes : Array[Var] = []
    for i in 0..<n {
      nodes.push({ id: i })
    }
    let edges : Array[(Var, Var)] = []
    // 仅生成「低编号 → 高编号」无向边，保证较小 id 在前且不产生自环。
    for i in 0..<n {
      for j in (i + 1)..<n {
        if rng.next_bool() {
          edges.push(({ id: i }, { id: j }))
        }
      }
    }
    let k = rng.next_range(1, 4)
    ({ nodes, edges }, k)
  })
}

///|
/// 随机活跃区间集合 + 寄存器数生成器（live intervals + register count generator）。
///
/// 生成 `n ∈ [1, 8]` 个活跃区间，变量 id 取 `0 .. n-1`（互不相同，保证分配结果
/// 键唯一）；每个区间起点 `start ∈ [0, 10]`，长度 `len ∈ [0, 6]`，终点
/// `end = start + len`（允许零长度区间）。寄存器数 `K ∈ [1, 4]`，覆盖「区间可
/// 全部着色」与「区间重叠超出寄存器数触发溢出」两种情形。
fn gen_linear_scan_case() -> @infra_pbt.Gen[(Array[LiveInterval], Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 8)
    let intervals : Array[LiveInterval] = []
    for i in 0..<n {
      let start = rng.next_range(0, 10)
      let len = rng.next_range(0, 6)
      intervals.push({ variable: { id: i }, start, end: start + len })
    }
    let k = rng.next_range(1, 4)
    (intervals, k)
  })
}

// ---------------------------------------------------------------------------
// 谓词（predicates）
// ---------------------------------------------------------------------------

///|
/// 图着色分配满足干涉不变量：对干涉图每条边 `(a, b)`，若两端均着色为寄存器，
/// 则编号互不相同。
fn coloring_respects_interference(input : (InterferenceGraph, Int)) -> Bool {
  let (g, k) = input
  let alloc = allocate_coloring(g, k)
  for e in g.edges {
    let (a, b) = e
    match (alloc.get(a), alloc.get(b)) {
      (Some(Reg(x)), Some(Reg(y))) => if x == y { return false }
      _ => ()
    }
  }
  true
}

///|
/// 两个活跃区间是否重叠（即相互干涉）：`start_a <= end_b && start_b <= end_a`。
/// 与 `allocate_linear_scan` 的过期回收语义一致（终点与下一区间起点相接亦视为
/// 重叠，因其过期条件为 `end >= 当前起点`）。
fn intervals_overlap(a : LiveInterval, b : LiveInterval) -> Bool {
  a.start <= b.end && b.start <= a.end
}

///|
/// 线性扫描分配满足干涉不变量：对任意一对重叠（相互干涉）的活跃区间，若两者
/// 均着色为寄存器，则编号互不相同。
fn linear_scan_respects_interference(
  input : (Array[LiveInterval], Int),
) -> Bool {
  let (intervals, k) = input
  let alloc = allocate_linear_scan(intervals, k)
  for i in 0..<intervals.length() {
    for j in (i + 1)..<intervals.length() {
      let a = intervals[i]
      let b = intervals[j]
      if intervals_overlap(a, b) {
        match (alloc.get(a.variable), alloc.get(b.variable)) {
          (Some(Reg(x)), Some(Reg(y))) => if x == y { return false }
          _ => ()
        }
      }
    }
  }
  true
}

// ---------------------------------------------------------------------------
// 属性测试（property tests）
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 7: 寄存器分配干涉不变量（图着色）
///
/// 对任意由生成器产生的变量干涉图与寄存器数 K，`allocate_coloring` 的分配方案
/// 中，任意相互干涉（相邻）的两变量都不共享同一寄存器。
///
/// **Validates: Requirements 3.3**
test "Feature: moonbit-infra-suite, Property 7: graph coloring interference invariant" {
  let ok = @infra_pbt.holds_for_all(
    gen_interference_case(),
    coloring_respects_interference,
  )
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 7: 寄存器分配干涉不变量（线性扫描）
///
/// 对任意由生成器产生的活跃区间集合与寄存器数 K，`allocate_linear_scan` 的分配
/// 方案中，任意相互干涉（活跃区间重叠）的两变量都不共享同一寄存器。
///
/// **Validates: Requirements 3.3**
test "Feature: moonbit-infra-suite, Property 7: linear scan interference invariant" {
  let ok = @infra_pbt.holds_for_all(
    gen_linear_scan_case(),
    linear_scan_respects_interference,
  )
  assert_true(ok)
}
