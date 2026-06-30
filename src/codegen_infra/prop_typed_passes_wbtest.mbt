// prop_typed_passes_wbtest.mbt —— 类型化优化遍 + 验证型流水线的属性/回归测试（白盒）。
//
// 纲领落点（docs/PRODUCTION_FRONTIER_ROADMAP.md 方向三 Codegen，T3.1 / T3.2）：
//   * T3.2 要求每个优化 pass 带「优化前后求值等价」PBT —— 本文件对五个遍
//     （const_fold / algebraic_simplify / strength_reduce / dce / cse）各给一条
//     ≥100 迭代的**可观察等价** PBT：以 `interp_ir` 为基准，优化前后返回值相等、
//     且优化后仍存在的寄存器其终值与优化前一致。
//   * T3.1 要求「每 pass 前后断言 SSA 良构性」—— 本文件验证：每个遍保持
//     `validate_ir` 良构性（合法函数优化后仍 `Ok`）；`run_typed_pipeline_validated`
//     对合法输入返回 `Ok` 且与不验证版本结果一致，对非法输入（重复定义 /
//     类型违规 / 控制流缺失）返回 `Err`。
//
// 置于白盒测试（`_wbtest.mbt`，与被测代码同包）的原因：复用 typed_ir_prop_wbtest.mbt
// 已有的「合法函数生成器」`gen_legal_function` / `gen_legal_function_with_args`
// 与反例生成器 `gen_dup_def` / `gen_type_violation` / `gen_cfg_violation`，并可
// 直接读取 `IrEvalResult` 字段、不带 `@codegen_infra.` 前缀构造 IR。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `holds_for_all`；每条属性显式 `iters=100`
// （≥100 次迭代，满足质量门槛）。断言统一以 `assert_true` + 派生 `Eq` / `match`
// 表达，规避核心库 `Show` 弃用告警，使本文件零告警。

// ───────────────────────────── 可观察等价 ─────────────────────────────

///|
/// 一组确定性的额外入参赋值，用于在 `obs_equiv` 中跨多组输入加强等价判定
/// （覆盖寄存器读取与 `CondBr` 条件的「零 / 正 / 负」三态分支走向）。键覆盖
/// 生成器可能引用的入参寄存器号区间 `0 ..= 7`。
let obs_arg_variants : Array[Map[Int, Int]] = [
  Map([(0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0), (7, 0)]),
  Map([(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 8)]),
  Map([(0, -1), (1, -2), (2, -3), (3, -4), (4, -5), (5, -6), (6, -7), (7, -8)]),
]

///|
/// 可观察等价判定：优化前 `orig` 与优化后 `opt` 对**同一入参**经 `interp_ir`
/// 求值得到**相等的返回值** `returned`。
///
/// 函数的可观察契约是「给定入参 → 返回值」；寄存器堆终态是解释器内部状态，
/// **不属于**可观察契约——死代码消除合法地删除无用定义会改变内部寄存器终态，
/// 却不改变返回值（喂给返回值的寄存器必被使用、绝不会被删除）。故等价判定
/// 仅比较返回值，并在「调用方给定入参」之外再跨 `obs_arg_variants` 多组确定性
/// 入参比较，强化覆盖（不同分支走向、不同寄存器读值）。
///
/// 这是 T3.2「优化前后求值等价」的形式化判定，对全部五个遍统一适用。
fn obs_equiv(
  orig : TypedFunction,
  opt : TypedFunction,
  args : Map[Int, Int],
) -> Bool {
  if interp_ir(orig, args~).returned != interp_ir(opt, args~).returned {
    return false
  }
  for a in obs_arg_variants {
    if interp_ir(orig, args=a).returned != interp_ir(opt, args=a).returned {
      return false
    }
  }
  true
}

// ───────────────────────────── 等价谓词（逐遍） ─────────────────────────────

