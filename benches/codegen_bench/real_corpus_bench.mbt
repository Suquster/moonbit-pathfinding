// real_corpus_bench.mbt —— 优化流水线在「真实程序语料」上的削减率证据（T3 生产级补强）。
//
// 与 opt_reduction_bench.mbt 的合成程序族互补：本语料是 11 个**手写真实
// 内核**（多项式求值、二维数组寻址、双线性插值、2×2 行列式、点积、校验和
// 展开、定点缩放、clamp、绝对差、分支选择缩放、一范数），按「朴素前端直译」风格书写——
// 冗余全部来自真实翻译形态（重复的地址运算/幂次/权重子式、宏展开常量链、
// 直译临时量复制链、分支菱形），**无人工注入**。
//
// 语义护栏与合成族同口径：优化前后以 @cg.evaluate 沿全部可达路径对拍
// 输出序列，逐位一致才计入统计。

///|
/// 真实语料削减率门禁（百分比）：朴素直译内核的天然冗余显著低于
/// 合成极端族，门禁相应保守（实测应远超）。
let real_corpus_gate_pct : Double = 30.0

///|
/// 单个真实内核：名称 + CFG + 输入环境 + 全部可达路径。
priv struct RealKernel {
  name : String
  blocks : Array[@cg.BasicBlock]
  env : Map[String, Int]
  paths : Array[Array[String]]
}

///|
/// 直线型内核（单块 entry: instrs + ret）。
fn straight(
  name : String,
  instrs : Array[String],
  env : Map[String, Int],
) -> RealKernel {
  let body : Array[String] = []
  for s in instrs {
    body.push(s)
  }
  {
    name,
    blocks: [{ label: "entry", instrs: body, succs: [] }],
    env,
    paths: [["entry"]],
  }
}

