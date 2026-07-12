// gaps88_test.mbt —— 寄存器分配退化臂（第八十八批）。

///|
/// allocate_coloring_briggs：k ≤ 0 时全部按 id 升序溢出。
test "allocate_coloring_briggs：k=0 全部溢出" {
  let g = InterferenceGraph::{
    nodes: [{ id: 2 }, { id: 0 }, { id: 1 }],
    edges: [({ id: 0 }, { id: 1 })],
  }
  let alloc = allocate_coloring_briggs(g, 0)
  inspect(alloc.length(), content="3")
  assert_true(alloc.get({ id: 0 }) is Some(Spill(0)))
  assert_true(alloc.get({ id: 1 }) is Some(Spill(1)))
  assert_true(alloc.get({ id: 2 }) is Some(Spill(2)))
}
