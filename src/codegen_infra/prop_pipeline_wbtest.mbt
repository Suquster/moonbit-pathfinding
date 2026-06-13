// prop_pipeline_wbtest.mbt —— Property 15：pass 框架保持 SSA 不变量（任务 10.3）。
//
// Feature: codegen-infra, Property 15: pass 框架保持 SSA 单赋值不变量
// **Validates: Requirements 8.4, 9.4, 10.3, 10.5**
//
// 性质：对任意随机 SSA 程序与随机 `OptPass` 序列（含 ConstFold/DeadCodeElim/
// CopyProp/Sccp/Gvn），经 `run_pipeline` 或 `run_to_fixpoint` 施加后结果仍满足
// SSA 单赋值不变量。白盒经包内私有 `version_id`（复用 `ssa_definition_ids` /
// `all_distinct`）抽取定义版本号。复用 holds_for_all（100 迭代）。

///|
/// OptPass 池（白盒可构造 pub enum 变体）。
let wb_optpass_pool : Array[OptPass] = [
  OptPass::ConstFold,
  OptPass::DeadCodeElim,
  OptPass::CopyProp,
  OptPass::Sccp,
  OptPass::Gvn,
]

///|
/// 生成器：随机 SSA 程序 + 随机 OptPass 序列。
fn gen_pipeline_case() -> @infra_pbt.Gen[(SsaProgram, Array[OptPass])] {
  @infra_pbt.Gen::new(fn(rng) {
    let blocks = gen_cfg_wb().generate(rng)
    let ssa = build_ssa_minimal(blocks, entry="b0")
    let len = rng.next_below(4)
    let passes : Array[OptPass] = []
    let mut i = 0
    while i < len {
      passes.push(wb_optpass_pool[rng.next_below(wb_optpass_pool.length())])
      i = i + 1
    }
    (ssa, passes)
  })
}

///|
/// Feature: codegen-infra, Property 15: pass 框架保持 SSA 单赋值不变量
/// **Validates: Requirements 8.4, 9.4, 10.3, 10.5**
test "Feature: codegen-infra, Property 15: pass framework preserves SSA invariant" {
  let ok = @infra_pbt.holds_for_all(
    gen_pipeline_case(),
    fn(pair) {
      let (ssa, passes) = pair
      let a = run_pipeline(ssa, passes)
      let b = run_to_fixpoint(ssa, passes)
      all_distinct(ssa_definition_ids(a)) && all_distinct(ssa_definition_ids(b))
    },
    iters=100,
  )
  assert_true(ok)
}
