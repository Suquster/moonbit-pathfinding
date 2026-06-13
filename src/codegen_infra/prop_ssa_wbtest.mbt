// prop_ssa_wbtest.mbt —— Property 8：SSA 单赋值不变量（建立与保持）属性测试。
//
// Feature: moonbit-infra-suite, Property 8: SSA 单赋值不变量（建立与保持）
// **Validates: Requirements 3.5, 3.6**
//
// 性质陈述（design.md §「Property 8」）：对任意由基本块序列构造的 SSA 程序，
// 每个变量恰有唯一一次静态定义（建立）；且在按声明顺序执行任意已注册优化
// pass 序列后，该单赋值不变量在每个 pass 之后仍然成立（保持）。
//
// 校验手段：收集 `build_ssa` / `run_passes` 产出程序的「全部定义版本号」
// （块内定义左值版本号 + φ 目标版本号，见同包白盒辅助 `ssa_definition_ids`），
// 当且仅当这些版本号两两互不相同时单赋值不变量成立（见同包白盒辅助
// `all_distinct`，其判定逻辑与 `@proofs.ssa_single_assignment` 谓词一致）。
//
// 本文件为白盒测试（`*_wbtest.mbt`），因 `ssa_definition_ids` 依赖包内私有的
// `tokenize` / `version_id`，需与被测包同处一个白盒测试编译单元。生成器复用
// 共享 PBT 包 @infra_pbt 的 `Rng` / `Gen` / `holds_for_all`（≥100 次迭代）。

// ---------------------------------------------------------------------------
// 随机程序生成器（generators）
// ---------------------------------------------------------------------------

///|
/// 变量名池：限制在小集合内以提高「同名变量跨块多次定义」（从而触发 φ 插入）
/// 的概率，更充分地考验单赋值不变量的建立。
let ssa_var_pool : Array[String] = ["a", "b", "c", "x", "y"]

///|
/// 二元运算符池（与 `pass_const_fold` 可折叠的运算符保持一致）。
let ssa_op_pool : Array[String] = ["+", "-", "*"]

///|
/// 可注册的优化 pass 池（用于生成任意 pass 序列以考验「保持」）。
let ssa_pass_pool : Array[Pass] = [ConstFold, DeadCodeElim, CopyProp]

///|
/// 从变量名池中随机取一个变量名。
fn gen_var_name(rng : @infra_pbt.Rng) -> String {
  ssa_var_pool[rng.next_below(ssa_var_pool.length())]
}

///|
/// 随机生成一条「定义」指令：`name = <const>` 或 `name = lhs op rhs`。
/// 两者经 `tokenize` 后第二个记号均为 `"="`，故都被 `build_ssa` 视为定义。
fn gen_def_instr(rng : @infra_pbt.Rng) -> String {
  let lhs = gen_var_name(rng)
  if rng.next_bool() {
    // 常量定义（可被 ConstFold 直接命中）。
    lhs + " = " + rng.next_range(0, 9).to_string()
  } else {
    // 二元运算定义；右值可能为常量或变量名（变量未定义时按字面记号保留）。
    let op = ssa_op_pool[rng.next_below(ssa_op_pool.length())]
    lhs + " = " + gen_var_name(rng) + " " + op + " " + gen_var_name(rng)
  }
}

///|
/// 生成 `count` 条定义指令。
fn gen_def_instrs(rng : @infra_pbt.Rng, count : Int) -> Array[String] {
  let instrs : Array[String] = []
  let mut i = 0
  while i < count {
    instrs.push(gen_def_instr(rng))
    i += 1
  }
  instrs
}