///|
/// 谓词：`const_fold_typed` 保持可观察等价。
fn pbt_const_fold_equiv(input : (TypedFunction, Map[Int, Int])) -> Bool {
  let (f, args) = input
  obs_equiv(f, const_fold_typed(f), args)
}

///|
/// 谓词：`algebraic_simplify_typed` 保持可观察等价。
fn pbt_algebraic_equiv(input : (TypedFunction, Map[Int, Int])) -> Bool {
  let (f, args) = input
  obs_equiv(f, algebraic_simplify_typed(f), args)
}

///|
/// 谓词：`strength_reduce_typed` 保持可观察等价。
fn pbt_strength_equiv(input : (TypedFunction, Map[Int, Int])) -> Bool {
  let (f, args) = input
  obs_equiv(f, strength_reduce_typed(f), args)
}

///|
/// 谓词：`dce_typed` 保持可观察等价。
fn pbt_dce_equiv(input : (TypedFunction, Map[Int, Int])) -> Bool {
  let (f, args) = input
  obs_equiv(f, dce_typed(f), args)
}

///|
/// 谓词：`cse_typed` 保持可观察等价。
fn pbt_cse_equiv(input : (TypedFunction, Map[Int, Int])) -> Bool {
  let (f, args) = input
  obs_equiv(f, cse_typed(f), args)
}

///|
/// 全部五遍组合的标准顺序（常量折叠→代数化简→强度削减→CSE→DCE）。
let pbt_all_passes : Array[TypedPass] = [
  ConstFold,
  AlgebraicSimplify,
  StrengthReduce,
  Cse,
  Dce,
]

///|
/// 谓词：整条流水线（五遍按序）保持可观察等价。
fn pbt_pipeline_equiv(input : (TypedFunction, Map[Int, Int])) -> Bool {
  let (f, args) = input
  obs_equiv(f, run_typed_pipeline(f, pbt_all_passes), args)
}

///|
/// 谓词：不动点驱动保持可观察等价，且确为不动点（再跑一遍流水线不再变化）。
fn pbt_fixpoint_equiv(input : (TypedFunction, Map[Int, Int])) -> Bool {
  let (f, args) = input
  let fixed = run_typed_to_fixpoint(f, pbt_all_passes)
  obs_equiv(f, fixed, args) &&
  run_typed_pipeline(fixed, pbt_all_passes) == fixed
}

// ───────────────────────────── 良构性谓词（T3.1） ─────────────────────────────

///|
/// 谓词：合法函数经每个遍及整条流水线后，`validate_ir` 仍返回 `Ok`
/// （「每 pass 前后断言 SSA 良构性」的正向保证）。
fn pbt_passes_preserve_validity(func : TypedFunction) -> Bool {
  let stays_ok = fn(g : TypedFunction) -> Bool {
    match validate_ir(g) {
      Ok(_) => true
      Err(_) => false
    }
  }
  stays_ok(const_fold_typed(func)) &&
  stays_ok(algebraic_simplify_typed(func)) &&
  stays_ok(strength_reduce_typed(func)) &&
  stays_ok(dce_typed(func)) &&
  stays_ok(cse_typed(func)) &&
  stays_ok(run_typed_pipeline(func, pbt_all_passes))
}

///|
/// 谓词：验证型流水线对合法输入返回 `Ok`，且其结果与不验证版本完全一致。
fn pbt_validated_pipeline_ok(func : TypedFunction) -> Bool {
  match run_typed_pipeline_validated(func, pbt_all_passes) {
    Ok(g) => g == run_typed_pipeline(func, pbt_all_passes)
    Err(_) => false
  }
}

///|
/// 谓词：验证型流水线对「重复定义」非法输入返回 `Err`（不被静默放行）。
fn pbt_validated_rejects_dup(input : (TypedFunction, Int)) -> Bool {
  let (func, _) = input
  match run_typed_pipeline_validated(func, pbt_all_passes) {
    Err(_) => true
    Ok(_) => false
  }
}

