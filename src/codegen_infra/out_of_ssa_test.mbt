// out_of_ssa_test.mbt —— SSA 析构单元测试（任务 6.2）。
//
// 覆盖 `a←b, b←a` 复制环引入临时打破的见证（R7.3），以及析构后 `phis` 为空且
// 沿路径求值与原 SSA 一致（R7.4）。

///|
/// 复制环 swap：sequentialize_parallel_copy 引入临时（负 id）打破环。
test "sequentialize_parallel_copy 破环引入临时" {
  // 并行复制 {0←1, 1←0}（swap）。
  let seq = sequentialize_parallel_copy([
    ({ id: 0 }, { id: 1 }),
    ({ id: 1 }, { id: 0 }),
  ])
  // 破环后为 3 条串行复制：先保存到临时（负 id），再依次复制。
  inspect(seq.length(), content="3")
  let (d0, s0) = seq[0]
  inspect(d0.id, content="-1")
  inspect(s0.id, content="0")
}

///|
/// 析构后不含任何 φ，且沿路径解释执行与原 SSA 一致。
test "destruct_ssa 消除全部 φ 且语义一致" {
  let diamond = [
    BasicBlock::{ label: "entry", instrs: ["cbr p then else"], succs: ["then", "else"] },
    BasicBlock::{ label: "then", instrs: ["x = 1", "br join"], succs: ["join"] },
    BasicBlock::{ label: "else", instrs: ["x = 2", "br join"], succs: ["join"] },
    BasicBlock::{ label: "join", instrs: ["ret x"], succs: [] },
  ]
  let ssa = build_ssa_minimal(diamond, entry="entry")
  let d = destruct_ssa(ssa)
  inspect(d.phis.length(), content="0")
  // 沿 then 来路：原 SSA 与析构后输出一致（均为 1）。
  let oa = evaluate(ssa, Map([]), ["entry", "then", "join"]).output
  let ob = evaluate(d, Map([]), ["entry", "then", "join"]).output
  assert_eq(oa, ob)
  inspect(ob, content="[1]")
  // 沿 else 来路一致（均为 2）。
  let ea = evaluate(ssa, Map([]), ["entry", "else", "join"]).output
  let eb = evaluate(d, Map([]), ["entry", "else", "join"]).output
  assert_eq(ea, eb)
  inspect(eb, content="[2]")
}
