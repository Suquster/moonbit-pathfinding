// ssa_min_test.mbt —— 最小 SSA 构造单元测试（任务 5.2）。
//
// 覆盖菱形汇合的版本化重命名见证（R6.3），以及在最小文法输入上
// build_ssa_minimal 与冻结 build_ssa 的 φ 数量 / 版本化文本 / 块结构逐字段一致
// （向后兼容，R6.4）。

///|
/// 两个字符串数组逐元素相等。
fn t_str_arr_eq(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// 菱形汇合的版本化重命名见证：then→x#0、else→x#1、join 处 φ(x#0,x#1)→x#2。
test "build_ssa_minimal 菱形汇合版本化重命名见证" {
  let diamond = [
    BasicBlock::{
      label: "entry",
      instrs: ["cbr p then else"],
      succs: ["then", "else"],
    },
    BasicBlock::{ label: "then", instrs: ["x = 1", "br join"], succs: ["join"] },
    BasicBlock::{ label: "else", instrs: ["x = 2", "br join"], succs: ["join"] },
    BasicBlock::{ label: "join", instrs: ["ret x"], succs: [] },
  ]
  let bm = build_ssa_minimal(diamond, entry="entry")
  inspect(bm.phis.length(), content="1")
  inspect(bm.phis[0].args.length(), content="2")
  inspect(bm.blocks[1].instrs[0], content="x#0 = 1")
  inspect(bm.blocks[2].instrs[0], content="x#1 = 2")
  inspect(bm.blocks[3].instrs[0], content="ret x#2")
}

///|
/// 向后兼容（菱形）：build_ssa_minimal 与 build_ssa 的 φ 数 / 文本 / 块结构一致。
test "build_ssa_minimal 与 build_ssa 在菱形上逐字段一致" {
  let diamond = [
    BasicBlock::{
      label: "entry",
      instrs: ["cbr p then else"],
      succs: ["then", "else"],
    },
    BasicBlock::{ label: "then", instrs: ["x = 1", "br join"], succs: ["join"] },
    BasicBlock::{ label: "else", instrs: ["x = 2", "br join"], succs: ["join"] },
    BasicBlock::{ label: "join", instrs: ["ret x"], succs: [] },
  ]
  let bs = build_ssa(diamond)
  let bm = build_ssa_minimal(diamond, entry="entry")
  @test.assert_eq(bm.phis.length(), bs.phis.length())
  @test.assert_eq(bm.blocks.length(), bs.blocks.length())
  for i in 0..<bm.blocks.length() {
    assert_true(t_str_arr_eq(bm.blocks[i].instrs, bs.blocks[i].instrs))
    @test.assert_eq(bm.blocks[i].label, bs.blocks[i].label)
  }
  // φ 实参逐一致。
  @test.assert_eq(bm.phis[0].args.length(), bs.phis[0].args.length())
}

///|
/// 向后兼容（直线代码）：无 φ，定义左值与右值使用版本化文本一致。
test "build_ssa_minimal 与 build_ssa 在直线代码上一致" {
  let straight = [
    BasicBlock::{
      label: "b0",
      instrs: ["x = 1", "y = x + 2", "ret y"],
      succs: [],
    },
  ]
  let bs = build_ssa(straight)
  let bm = build_ssa_minimal(straight, entry="b0")
  inspect(bm.phis.length(), content="0")
  assert_true(t_str_arr_eq(bm.blocks[0].instrs, bs.blocks[0].instrs))
  inspect(bm.blocks[0].instrs[1], content="y#1 = x#0 + 2")
}