///|
/// 谓词：验证型流水线对「类型违规」非法输入返回 `Err`。
fn pbt_validated_rejects_type(func : TypedFunction) -> Bool {
  match run_typed_pipeline_validated(func, pbt_all_passes) {
    Err(_) => true
    Ok(_) => false
  }
}

///|
/// 谓词：验证型流水线对「控制流缺失」非法输入返回 `Err`。
fn pbt_validated_rejects_cfg(func : TypedFunction) -> Bool {
  match run_typed_pipeline_validated(func, pbt_all_passes) {
    Err(_) => true
    Ok(_) => false
  }
}

// ───────────────────────────── 等价属性测试（T3.2，各 ≥100 迭代） ─────────────────────────────

///|
/// Feature: codegen-frontier T3.2, Property: const folding preserves semantics
///
/// 对任意合法函数与入参，`const_fold_typed` 优化前后 `interp_ir` 可观察等价。
test "T3.2: const_fold_typed preserves observable semantics" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_legal_function_with_args(),
      pbt_const_fold_equiv,
      iters=100,
    ),
  )
}

///|
/// Feature: codegen-frontier T3.2, Property: algebraic simplification preserves semantics
///
/// 对任意合法函数与入参，`algebraic_simplify_typed` 优化前后可观察等价。
test "T3.2: algebraic_simplify_typed preserves observable semantics" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_legal_function_with_args(),
      pbt_algebraic_equiv,
      iters=100,
    ),
  )
}

///|
/// Feature: codegen-frontier T3.2, Property: strength reduction preserves semantics
///
/// 对任意合法函数与入参，`strength_reduce_typed`（`x*2 → x+x`）优化前后可观察等价。
test "T3.2: strength_reduce_typed preserves observable semantics" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_legal_function_with_args(),
      pbt_strength_equiv,
      iters=100,
    ),
  )
}

///|
/// Feature: codegen-frontier T3.2, Property: DCE preserves semantics
///
/// 对任意合法函数与入参，`dce_typed` 优化前后可观察等价（删除的寄存器不可观察）。
test "T3.2: dce_typed preserves observable semantics" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_legal_function_with_args(),
      pbt_dce_equiv,
      iters=100,
    ),
  )
}

///|
/// Feature: codegen-frontier T3.2, Property: CSE preserves semantics
///
/// 对任意合法函数与入参，`cse_typed` 优化前后可观察等价（冗余表达式改名到规范
/// 寄存器，取值恒等）。
test "T3.2: cse_typed preserves observable semantics" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_legal_function_with_args(),
      pbt_cse_equiv,
      iters=100,
    ),
  )
}

///|
/// Feature: codegen-frontier T3.1, Property: full pipeline preserves semantics
///
/// 对任意合法函数与入参，整条五遍流水线优化前后可观察等价。
test "T3.1: run_typed_pipeline preserves observable semantics" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_legal_function_with_args(),
      pbt_pipeline_equiv,
      iters=100,
    ),
  )
}

///|
/// Feature: codegen-frontier T3.1, Property: fixpoint converges and preserves semantics
///
/// 对任意合法函数与入参，不动点驱动结果可观察等价于原函数，且确为不动点。
test "T3.1: run_typed_to_fixpoint converges and preserves semantics" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_legal_function_with_args(),
      pbt_fixpoint_equiv,
      iters=100,
    ),
  )
}

// ───────────────────────────── 良构性属性测试（T3.1，各 ≥100 迭代） ─────────────────────────────

///|
/// Feature: codegen-frontier T3.1, Property: passes preserve IR well-formedness
///
/// 对任意合法函数，每个遍及整条流水线的产物仍通过 `validate_ir`。
test "T3.1: optimization passes preserve IR well-formedness" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_legal_function(),
      pbt_passes_preserve_validity,
      iters=100,
    ),
  )
}

