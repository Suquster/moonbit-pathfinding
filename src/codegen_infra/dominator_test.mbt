// dominator_test.mbt —— 支配树单元测试（任务 2.2）。
//
// 覆盖不可达块被排除出支配树（R5.4）与「除入口外每个可达节点恰有一个 idom」
// 的具体见证（R5.2）。

///|
/// 不可达块 b2 被排除出支配树：不在 reachable，也不在 idom 键集。
test "build_dom_tree 排除不可达块" {
  let blocks = [
    BasicBlock::{ label: "b0", instrs: ["br b1"], succs: ["b1"] },
    BasicBlock::{ label: "b1", instrs: ["ret a"], succs: [] },
    BasicBlock::{ label: "b2", instrs: ["ret a"], succs: [] },
  ]
  let dom = build_dom_tree(blocks, entry="b0")
  inspect(t_contains_str(dom.reachable, "b0"), content="true")
  inspect(t_contains_str(dom.reachable, "b1"), content="true")
  inspect(t_contains_str(dom.reachable, "b2"), content="false")
  inspect(dom.idom.get("b1"), content="Some(b0)")
  inspect(dom.idom.get("b2"), content="None")
}

///|
/// 菱形 CFG：then/else/join 的直接支配者均为 entry；恰各一个 idom。
test "build_dom_tree 菱形汇合各非入口节点恰有一个 idom" {
  let blocks = [
    BasicBlock::{
      label: "entry",
      instrs: ["cbr p then else"],
      succs: ["then", "else"],
    },
    BasicBlock::{ label: "then", instrs: ["x = 1", "br join"], succs: ["join"] },
    BasicBlock::{ label: "else", instrs: ["x = 2", "br join"], succs: ["join"] },
    BasicBlock::{ label: "join", instrs: ["ret x"], succs: [] },
  ]
  let dom = build_dom_tree(blocks, entry="entry")
  inspect(dom.root, content="entry")
  inspect(dom.reachable.length(), content="4")
  inspect(dom.idom.get("then"), content="Some(entry)")
  inspect(dom.idom.get("else"), content="Some(entry)")
  inspect(dom.idom.get("join"), content="Some(entry)")
  // 入口不在 idom 键集。
  inspect(dom.idom.get("entry"), content="None")
  // 支配关系：entry 支配全部；then 不支配 join。
  inspect(dom.dominates("entry", "join"), content="true")
  inspect(dom.dominates("then", "join"), content="false")
}
