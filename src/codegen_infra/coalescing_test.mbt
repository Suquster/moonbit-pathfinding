// coalescing_test.mbt —— 寄存器合并单元测试（任务 13.2）。
//
// 覆盖 George / Briggs 判据在典型图上的布尔结果（R2.3），以及存在干涉边时拒绝
// 合并的见证（R2.4）。

///|
/// George / Briggs 判据：a(0)/b(1) 不干涉、a 唯一邻居 c(2) 为低度 → 二者均可合并。
test "can_coalesce George/Briggs 在可合并图上为真" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }, { id: 2 }],
    edges: [({ id: 0 }, { id: 2 })],
  }
  inspect(can_coalesce_george(g, { id: 0 }, { id: 1 }, 2), content="true")
  inspect(can_coalesce_briggs(g, { id: 0 }, { id: 1 }, 2), content="true")
}

///|
/// 存在干涉边 a-b 时拒绝合并：两判据均为假，coalesce 不减少节点。
test "coalesce 拒绝合并互相干涉的变量对" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }],
    edges: [({ id: 0 }, { id: 1 })],
  }
  inspect(can_coalesce_george(g, { id: 0 }, { id: 1 }, 2), content="false")
  inspect(can_coalesce_briggs(g, { id: 0 }, { id: 1 }, 2), content="false")
  let merged = coalesce(g, { moves: [({ id: 0 }, { id: 1 })] }, 2)
  // 干涉对未被合并 → 仍为 2 个节点。
  inspect(merged.nodes.length(), content="2")
}

///|
/// 非干涉的传送相关对在保守判据下被合并：节点数减少。
test "coalesce 合并非干涉的传送相关对" {
  let g = InterferenceGraph::{
    nodes: [{ id: 0 }, { id: 1 }, { id: 2 }],
    edges: [({ id: 0 }, { id: 2 })],
  }
  let merged = coalesce(
    g,
    { moves: [({ id: 0 }, { id: 1 })] },
    2,
    strategy=Briggs,
  )
  // 0 与 1 不干涉且保守可合并 → 合并后 2 个节点。
  inspect(merged.nodes.length(), content="2")
}