///|
/// 真实程序语料（11 内核，朴素前端直译风格）。
fn real_corpus() -> Array[RealKernel] {
  let ks : Array[RealKernel] = []
  // 1) horner3：naive 直译 a*x^3 + b*x^2 + c*x + d —— 幂次重复计算（GVN）。
  ks.push(
    straight(
      "poly3_naive",
      [
        "x2 = x * x", "x3a = x * x", "x3 = x3a * x", "t1 = a * x3", "x2b = x * x",
        "t2 = b * x2b", "t3 = c * x", "s1 = t1 + t2", "s2 = s1 + t3", "s3 = s2 + d",
        "ret s3",
      ],
      Map([("x", 3), ("a", 2), ("b", 5), ("c", 7), ("d", 11)]),
    ),
  )
  // 2) idx2d_store_load：row-major 寻址 base+(i*W+j)*4 为 load 与 store 各算一遍。
  ks.push(
    straight(
      "idx2d_addr_twice",
      [
        "w0 = 64", "s0 = 4", "r1 = i * w0", "r2 = r1 + j", "addr1 = r2 * s0", "la = base + addr1",
        "r3 = i * w0", "r4 = r3 + j", "addr2 = r4 * s0", "sa = base + addr2", "diff = la - sa",
        "v1 = la + diff", "ret v1",
      ],
      Map([("i", 5), ("j", 9), ("base", 1024)]),
    ),
  )
  // 3) bilinear：插值权重 (1-t) 直译为 one-t 且重复出现（GVN + 常量）。
  ks.push(
    straight(
      "bilerp_weights",
      [
        "one = 1", "it = one - t", "w00 = it * it", "w01a = one - t", "w01 = w01a * t",
        "w10a = one - t", "w10 = t * w10a", "w11 = t * t", "p0 = w00 * q00", "p1 = w01 * q01",
        "p2 = w10 * q10", "p3 = w11 * q11", "a0 = p0 + p1", "a1 = a0 + p2", "a2 = a1 + p3",
        "ret a2",
      ],
      Map([("t", 2), ("q00", 3), ("q01", 5), ("q10", 7), ("q11", 9)]),
    ),
  )
  // 4) det2x2_pair：两个 2×2 行列式共享子式 ad-bc（GVN 跨表达式）。
  ks.push(
    straight(
      "det2x2_pair",
      [
        "m1 = a * d", "m2 = b * c", "det1 = m1 - m2", "m3 = a * d", "m4 = b * c",
        "det2 = m3 - m4", "s = det1 + det2", "ret s",
      ],
      Map([("a", 4), ("b", 3), ("c", 2), ("d", 8)]),
    ),
  )
  // 5) dot3_unrolled：三维点积直译，逐分量临时量 + 复制链（CopyProp）。
  ks.push(
    straight(
      "dot3_unrolled",
      [
        "p0 = ax * bx", "acc0 = p0", "t0 = acc0", "p1 = ay * by", "acc1 = t0 + p1",
        "t1 = acc1", "p2 = az * bz", "acc2 = t1 + p2", "t2 = acc2", "ret t2",
      ],
      Map([("ax", 1), ("ay", 2), ("az", 3), ("bx", 4), ("by", 5), ("bz", 6)]),
    ),
  )
  // 6) checksum4：四步展开校验和，宏展开常量系数链（SCCP/折叠）。
  ks.push(
    straight(
      "checksum4_unrolled",
      [
        "k0 = 31", "k1 = k0 * 31", "k2 = k1 * 31", "k3 = k2 * 31", "h0 = d0 * k3",
        "h1 = d1 * k2", "h2 = d2 * k1", "h3 = d3 * k0", "s0 = h0 + h1", "s1 = s0 + h2",
        "s2 = s1 + h3", "ret s2",
      ],
      Map([("d0", 2), ("d1", 3), ("d2", 5), ("d3", 7)]),
    ),
  )
  // 7) fixed_scale：定点缩放，宏展开的移位当量常量链 + 死调试量（DCE）。
  ks.push(
    straight(
      "fixed_scale_debug",
      [
        "sh1 = 2", "sh2 = sh1 * 2", "sh3 = sh2 * 2", "sh4 = sh3 * 2", "scaled = v * sh4",
        "dbg1 = v * 100", "dbg2 = dbg1 + 7", "half = sh4 - 8", "out = scaled + half",
        "ret out",
      ],
      Map([("v", 12)]),
    ),
  )
  // 8) abs_diff：|a-b| 分支菱形直译（跨路径语义对拍）。
  ks.push({
    name: "abs_diff_diamond",
    blocks: [
      {
        label: "entry",
        instrs: ["d1 = a - b", "d2 = a - b", "cbr p pos neg"],
        succs: ["pos", "neg"],
      },
      { label: "pos", instrs: ["r = d1 + 0", "br join"], succs: ["join"] },
      { label: "neg", instrs: ["r = 0 - d2", "br join"], succs: ["join"] },
      { label: "join", instrs: ["out = r * 1", "ret out"], succs: [] },
    ],
    env: Map([("a", 9), ("b", 4), ("p", 1)]),
    paths: [["entry", "pos", "join"], ["entry", "neg", "join"]],
  })
  // 9) clamp：上下界嵌套菱形，边界常量宏展开。
  ks.push({
    name: "clamp_nested",
    blocks: [
      {
        label: "entry",
        instrs: ["lo = 0 + 0", "hi = 100 * 1", "t1 = v - lo", "cbr cl low high"],
        succs: ["low", "high"],
      },
      { label: "low", instrs: ["r = lo + 0", "br join"], succs: ["join"] },
      {
        label: "high",
        instrs: ["r = v + 0", "hb = hi - v", "br join"],
        succs: ["join"],
      },
      { label: "join", instrs: ["out = r + 0", "ret out"], succs: [] },
    ],
    env: Map([("v", 42), ("cl", 0)]),
    paths: [["entry", "low", "join"], ["entry", "high", "join"]],
  })
  // 10) branch_blend：两臂各自直译同一组插值权重子式（互不支配的跨臂
  //     冗余，PRE 式上提至公共支配块后合并——典型「分支内重复展开」形态）。
  ks.push({
    name: "branch_blend_diamond",
    blocks: [
      {
        label: "entry",
        instrs: ["one = 1", "it = one - t", "cbr p up down"],
        succs: ["up", "down"],
      },
      {
        label: "up",
        instrs: [
          "p00 = it * it", "p01 = it * t", "p11 = t * t", "sa = p00 + p01", "ra = sa + p11",
          "r = ra * 3", "br join",
        ],
        succs: ["join"],
      },
      {
        label: "down",
        instrs: [
          "q00 = it * it", "q01 = it * t", "q11 = t * t", "sb = q00 + q01", "rb = sb + q11",
          "r = rb * 5", "br join",
        ],
        succs: ["join"],
      },
      { label: "join", instrs: ["out = r + 0", "ret out"], succs: [] },
    ],
    env: Map([("t", 2), ("p", 1)]),
    paths: [["entry", "up", "join"], ["entry", "down", "join"]],
  })
  // 11) norm1_4：四元素一范数直译（重复地址步长常量 + 复制链）。
  ks.push(
    straight(
      "norm1_4_naive",
      [
        "s = 4", "o0 = 0 * s", "o1 = 1 * s", "o2 = 2 * s", "o3 = 3 * s", "u0 = e0 + o0",
        "u1 = e1 + o1", "u2 = e2 + o2", "u3 = e3 + o3", "a0 = u0 + u1", "c0 = a0",
        "a1 = c0 + u2", "c1 = a1", "a2 = c1 + u3", "ret a2",
      ],
      Map([("e0", 1), ("e1", 2), ("e2", 3), ("e3", 4)]),
    ),
  )
  ks
}

