// benches/codegen_bench —— codegen_infra 旗舰深化五类工作负载的 native 基准与
// 平滑回归守卫（R13）。
//
// 五类负载：支配树构造（`build_dom_tree`）、最小 SSA 构造（`build_ssa_minimal`）、
// 图着色分配（`allocate_coloring_briggs`）、线性扫描分配（`allocate_linear_scan`）、
// SCCP（`sccp`）。规模化随机 CFG / 干涉图 / 区间集由确定性 @pbt.Rng 驱动，保证
// 可复现与三后端一致。基准计时经 `moon bench` 采集；工件（含机器标识、后端、
// 图规模、计时统计）与基线中位数比较的回归报告由仓库既有 guard 工具流处理，
// 写入 benches/results/（与既有基准包一致）。
//
// 可复现运行（native 前置）：
//   export LIBRARY_PATH=/usr/lib64:/usr/lib
//   moon bench benches/codegen_bench --target native
//
// _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_

///|
/// 规模化随机 CFG 生成：`n` 个块、前向边 DAG（出度 ≤ 2，含汇合）、块内含定义。
fn make_cfg(rng : @pbt.Rng, n : Int) -> Array[@cg.BasicBlock] {
  let pool = ["a", "b", "c", "x", "y"]
  let ops = ["+", "-", "*"]
  let succ : Array[Array[Int]] = []
  for _ in 0..<n {
    succ.push([])
  }
  for i in 1..<n {
    let start = rng.next_below(i)
    for off in 0..<i {
      let j = (start + off) % i
      if succ[j].length() < 2 {
        let mut dup = false
        for t in succ[j] {
          if t == i {
            dup = true
          }
        }
        if not(dup) {
          succ[j].push(i)
          break
        }
      }
    }
  }
  let extra = rng.next_below(n)
  let mut e = 0
  while e < extra {
    let a = rng.next_below(n - 1)
    let b = rng.next_range(a + 1, n - 1)
    if succ[a].length() < 2 {
      succ[a].push(b)
    }
    e = e + 1
  }
  let blocks : Array[@cg.BasicBlock] = []
  for i in 0..<n {
    succ[i].sort()
    let succ_labels : Array[String] = []
    for t in succ[i] {
      succ_labels.push("b" + t.to_string())
    }
    let instrs : Array[String] = []
    let ndef = rng.next_below(3)
    let mut d = 0
    while d < ndef {
      let lhs = pool[rng.next_below(pool.length())]
      let l = pool[rng.next_below(pool.length())]
      let r = pool[rng.next_below(pool.length())]
      let op = ops[rng.next_below(ops.length())]
      instrs.push(lhs + " = " + l + " " + op + " " + r)
      d = d + 1
    }
    if succ_labels.length() == 0 {
      instrs.push("ret " + pool[rng.next_below(pool.length())])
    } else if succ_labels.length() == 1 {
      instrs.push("br " + succ_labels[0])
    } else {
      instrs.push("cbr p " + succ_labels[0] + " " + succ_labels[1])
    }
    blocks.push({ label: "b" + i.to_string(), instrs, succs: succ_labels })
  }
  blocks
}

///|
/// 规模化随机干涉图：`n` 节点，每对约 `1/3` 概率连边。
fn make_interference(rng : @pbt.Rng, n : Int) -> @cg.InterferenceGraph {
  let nodes : Array[@cg.Var] = []
  for i in 0..<n {
    nodes.push({ id: i })
  }
  let edges : Array[(@cg.Var, @cg.Var)] = []
  for i in 0..<n {
    for j in (i + 1)..<n {
      if rng.next_below(3) == 0 {
        edges.push(({ id: i }, { id: j }))
      }
    }
  }
  { nodes, edges }
}

///|
/// 规模化随机活跃区间集：`n` 个区间，起点 / 长度随机。
fn make_intervals(rng : @pbt.Rng, n : Int) -> Array[@cg.LiveInterval] {
  let out : Array[@cg.LiveInterval] = []
  for i in 0..<n {
    let start = rng.next_range(0, 200)
    let len = rng.next_range(0, 20)
    out.push({ variable: { id: i }, start, end: start + len })
  }
  out
}

