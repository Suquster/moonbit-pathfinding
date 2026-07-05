// opt_reduction_bench.mbt —— 优化流水线指令削减率的量化证据与门禁（任务 T3）。
//
// 目标：在**含真实冗余形态**的代表性程序族上，量化旗舰优化流水线
// `run_to_fixpoint([Sccp, Gvn, CopyProp, DeadCodeElim, ConstFold])` 的指令
// 削减率，并以 **≥30%** 为门禁断言（`moon test` 三后端常跑）。
//
// 冗余形态（与工业编译器的经典优化机会一一对应）：
//   * 常量链（SCCP / 常量折叠）：`c1 = 5; c2 = c1 + 3; …`
//   * 公共子表达式（GVN）：同支配路径上重复的 `a + b`
//   * 复制链（CopyProp）：`e1 = d; e2 = e1; …`
//   * 死代码（DCE）：从 `ret` 反向不可达的定义
//
// 语义护栏：优化前后以共享参考解释器 `@cg.evaluate`（同输入环境、同执行
// 路径）对拍可达输出序列，逐位一致才计入削减统计。程序族由确定性 LCG
// 生成，三后端逐元素可复现。

///|
/// 削减率门禁（百分比）。
let opt_reduction_gate_pct : Double = 30.0

///|
/// 程序族规模（每个规模档位一个程序）。
let opt_reduction_cases : Int = 12

///|
/// 自包含 LCG（与既有 `*_bench` 一致，三后端可复现）。
priv struct OptLcg {
  mut state : Int
}

///|
fn OptLcg::new(seed : Int) -> OptLcg {
  let s = if seed <= 0 { (-seed).lor(1) } else { seed }
  { state: s.land(0x7fffffff) }
}

///|
fn OptLcg::next(self : OptLcg) -> Int {
  let v = (self.state * 1103515245 + 12345).land(0x7fffffff)
  self.state = v
  v
}

///|
/// 生成一个含四类冗余形态的菱形 CFG 程序（entry → then/else → join）。
///
/// 变量约定：`p` 为分支谓词输入，`a`/`b` 为算术输入（均经 `init` 环境
/// 提供）；`ret` 的实参依赖各类活跃计算，保证优化不能整段删空。
fn make_redundant_program(rng : OptLcg, scale : Int) -> Array[@cg.BasicBlock] {
  let entry_instrs : Array[String] = []
  // ① 常量链：c0 = k; c_{i} = c_{i-1} + k_i —— SCCP 可全部折叠成常量。
  entry_instrs.push("c0 = \{1 + rng.next() % 9}")
  for i in 1..<(scale + 2) {
    entry_instrs.push("c\{i} = c\{i - 1} + \{1 + rng.next() % 9}")
  }
  // ② 公共子表达式：同一 `a + b` 重复定义 —— GVN 合并为单一值。
  entry_instrs.push("g0 = a + b")
  for i in 1..<(scale + 2) {
    entry_instrs.push("g\{i} = a + b")
  }
  // ③ 复制链：e0 = g0; e_i = e_{i-1} —— CopyProp 全部内联。
  entry_instrs.push("e0 = g0")
  for i in 1..<(scale + 2) {
    entry_instrs.push("e\{i} = e\{i - 1}")
  }
  // ④ 死代码：从 ret 反向不可达 —— DCE 删除。
  for i in 0..<(scale + 2) {
    entry_instrs.push("z\{i} = a * \{2 + rng.next() % 7}")
  }
  entry_instrs.push("cbr p then else")
  let last_c = "c\{scale + 1}"
  let last_e = "e\{scale + 1}"
  [
    { label: "entry", instrs: entry_instrs, succs: ["then", "else"] },
    {
      label: "then",
      instrs: ["x = \{last_c} + \{last_e}", "br join"],
      succs: ["join"],
    },
    {
      label: "else",
      instrs: ["x = \{last_c} - \{last_e}", "br join"],
      succs: ["join"],
    },
    { label: "join", instrs: ["y = x * 2", "ret y"], succs: [] },
  ]
}

