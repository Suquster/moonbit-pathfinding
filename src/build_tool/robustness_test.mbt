// robustness_test.mbt —— T6.3 鲁棒性回归：缺失输入 / 写竞争 / 前置校验。

///|
/// 便捷构造动作。
fn mk_rb_action(
  id : String,
  inputs : Array[String],
  outputs : Array[String],
) -> Action {
  { id, inputs, outputs, command: "cc " + id }
}

///|
test "T6.3: missing_inputs reports unsatisfiable inputs deterministically" {
  let actions = [
    mk_rb_action("link", ["a.o", "b.o"], ["app"]),
    mk_rb_action("cc_a", ["a.c"], ["a.o"]),
    mk_rb_action("cc_b", ["b.c"], ["b.o"]),
  ]
  // b.c 未声明为源文件：唯一缺失输入。
  let report = missing_inputs(actions, ["a.c"])
  assert_true(report == [("cc_b", "b.c")])
  // 补齐源文件后校验通过。
  assert_eq(missing_inputs(actions, ["a.c", "b.c"]).length(), 0)
}

///|
test "T6.3: write_conflicts detects unordered writers of the same output" {
  let a = mk_rb_action("gen1", [], ["shared.h"])
  let b = mk_rb_action("gen2", [], ["shared.h"])
  let c = mk_rb_action("use", ["shared.h"], ["main.o"])
  // gen1 与 gen2 无先后序 → 竞争。
  let conflicts = write_conflicts([a, b, c], [("gen1", "use"), ("gen2", "use")])
  assert_true(conflicts == [("gen1", "gen2", "shared.h")])
  // 建立 gen1 → gen2 先后序后竞争消除。
  let ordered = write_conflicts([a, b, c], [("gen1", "gen2"), ("gen2", "use")])
  assert_eq(ordered.length(), 0)
}

///|
test "T6.3: validate_build reports cycle, missing input, conflict in order" {
  let a = mk_rb_action("a", ["src"], ["a.o"])
  let b = mk_rb_action("b", ["a.o"], ["b.o"])
  // 环：a → b → a。
  match validate_build([a, b], [("a", "b"), ("b", "a")], ["src"]) {
    Err(msg) => assert_true(msg.has_prefix("cycle: "))
    Ok(_) => assert_true(false)
  }
  // 缺失输入：src 未声明。
  match validate_build([a, b], [("a", "b")], []) {
    Err(msg) => assert_eq(msg, "missing inputs: a requires src")
    Ok(_) => assert_true(false)
  }
  // 全部通过。
  assert_true(validate_build([a, b], [("a", "b")], ["src"]) is Ok(_))
}

///|
/// T6.3 属性：确定性——同一输入多次校验逐字节一致；且把并行调度中同波动作
/// 的产物设为互不相交时 `write_conflicts` 恒为空。
test "T6.3 property: robustness checks are deterministic (100 iters)" {
  let gen = @infra_pbt.gen_int_range(0, 1000000)
  let ok = @infra_pbt.holds_for_all(gen, fn(seed) {
    // 由种子构造 1~8 个动作的链 + 扇出混合图，注入可控缺陷。
    let n = seed % 8 + 1
    let inject_missing = seed % 3 == 0
    let inject_conflict = seed % 5 == 0
    let actions : Array[Action] = []
    let edges : Array[(String, String)] = []
    let sources : Array[String] = ["s0"]
    for i in 0..<n {
      let id = "t" + i.to_string()
      let input = if i == 0 { "s0" } else { "o" + (i - 1).to_string() }
      actions.push(mk_rb_action(id, [input], ["o" + i.to_string()]))
      if i > 0 {
        edges.push(("t" + (i - 1).to_string(), id))
      }
    }
    if inject_missing {
      actions.push(mk_rb_action("ghost", ["nowhere"], ["ghost.o"]))
    }
    if inject_conflict {
      actions.push(mk_rb_action("dup", [], ["o0"]))
    }
    let r1 = validate_build(actions, edges, sources)
    let r2 = validate_build(actions, edges, sources)
    // 确定性：两次校验结果一致。
    let deterministic = r1 == r2
    // 语义：注入缺陷 ⇔ 校验失败。
    let should_fail = inject_missing || inject_conflict
    let failed = r1 is Err(_)
    deterministic && failed == should_fail
  })
  assert_true(ok)
}