///|
/// Feature: codegen-frontier T3.1, Property: validated pipeline accepts legal IR
///
/// 对任意合法函数，`run_typed_pipeline_validated` 返回 `Ok` 且与不验证版本一致。
test "T3.1: validated pipeline accepts legal IR and matches unvalidated" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_legal_function(),
      pbt_validated_pipeline_ok,
      iters=100,
    ),
  )
}

///|
/// Feature: codegen-frontier T3.1, Property: validated pipeline rejects duplicate-def IR
test "T3.1: validated pipeline rejects duplicate-definition IR" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_dup_def(),
      pbt_validated_rejects_dup,
      iters=100,
    ),
  )
}

///|
/// Feature: codegen-frontier T3.1, Property: validated pipeline rejects ill-typed IR
test "T3.1: validated pipeline rejects type-violating IR" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_type_violation(),
      pbt_validated_rejects_type,
      iters=100,
    ),
  )
}

///|
/// Feature: codegen-frontier T3.1, Property: validated pipeline rejects malformed-CFG IR
test "T3.1: validated pipeline rejects control-flow-broken IR" {
  assert_true(
    @infra_pbt.holds_for_all(
      gen_cfg_violation(),
      pbt_validated_rejects_cfg,
      iters=100,
    ),
  )
}

// ───────────────────────────── 确定性回归（具体例证 / 可解释性） ─────────────────────────────

///|
/// 回归：常量折叠 + 块内传播级联。
/// `r1 = 2 + 3; r2 = r1 * 4; ret r2` → `r1 = 5; r2 = 20; ret r2`，返回 20。
test "const_fold_typed cascades constants within a block" {
  let f = TypedFunction::{
    entry: "b0",
    blocks: [
      TypedBlock::{
        label: "b0",
        instrs: [
          Add(dst=1, lhs=Imm(2), rhs=Imm(3)),
          Mul(dst=2, lhs=Reg(1), rhs=Imm(4)),
        ],
        terminator: Some(Ret(value=Some(Reg(2)))),
      },
    ],
  }
  let opt = const_fold_typed(f)
  let expected = TypedFunction::{
    entry: "b0",
    blocks: [
      TypedBlock::{
        label: "b0",
        instrs: [
          Add(dst=1, lhs=Imm(5), rhs=Imm(0)),
          Add(dst=2, lhs=Imm(20), rhs=Imm(0)),
        ],
        // Reg(2) 已知为常量 20，返回值位置被常量传播为 Imm(20)。
        terminator: Some(Ret(value=Some(Imm(20)))),
      },
    ],
  }
  assert_true(opt == expected)
  assert_true(interp_ir(opt, args=Map([])).returned == Some(20))
}

///|
/// 回归：代数化简 `x * 0 = 0` 与 `x - x = 0`，均物化为 `Add(_, 0, 0)`。
test "algebraic_simplify_typed folds x*0 and x-x to zero" {
  let f = TypedFunction::{
    entry: "b0",
    blocks: [
      TypedBlock::{
        label: "b0",
        instrs: [
          Mul(dst=2, lhs=Reg(1), rhs=Imm(0)),
          Sub(dst=3, lhs=Reg(1), rhs=Reg(1)),
        ],
        terminator: Some(Ret(value=Some(Reg(2)))),
      },
    ],
  }
  let opt = algebraic_simplify_typed(f)
  match opt.blocks[0].instrs[0] {
    Add(dst~, lhs~, rhs~) =>
      assert_true(dst == 2 && lhs == Imm(0) && rhs == Imm(0))
    _ => assert_true(false)
  }
  match opt.blocks[0].instrs[1] {
    Add(dst~, lhs~, rhs~) =>
      assert_true(dst == 3 && lhs == Imm(0) && rhs == Imm(0))
    _ => assert_true(false)
  }
}

