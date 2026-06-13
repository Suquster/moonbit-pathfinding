// pipeline_test.mbt —— pass 框架单元测试（任务 10.2）。
//
// 覆盖按声明顺序施加（R10.1）、不动点收敛终止（R10.2），以及既有 `run_passes`
// 在既有 `Pass` 序列上行为冻结的回归（R10.4）。

///|
/// 按声明顺序施加：ConstFold 折叠常量后 DeadCodeElim 删除未使用定义。
test "run_pipeline 按声明顺序施加 ConstFold 后 DeadCodeElim" {
  let base = build_ssa([
    BasicBlock::{
      label: "b0",
      instrs: ["x = 1 + 2", "y = 5", "ret x"],
      succs: [],
    },
  ])
  let out = run_pipeline(base, [OptPass::ConstFold, OptPass::DeadCodeElim])
  // x#0 = 1 + 2 → 3；y#1 = 5 未被使用 → 删除。
  inspect(out.blocks[0].instrs.length(), content="2")
  inspect(out.blocks[0].instrs[0], content="x#0 = 3")
  inspect(out.blocks[0].instrs[1], content="ret x#0")
}

///|
/// 不动点收敛：run_to_fixpoint 终止并产出与单遍施加同样收敛的结果。
test "run_to_fixpoint 收敛终止" {
  let base = build_ssa([
    BasicBlock::{
      label: "b0",
      instrs: ["x = 1 + 2", "y = 5", "ret x"],
      succs: [],
    },
  ])
  let out = run_to_fixpoint(base, [OptPass::ConstFold, OptPass::DeadCodeElim])
  inspect(out.blocks[0].instrs.length(), content="2")
  inspect(out.blocks[0].instrs[0], content="x#0 = 3")
  // 再施加一遍不再变化（幂等收敛）。
  let again = run_pipeline(out, [OptPass::ConstFold, OptPass::DeadCodeElim])
  assert_eq(again.blocks[0].instrs.length(), out.blocks[0].instrs.length())
}

///|
/// 既有 run_passes 行为冻结回归：ConstFold 在既有 Pass 序列上与 0.1.0 一致。
test "run_passes 既有 Pass 行为冻结回归" {
  let base = build_ssa([
    BasicBlock::{ label: "b0", instrs: ["x = 1 + 2", "ret x"], succs: [] },
  ])
  let out = run_passes(base, [Pass::ConstFold])
  inspect(out.blocks[0].instrs[0], content="x#0 = 3")
}
