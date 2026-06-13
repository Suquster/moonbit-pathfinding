// coloring_test.mbt —— Chaitin-Briggs 乐观着色单元测试（任务 12.2）。
//
// 覆盖 simplify/potential-spill/select 阶段顺序见证、`k` 不足时出现 `Spill`
// （R1.2），以及 potential-spill 按溢出代价选中预期最低代价节点（R2.1）。

///|
/// K3 完全图在 k=3 时全部着色为 Reg 且无溢出（充足）。
test "allocate_coloring_briggs K3 在 k=3 全部着色" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }, { id: 2 }],
    edges: [
      ({ id: 0 }, { id: 1 }),
      ({ id: 1 }, { id: 2 }),
      ({ id: 0 }, { id: 2 }),
    ],
  }
  let alloc = allocate_coloring_briggs(g, 3)
  inspect(alloc.length(), content="3")
  assert_true(t_coloring_respects(g, alloc))
  inspect(t_count_spills(alloc), content="0")
}

///|
/// K3 在 k=2 时不可三着色，至少溢出一个；干涉不变量仍成立。
test "allocate_coloring_briggs K3 在 k=2 溢出且不变量保持" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }, { id: 2 }],
    edges: [
      ({ id: 0 }, { id: 1 }),
      ({ id: 1 }, { id: 2 }),
      ({ id: 0 }, { id: 2 }),
    ],
  }
  let alloc = allocate_coloring_briggs(g, 2)
  assert_true(t_count_spills(alloc) >= 1)
  assert_true(t_coloring_respects(g, alloc))
}

///|
/// 溢出代价：K4 在 k=3 时恰溢出一个；potential-spill 选中代价最低者（长区间节点 3）。
test "allocate_coloring_briggs potential-spill 选中最低代价节点" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }, { id: 2 }, { id: 3 }],
    edges: [
      ({ id: 0 }, { id: 1 }),
      ({ id: 0 }, { id: 2 }),
      ({ id: 0 }, { id: 3 }),
      ({ id: 1 }, { id: 2 }),
      ({ id: 1 }, { id: 3 }),
      ({ id: 2 }, { id: 3 }),
    ],
  }
  // 节点 3 区间最长 → 溢出代价最低 → 被选为乐观溢出候选并最终实际溢出。
  let intervals = [
    LiveInterval::{ variable: { id: 0 }, start: 0, end: 1 },
    LiveInterval::{ variable: { id: 1 }, start: 0, end: 1 },
    LiveInterval::{ variable: { id: 2 }, start: 0, end: 1 },
    LiveInterval::{ variable: { id: 3 }, start: 0, end: 100 },
  ]
  let cost = spill_cost(g, intervals)
  let alloc = allocate_coloring_briggs(g, 3, cost~)
  inspect(t_count_spills(alloc), content="1")
  // 最低代价节点 3 被溢出，其余着色为寄存器。
  inspect(alloc.get({ id: 3 }), content="Some(Spill(0))")
  assert_true(t_coloring_respects(g, alloc))
}
