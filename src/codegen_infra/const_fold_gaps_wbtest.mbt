// const_fold_gaps_wbtest.mbt —— 常量折叠/代数恒等与着色排序分支覆盖收口
// （INFRA 第二十二批）：fold_identity 各恒等式、fold_op 不支持运算符、
// parse_int/version_id 畸形拒绝、分量排序比较各分支的确定性见证。

///|
test "fold_identity/fold_op 各恒等式与拒绝" {
  // a + 0 / 0 + a / a - 0。
  assert_true(fold_identity("x#1", "+", "0") == Some("x#1"))
  assert_true(fold_identity("0", "+", "y#2") == Some("y#2"))
  assert_true(fold_identity("x#1", "-", "0") == Some("x#1"))
  // 同一 SSA 版本自减 → 0；纯常量自减不走此分支。
  assert_true(fold_identity("x#1", "-", "x#1") == Some("0"))
  assert_true(fold_identity("5", "-", "5") is None)
  // a * 1 / 1 * a / a * 0 / 0 * a。
  assert_true(fold_identity("x#1", "*", "1") == Some("x#1"))
  assert_true(fold_identity("1", "*", "y#2") == Some("y#2"))
  assert_true(fold_identity("x#1", "*", "0") == Some("0"))
  assert_true(fold_identity("0", "*", "y#2") == Some("0"))
  // 不适用组合。
  assert_true(fold_identity("x#1", "+", "y#2") is None)
  assert_true(fold_identity("x#1", "/", "0") is None)
  // fold_op：支持 + - *，其余拒绝。
  assert_true(fold_op("+", 2, 3) == Some(5))
  assert_true(fold_op("-", 2, 3) == Some(-1))
  assert_true(fold_op("*", 2, 3) == Some(6))
  assert_true(fold_op("/", 6, 2) is None)
}

///|
test "parse_int/version_id 畸形拒绝" {
  assert_true(parse_int("") is None)
  assert_true(parse_int("-") is None)
  assert_true(parse_int("-12") == Some(-12))
  assert_true(parse_int("1a2") is None)
  assert_true(version_id("x") is None)
  assert_true(version_id("x#") is None)
  assert_true(version_id("x#1b") is None)
  assert_true(version_id("x#12") == Some(12))
}

///|
test "pass_const_fold 折叠与恒等化简经 run_passes" {
  let p = SsaProgram::{
    blocks: [
      BasicBlock::{
        label: "entry",
        instrs: [
          "a#1 = 2 + 3", "b#1 = a#1 + 0", "c#1 = a#1 * 0", "d#1 = a#1 - a#1", "e#1 = a#1 + b#1",
        ],
        succs: [],
      },
    ],
    phis: [],
  }
  let out = run_passes(p, [ConstFold])
  assert_true(out.blocks[0].instrs.contains("a#1 = 5"))
  assert_true(out.blocks[0].instrs.contains("b#1 = a#1"))
  assert_true(out.blocks[0].instrs.contains("c#1 = 0"))
  assert_true(out.blocks[0].instrs.contains("d#1 = 0"))
  assert_true(out.blocks[0].instrs.contains("e#1 = a#1 + b#1"))
}

///|
test "allocate_coloring 多分量排序与溢出" {
  // 两个独立分量（{1,2,3} 三角形与 {10,11} 边），k=2 触发三角形溢出。
  let g = InterferenceGraph::{
    nodes: [{ id: 10 }, { id: 11 }, { id: 1 }, { id: 2 }, { id: 3 }],
    edges: [
      ({ id: 1 }, { id: 2 }),
      ({ id: 2 }, { id: 3 }),
      ({ id: 1 }, { id: 3 }),
      ({ id: 10 }, { id: 11 }),
    ],
  }
  let alloc = allocate_coloring(g, 2)
  // 三角形需 3 色：k=2 下恰有一个变量溢出栈槽。
  let mut spills = 0
  for _, loc in alloc {
    match loc {
      Spill(_) => spills = spills + 1
      Reg(_) => ()
    }
  }
  assert_true(spills == 1)
  // 干涉端点不同色。
  fn loc_eq(a : Location, b : Location) -> Bool {
    a == b
  }

  assert_false(
    loc_eq(alloc.get({ id: 1 }).unwrap(), alloc.get({ id: 2 }).unwrap()),
  )
  assert_false(
    loc_eq(alloc.get({ id: 10 }).unwrap(), alloc.get({ id: 11 }).unwrap()),
  )
}