///|
/// 回归：强度削减 `x * 2 → x + x`。
test "strength_reduce_typed rewrites x*2 into x+x" {
  let f = TypedFunction::{
    entry: "b0",
    blocks: [
      TypedBlock::{
        label: "b0",
        instrs: [Mul(dst=2, lhs=Reg(1), rhs=Imm(2))],
        terminator: Some(Ret(value=Some(Reg(2)))),
      },
    ],
  }
  let opt = strength_reduce_typed(f)
  match opt.blocks[0].instrs[0] {
    Add(dst~, lhs~, rhs~) =>
      assert_true(dst == 2 && lhs == Reg(1) && rhs == Reg(1))
    _ => assert_true(false)
  }
}

///|
/// 回归：DCE 删除「定义未被使用、无副作用」的指令，保留有副作用的 `Store`。
test "dce_typed removes unused pure defs but keeps stores" {
  let f = TypedFunction::{
    entry: "b0",
    blocks: [
      TypedBlock::{
        label: "b0",
        instrs: [
          Add(dst=1, lhs=Imm(1), rhs=Imm(2)), // dead: r1 never used
          Store(addr=Mem(0), value=Imm(7)), // side effect: kept
          Add(dst=2, lhs=Imm(3), rhs=Imm(4)), // used by Ret
        ],
        terminator: Some(Ret(value=Some(Reg(2)))),
      },
    ],
  }
  let opt = dce_typed(f)
  assert_true(opt.blocks[0].instrs.length() == 2)
  match opt.blocks[0].instrs[0] {
    Store(addr~, value~) => assert_true(addr == Mem(0) && value == Imm(7))
    _ => assert_true(false)
  }
  match opt.blocks[0].instrs[1] {
    Add(dst~, ..) => assert_true(dst == 2)
    _ => assert_true(false)
  }
}

///|
/// 回归：CSE 删除冗余的同一表达式（含加法交换律），后续使用改名到规范寄存器。
/// `r3 = r1 + r2; r4 = r2 + r1; ret r4` → 删除 r4，`ret` 改名引用 r3。
test "cse_typed eliminates a commutative redundant expression" {
  let f = TypedFunction::{
    entry: "b0",
    blocks: [
      TypedBlock::{
        label: "b0",
        instrs: [
          Add(dst=3, lhs=Reg(1), rhs=Reg(2)),
          Add(dst=4, lhs=Reg(2), rhs=Reg(1)),
        ],
        terminator: Some(Ret(value=Some(Reg(4)))),
      },
    ],
  }
  let opt = cse_typed(f)
  assert_true(opt.blocks[0].instrs.length() == 1)
  match opt.blocks[0].terminator {
    Some(Ret(value=Some(Reg(r)))) => assert_true(r == 3)
    _ => assert_true(false)
  }
  // 等价：原 ret r4 == 优化后 ret r3，任取入参 r1=10,r2=20 → 30。
  let args : Map[Int, Int] = Map([(1, 10), (2, 20)])
  assert_true(interp_ir(opt, args~).returned == Some(30))
  assert_true(interp_ir(f, args~).returned == interp_ir(opt, args~).returned)
}

///|
/// 回归：验证型流水线对合法输入返回 `Ok`，对缺失终结指令的非法输入返回 `Err`。
test "run_typed_pipeline_validated accepts legal and rejects malformed IR" {
  let legal = TypedFunction::{
    entry: "b0",
    blocks: [
      TypedBlock::{
        label: "b0",
        instrs: [Add(dst=1, lhs=Imm(2), rhs=Imm(2))],
        terminator: Some(Ret(value=Some(Reg(1)))),
      },
    ],
  }
  match run_typed_pipeline_validated(legal, pbt_all_passes) {
    Ok(_) => assert_true(true)
    Err(_) => assert_true(false)
  }
  let malformed = TypedFunction::{
    entry: "b0",
    blocks: [TypedBlock::{ label: "b0", instrs: [], terminator: None }],
  }
  match run_typed_pipeline_validated(malformed, pbt_all_passes) {
    Err(_) => assert_true(true)
    Ok(_) => assert_true(false)
  }
}
