// codegen_infra_gaps_wbtest.mbt —— 常量折叠/死代码消除记号回退分支收口
// （INFRA 第三十六批）。

///|
test "pass_const_fold：不可折叠算符保留原指令" {
  // "/" 不在 fold_op 支持集合 → fold_op None → 保留原指令。
  let p = SsaProgram::{
    blocks: [
      BasicBlock::{ label: "b", instrs: ["x#1 = 6 / 3", "ret x#1"], succs: [] },
    ],
    phis: [],
  }
  let out = run_passes(p, [ConstFold])
  assert_true(out.blocks[0].instrs[0] == "x#1 = 6 / 3")
}

///|
test "pass_const_fold：可折叠算符归约为常量" {
  let p = SsaProgram::{
    blocks: [
      BasicBlock::{
        label: "b",
        instrs: ["x#1 = 6 + 3", "y#1 = 4 * 2"],
        succs: [],
      },
    ],
    phis: [],
  }
  let out = run_passes(p, [ConstFold])
  assert_true(out.blocks[0].instrs[0] == "x#1 = 9")
  assert_true(out.blocks[0].instrs[1] == "y#1 = 8")
}

///|
test "pass_dead_code_elim：无版本号定义左值原样保留" {
  // 定义左值 "tmp" 无 '#' 版本号 → version_id None → 保留（不作 DCE 判定）。
  let p = SsaProgram::{
    blocks: [
      BasicBlock::{ label: "b", instrs: ["tmp = 1 + 2", "ret 0"], succs: [] },
    ],
    phis: [],
  }
  let out = run_passes(p, [DeadCodeElim])
  assert_true(out.blocks[0].instrs.contains("tmp = 1 + 2"))
}