///|
/// 随机生成一个基本块序列，覆盖三类控制流形态：
///   * 直线代码（straight-line）：单块顺序定义；
///   * 菱形（diamond）：entry → then/else → join，汇合块有 2 个前驱；
///   * 三路汇合（merge）：entry → b1/b2/b3 → join，汇合块有 3 个前驱。
/// 后两类在汇合块触发 φ 插入，考验 SSA 单赋值不变量的建立。
fn gen_blocks(rng : @infra_pbt.Rng) -> Array[BasicBlock] {
  let shape = rng.next_below(3)
  if shape == 0 {
    // 直线代码：1..5 条定义 + 一条 ret 使用。
    let instrs = gen_def_instrs(rng, rng.next_range(1, 5))
    instrs.push("ret " + gen_var_name(rng))
    [BasicBlock::{ label: "b0", instrs, succs: [] }]
  } else if shape == 1 {
    // 菱形汇合（2 个前驱）。
    [
      BasicBlock::{ label: "entry", instrs: [], succs: ["then", "else"] },
      BasicBlock::{
        label: "then",
        instrs: gen_def_instrs(rng, rng.next_range(1, 3)),
        succs: ["join"],
      },
      BasicBlock::{
        label: "else",
        instrs: gen_def_instrs(rng, rng.next_range(1, 3)),
        succs: ["join"],
      },
      BasicBlock::{
        label: "join",
        instrs: ["ret " + gen_var_name(rng)],
        succs: [],
      },
    ]
  } else {
    // 三路汇合（3 个前驱）。
    [
      BasicBlock::{ label: "entry", instrs: [], succs: ["b1", "b2", "b3"] },
      BasicBlock::{
        label: "b1",
        instrs: gen_def_instrs(rng, rng.next_range(1, 2)),
        succs: ["join"],
      },
      BasicBlock::{
        label: "b2",
        instrs: gen_def_instrs(rng, rng.next_range(1, 2)),
        succs: ["join"],
      },
      BasicBlock::{
        label: "b3",
        instrs: gen_def_instrs(rng, rng.next_range(1, 2)),
        succs: ["join"],
      },
      BasicBlock::{
        label: "join",
        instrs: ["ret " + gen_var_name(rng)],
        succs: [],
      },
    ]
  }
}

///|
/// 随机生成一个长度为 0..3 的 pass 序列（可重复、任意顺序），用于考验
/// 「按声明顺序执行任意已注册 pass 序列后仍保持单赋值不变量」。
fn gen_passes(rng : @infra_pbt.Rng) -> Array[Pass] {
  let len = rng.next_below(4)
  let out : Array[Pass] = []
  let mut i = 0
  while i < len {
    out.push(ssa_pass_pool[rng.next_below(ssa_pass_pool.length())])
    i += 1
  }
  out
}

///|
/// 生成器：随机「基本块序列 + pass 序列」场景。
fn gen_ssa_scenario() -> @infra_pbt.Gen[(Array[BasicBlock], Array[Pass])] {
  @infra_pbt.Gen::new(fn(rng) { (gen_blocks(rng), gen_passes(rng)) })
}

// ---------------------------------------------------------------------------
// Property 8：SSA 单赋值不变量（建立与保持）
// ---------------------------------------------------------------------------

///|
/// **Property 8：SSA 单赋值不变量（建立与保持）**
/// **Validates: Requirements 3.5, 3.6**
///
/// 对任意随机基本块序列构造的 SSA 程序，校验：
///   1) 建立（Requirement 3.5）：`build_ssa` 产出程序的全部定义版本号两两互
///      不相同——每个变量恰有唯一一次静态定义；
///   2) 保持（Requirement 3.6）：对其执行任意已注册 pass 序列后，定义版本号
///      仍两两互不相同——单赋值不变量在每个 pass 之后均保持成立。
/// 复用 @infra_pbt.holds_for_all（200 次迭代，满足 ≥100 基线）。
test "Property 8: build_ssa 建立且 run_passes 保持 SSA 单赋值不变量" {
  let g = gen_ssa_scenario()
  let ok = @infra_pbt.holds_for_all(
    g,
    fn(scenario) {
      let (blocks, passes) = scenario
      let ssa = build_ssa(blocks)
      // 建立：构造即满足单赋值（定义版本号两两不同）。
      let built_ok = all_distinct(ssa_definition_ids(ssa))
      // 保持：任意 pass 序列执行后仍满足单赋值。
      let after = run_passes(ssa, passes)
      let preserved_ok = all_distinct(ssa_definition_ids(after))
      built_ok && preserved_ok
    },
    iters=200,
  )
  assert_true(ok)
}
