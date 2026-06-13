// liveness_test.mbt —— 活跃性构造桥单元测试（任务 1.2）。
//
// 覆盖 build_interference_from_liveness 端点见证、build_intervals_from_liveness
// 区间端点见证与按 Var.id 升序的规范化（R4.3, R4.4）。

///|
/// 同时活跃的 a、b 之间应建立一条干涉边；区间与边均按 id 升序规范化。
test "build_interference_from_liveness 在同时活跃的变量间建边" {
  let blocks = [
    BasicBlock::{
      label: "b0",
      instrs: ["a = 1", "b = 2", "c = a + b", "ret c"],
      succs: [],
    },
  ]
  let live = analyze_liveness(blocks)
  let g = build_interference_from_liveness(blocks, live)
  // 变量名升序映射：a=0, b=1, c=2。a 与 b 在 `c = a + b` 处同时活跃 → 边 (0,1)。
  inspect(g.nodes.length(), content="3")
  inspect(g.edges.length(), content="1")
  let (e0, e1) = g.edges[0]
  inspect(e0.id, content="0")
  inspect(e1.id, content="1")
}

///|
/// 活跃区间覆盖各变量首次定义到最后一次活跃使用的线性序号；按 id 升序返回。
test "build_intervals_from_liveness 覆盖定义到最后使用并按 id 升序" {
  let blocks = [
    BasicBlock::{
      label: "b0",
      instrs: ["a = 1", "b = 2", "c = a + b", "ret c"],
      succs: [],
    },
  ]
  let live = analyze_liveness(blocks)
  let intervals = build_intervals_from_liveness(blocks, live)
  inspect(intervals.length(), content="3")
  // a:[0,2], b:[1,2], c:[2,3]，按 variable.id 升序。
  inspect(intervals[0].variable.id, content="0")
  inspect(intervals[0].start, content="0")
  inspect(intervals[0].end, content="2")
  inspect(intervals[1].variable.id, content="1")
  inspect(intervals[1].start, content="1")
  inspect(intervals[1].end, content="2")
  inspect(intervals[2].variable.id, content="2")
  inspect(intervals[2].start, content="2")
  inspect(intervals[2].end, content="3")
}

///|
/// 空块序列：活跃性结果为空，干涉图无节点，区间为空（退化输入良构）。
test "analyze_liveness 空程序产出空结果" {
  let blocks : Array[BasicBlock] = []
  let live = analyze_liveness(blocks)
  let g = build_interference_from_liveness(blocks, live)
  inspect(g.nodes.length(), content="0")
  inspect(g.edges.length(), content="0")
  inspect(build_intervals_from_liveness(blocks, live).length(), content="0")
}
