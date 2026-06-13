// evaluate_test.mbt —— 参考解释器单元测试（任务 4.2）。
//
// 覆盖直线算术求值、cbr 沿指定分支走、φ 按来路选实参的具体见证（R7.5）。

///|
/// 直线算术：x#0 = 2；y#1 = x#0 + 3；ret y#1 → 输出 [5]，变量取值正确。
test "evaluate 直线算术求值" {
  let p : SsaProgram = {
    blocks: [
      {
        label: "b0",
        instrs: ["x#0 = 2", "y#1 = x#0 + 3", "ret y#1"],
        succs: [],
      },
    ],
    phis: [],
  }
  let r = evaluate(p, Map([]), ["b0"])
  inspect(r.output, content="[5]")
  inspect(r.values.get("x#0"), content="Some(2)")
  inspect(r.values.get("y#1"), content="Some(5)")
}

///|
/// 条件分支：解释执行沿 `path` 指定分支走（cbr 不参与求值，仅由 path 决定）。
test "evaluate 沿指定分支解释执行 cbr" {
  let p : SsaProgram = {
    blocks: [
      { label: "b0", instrs: ["cbr c b1 b2"], succs: ["b1", "b2"] },
      { label: "b1", instrs: ["ret 1"], succs: [] },
      { label: "b2", instrs: ["ret 2"], succs: [] },
    ],
    phis: [],
  }
  inspect(evaluate(p, Map([]), ["b0", "b1"]).output, content="[1]")
  inspect(evaluate(p, Map([]), ["b0", "b2"]).output, content="[2]")
}

///|
/// φ 按来路前驱选实参：菱形最小 SSA 沿 then 来路得 then 的值，沿 else 得 else。
test "evaluate φ 按来路前驱选择实参" {
  let p = build_ssa_minimal(
    [
      { label: "entry", instrs: ["cbr p then else"], succs: ["then", "else"] },
      { label: "then", instrs: ["x = 1", "br join"], succs: ["join"] },
      { label: "else", instrs: ["x = 2", "br join"], succs: ["join"] },
      { label: "join", instrs: ["ret x"], succs: [] },
    ],
    entry="entry",
  )
  // 沿 then 来路：φ 选 then 的定义 → 输出 1。
  inspect(evaluate(p, Map([]), ["entry", "then", "join"]).output, content="[1]")
  // 沿 else 来路：φ 选 else 的定义 → 输出 2。
  inspect(evaluate(p, Map([]), ["entry", "else", "join"]).output, content="[2]")
}