///|
/// 统计 SSA 程序的指令总数（块内指令 + φ 函数）。
fn count_instrs(p : @cg.SsaProgram) -> Int {
  let mut n = p.phis.length()
  for b in p.blocks {
    n = n + b.instrs.length()
  }
  n
}

///|
/// 对单个程序执行「优化 + 语义对拍 + 削减统计」。
/// 返回 `(优化前指令数, 优化后指令数, 语义一致)`。
fn measure_reduction(
  blocks : Array[@cg.BasicBlock],
  env : Map[String, Int],
) -> (Int, Int, Bool) {
  let ssa = @cg.build_ssa(blocks)
  let before = count_instrs(ssa)
  let opt = @cg.run_to_fixpoint(ssa, [
    @cg.OptPass::Sccp,
    @cg.OptPass::Gvn,
    @cg.OptPass::CopyProp,
    @cg.OptPass::DeadCodeElim,
    @cg.OptPass::ConstFold,
  ])
  let after = count_instrs(opt)
  // 语义对拍：两条可达路径（then / else）上可达输出序列逐位一致。
  let mut ok = true
  for path in [["entry", "then", "join"], ["entry", "else", "join"]] {
    let base = @cg.evaluate(ssa, env, path)
    let got = @cg.evaluate(opt, env, path)
    if got.output != base.output {
      ok = false
    }
  }
  (before, after, ok)
}

///|
/// 运行整个程序族并汇总：返回（Markdown 证据, 总削减率 %, 全语义一致）。
fn run_reduction_suite() -> (String, Double, Bool) {
  let rng = OptLcg::new(20240607)
  let lines : Array[String] = []
  lines.push(
    "# 优化流水线指令削减率（Sccp→Gvn→CopyProp→Dce→ConstFold 不动点）",
  )
  lines.push("")
  lines.push("| case | scale | before | after | reduction |")
  lines.push("| --- | --- | --- | --- | --- |")
  let mut total_before = 0
  let mut total_after = 0
  let mut all_ok = true
  for i in 0..<opt_reduction_cases {
    let scale = 2 + i * 2
    let blocks = make_redundant_program(rng, scale)
    let env : Map[String, Int] = Map([])
    env["p"] = rng.next() % 2
    env["a"] = 1 + rng.next() % 97
    env["b"] = 1 + rng.next() % 97
    let (before, after, ok) = measure_reduction(blocks, env)
    if !ok {
      all_ok = false
    }
    total_before = total_before + before
    total_after = total_after + after
    let pct = (before - after).to_double() * 100.0 / before.to_double()
    lines.push("| \{i} | \{scale} | \{before} | \{after} | \{pct}% |")
  }
  let total_pct = (total_before - total_after).to_double() *
    100.0 /
    total_before.to_double()
  lines.push("")
  lines.push("- 总指令数: before=\{total_before} after=\{total_after}")
  lines.push(
    "- 总削减率: \{total_pct}%（门禁 ≥\{opt_reduction_gate_pct}%）",
  )
  lines.push(
    "- 优化前后语义对拍（then/else 双路径）全一致: \{all_ok}",
  )
  let tb = StringBuilder::new()
  for l in lines {
    tb.write_string(l)
    tb.write_string("\n")
  }
  (tb.to_string(), total_pct, all_ok)
}

///|
test "guard: 优化流水线指令削减率 ≥30% 且语义保持" {
  let (evidence, pct, ok) = run_reduction_suite()
  assert_true(evidence.contains("总削减率"))
  assert_true(ok)
  assert_true(pct >= opt_reduction_gate_pct)
}

///|
test "bench: emit optimization reduction evidence" (b : @bench.T) {
  let (evidence, pct, ok) = run_reduction_suite()
  println("===OPT_REDUCTION_EVIDENCE_BEGIN===")
  println(evidence)
  println("===OPT_REDUCTION_EVIDENCE_END===")
  b.bench(name="opt_reduction_emitted", fn() {
    b.keep(evidence.length() + pct.to_int() + (if ok { 1 } else { 0 }))
  })
}
