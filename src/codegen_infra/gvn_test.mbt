// gvn_test.mbt —— 全局值编号单元测试（任务 9.2）。
//
// 覆盖两个计算等价表达式被合并（R9.1）、无活跃使用定义被删除（R9.2）、复制目标
// 使用被替换为源（R9.3）的具体见证。

///|
/// 两个计算等价表达式（相同操作符 + 相同 SSA 操作数）被合并为一个，后者删除、
/// 其使用替换为代表。
test "gvn 合并计算等价的表达式" {
  let p : SsaProgram = {
    blocks: [
      {
        label: "b0",
        instrs: [
          "a#0 = 5", "b#1 = 6", "x#2 = a#0 + b#1", "y#3 = a#0 + b#1", "ret y#3",
        ],
        succs: [],
      },
    ],
    phis: [],
  }
  let out = gvn(p)
  // y#3 与 x#2 计算等价 → y#3 删除，ret 引用替换为 x#2。
  inspect(out.blocks[0].instrs.length(), content="4")
  inspect(out.blocks[0].instrs[3], content="ret x#2")
}

///|
/// 死代码消除：无活跃使用的定义 a#0 被删除，被 ret 使用的 b#1 保留。
test "gvn 删除无活跃使用的定义" {
  let p : SsaProgram = {
    blocks: [
      { label: "b0", instrs: ["a#0 = 1", "b#1 = 2", "ret b#1"], succs: [] },
    ],
    phis: [],
  }
  let out = gvn(p)
  inspect(out.blocks[0].instrs.length(), content="2")
  inspect(out.blocks[0].instrs[0], content="b#1 = 2")
  inspect(out.blocks[0].instrs[1], content="ret b#1")
}

///|
/// 复制传播：复制目标 b#1 的使用被替换为源 a#0，复制删除。
test "gvn 复制目标使用替换为源" {
  let p : SsaProgram = {
    blocks: [
      { label: "b0", instrs: ["a#0 = 5", "b#1 = a#0", "ret b#1"], succs: [] },
    ],
    phis: [],
  }
  let out = gvn(p)
  inspect(out.blocks[0].instrs.length(), content="2")
  inspect(out.blocks[0].instrs[1], content="ret a#0")
}