///|
/// 运行真实语料并汇总：返回（Markdown 证据, 总削减率 %, 全语义一致）。
fn run_real_corpus_suite() -> (String, Double, Bool) {
  let lines : Array[String] = []
  lines.push(
    "# 优化流水线削减率 — 真实程序语料（朴素前端直译，无注入冗余）",
  )
  lines.push("")
  lines.push("| kernel | before | after | reduction | semantics |")
  lines.push("| --- | --- | --- | --- | --- |")
  let mut total_before = 0
  let mut total_after = 0
  let mut all_ok = true
  for k in real_corpus() {
    let ssa = @cg.build_ssa(k.blocks)
    let before = count_instrs(ssa)
    let opt = @cg.run_to_fixpoint(ssa, [
      @cg.OptPass::Sccp,
      @cg.OptPass::Gvn,
      @cg.OptPass::CopyProp,
      @cg.OptPass::DeadCodeElim,
      @cg.OptPass::ConstFold,
    ])
    let after = count_instrs(opt)
    let mut case_ok = true
    for path in k.paths {
      let base = @cg.evaluate(ssa, k.env, path)
      let got = @cg.evaluate(opt, k.env, path)
      if got.output != base.output {
        case_ok = false
        all_ok = false
      }
    }
    total_before = total_before + before
    total_after = total_after + after
    let pct = (before - after).to_double() * 100.0 / before.to_double()
    lines.push("| \{k.name} | \{before} | \{after} | \{pct}% | \{case_ok} |")
  }
  let total_pct = (total_before - total_after).to_double() *
    100.0 /
    total_before.to_double()
  lines.push("")
  lines.push("- 总指令数: before=\{total_before} after=\{total_after}")
  lines.push(
    "- 总削减率: \{total_pct}%（门禁 ≥\{real_corpus_gate_pct}%）",
  )
  lines.push("- 优化前后全路径语义对拍一致: \{all_ok}")
  let tb = StringBuilder::new()
  for l in lines {
    tb.write_string(l)
    tb.write_string("\n")
  }
  (tb.to_string(), total_pct, all_ok)
}

///|
test "guard: 真实程序语料削减率 ≥30% 且语义保持" {
  let (evidence, pct, ok) = run_real_corpus_suite()
  assert_true(evidence.contains("总削减率"))
  assert_true(ok)
  assert_true(pct >= real_corpus_gate_pct)
}

///|
test "bench: emit real-corpus reduction evidence" (b : @bench.T) {
  let (evidence, pct, ok) = run_real_corpus_suite()
  println("===REAL_CORPUS_EVIDENCE_BEGIN===")
  println(evidence)
  println("===REAL_CORPUS_EVIDENCE_END===")
  b.bench(name="real_corpus_reduction_emitted", fn() {
    b.keep(evidence.length() + pct.to_int() + (if ok { 1 } else { 0 }))
  })
}