// ---------------------------------------------------------------------------
// 平滑回归守卫（smoke guard）—— 在 `moon test` / `moon check` 内运行，护正确性
// ---------------------------------------------------------------------------

///|
/// 守卫：64 块 CFG 上支配树可达节点非空、最小 SSA 块结构守恒（回归正确性）。
test "guard: dominator tree and minimal SSA on a 64-block CFG" {
  let rng = @pbt.rng_new(0x51ED_C0DE_1234)
  let blocks = make_cfg(rng, 64)
  let dom = @cg.build_dom_tree(blocks, entry="b0")
  assert_true(dom.reachable.length() >= 1)
  assert_true(dom.reachable.length() <= blocks.length())
  let ssa = @cg.build_ssa_minimal(blocks, entry="b0")
  // 最小 SSA 保持块数与块标签（结构守恒）。
  assert_eq(ssa.blocks.length(), blocks.length())
  for i in 0..<blocks.length() {
    assert_eq(ssa.blocks[i].label, blocks[i].label)
  }
}

///|
/// 守卫：128 节点干涉图图着色尊重干涉；k 充足无溢出（回归正确性）。
test "guard: graph coloring respects interference on a 128-node graph" {
  let rng = @pbt.rng_new(0xC0FFEE_99)
  let g = make_interference(rng, 128)
  // k 取节点数（≥ 最大度 + 1）→ 应无溢出。
  let alloc = @cg.allocate_coloring_briggs(g, g.nodes.length())
  for e in g.edges {
    let (a, b) = e
    match (alloc.get(a), alloc.get(b)) {
      (Some(@cg.Location::Reg(x)), Some(@cg.Location::Reg(y))) =>
        assert_true(x != y)
      _ => ()
    }
  }
}

// ---------------------------------------------------------------------------
// native 基准工作负载（`moon bench`）
// ---------------------------------------------------------------------------

///|
/// 基准：大规模 CFG 支配树构造。
test "bench: dominator tree construction on large CFG" (b : @bench.T) {
  let rng = @pbt.rng_new(0xD0_1234)
  let blocks = make_cfg(rng, 256)
  b.bench(name="codegen_dom_tree_256_blocks", fn() {
    b.keep(@cg.build_dom_tree(blocks, entry="b0"))
  })
}

///|
/// 基准：大规模 CFG 最小 SSA 构造。
test "bench: minimal SSA construction on large CFG" (b : @bench.T) {
  let rng = @pbt.rng_new(0x55A_1234)
  let blocks = make_cfg(rng, 256)
  b.bench(name="codegen_ssa_min_256_blocks", fn() {
    b.keep(@cg.build_ssa_minimal(blocks, entry="b0"))
  })
}

///|
/// 基准：大规模干涉图 Chaitin-Briggs 图着色分配。
test "bench: graph coloring allocation on large interference graph" (
  b : @bench.T
) {
  let rng = @pbt.rng_new(0xC010_1234)
  let g = make_interference(rng, 256)
  b.bench(name="codegen_coloring_256_nodes", fn() {
    b.keep(@cg.allocate_coloring_briggs(g, 16))
  })
}

///|
/// 基准：大规模活跃区间线性扫描分配。
test "bench: linear scan allocation on large interval set" (b : @bench.T) {
  let rng = @pbt.rng_new(0x1115_1234)
  let intervals = make_intervals(rng, 512)
  b.bench(name="codegen_linear_scan_512_intervals", fn() {
    b.keep(@cg.allocate_linear_scan(intervals, 16))
  })
}

///|
/// 基准：大规模 SSA 程序 SCCP。
test "bench: SCCP on large SSA program" (b : @bench.T) {
  let rng = @pbt.rng_new(0x5CC9_1234)
  let blocks = make_cfg(rng, 256)
  let ssa = @cg.build_ssa_minimal(blocks, entry="b0")
  b.bench(name="codegen_sccp_256_blocks", fn() { b.keep(@cg.sccp(ssa)) })
}
