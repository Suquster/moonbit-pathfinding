// sccp_test.mbt —— 稀疏条件常量传播单元测试（任务 8.2）。
//
// 覆盖常量变量使用被替换为字面量（R8.2）与常量条件分支仅一侧后继可达（R8.3，
// 由不可达边对应的 φ 实参被排除、汇合 φ 退化为可达侧常量见证）。

///|
/// 常量变量的使用被替换、全常量表达式被折叠。
test "sccp 替换常量变量并折叠常量表达式" {
  let p : SsaProgram = {
    blocks: [
      {
        label: "b0",
        instrs: ["x#0 = 5", "y#1 = x#0 + 1", "ret y#1"],
        succs: [],
      },
    ],
    phis: [],
  }
  let out = sccp(p)
  inspect(out.blocks[0].instrs[0], content="x#0 = 5")
  // y#1 = x#0 + 1 → x#0 替换为 5 → 折叠为 6。
  inspect(out.blocks[0].instrs[1], content="y#1 = 6")
  // ret y#1 → y#1 为常量 6 → 替换为字面量。
  inspect(out.blocks[0].instrs[2], content="ret 6")
}

///|
/// 常量条件分支：恒真条件使 else 边不可达，汇合 φ 退化为 then 侧常量并传播。
test "sccp 常量条件仅一侧可达使 φ 退化为常量" {
  let p : SsaProgram = {
    blocks: [
      {
        label: "entry",
        instrs: ["c#0 = 1", "cbr c#0 then else"],
        succs: ["then", "else"],
      },
      { label: "then", instrs: ["x#1 = 7", "br join"], succs: ["join"] },
      { label: "else", instrs: ["x#2 = 9", "br join"], succs: ["join"] },
      { label: "join", instrs: ["ret x#3"], succs: [] },
    ],
    phis: [{ dest: { id: 3 }, args: [{ id: 1 }, { id: 2 }] }],
  }
  let out = sccp(p)
  // 条件恒真 → 仅 then 边可达 → φ 仅取 then 侧 x#1=7 → ret x#3 替换为 7
  // （else 侧 x#2=9 被判定不可达而忽略）。
  inspect(out.blocks[3].instrs[0], content="ret 7")
}
