// 网格模型 `Grid` 冒烟单元测试（任务 25.1）。
//
// 这里仅做「示例 + 边界」级别的单元校验，确认构造、三种编辑操作的值语义
// （成功返回新网格、失败返回 Err 且不改入参）、successor 转换与曼哈顿启发的
// 基本正确性。完整的属性测试（Property 2 合法编辑重算 / Property 3 非法编辑
// 被拒）由任务 25.2 / 25.3 承载。

///|
test "Grid::new 构造合法网格并设置默认端点" {
  let grid = @playground.Grid::new(3, 4).unwrap()
  @test.assert_eq(grid.rows, 3)
  @test.assert_eq(grid.cols, 4)
  @test.assert_eq(grid.cell_count(), 12)
  @test.assert_eq(grid.start, 0)
  @test.assert_eq(grid.goal, 11)
  // 初始无障碍。
  for b in grid.blocked {
    @test.assert_eq(b, false)
  }
}

///|
test "Grid::new 拒绝非正行列与不足 2 格的网格" {
  assert_true(@playground.Grid::new(0, 4) is Err(_))
  assert_true(@playground.Grid::new(3, 0) is Err(_))
  assert_true(@playground.Grid::new(-1, 4) is Err(_))
  // 1x1 网格无法容纳互异端点。
  assert_true(@playground.Grid::new(1, 1) is Err(_))
}

///|
test "Grid::set_start 合法移动返回新网格且不改入参" {
  let grid = @playground.Grid::new(3, 3).unwrap()
  let moved = grid.set_start(4).unwrap()
  @test.assert_eq(moved.start, 4)
  // 入参保持不变（值语义）。
  @test.assert_eq(grid.start, 0)
}

///|
test "Grid::set_start 拒绝越界/障碍/与终点重叠" {
  let grid = @playground.Grid::new(3, 3).unwrap()
  // 越界。
  assert_true(grid.set_start(9) is Err(_))
  assert_true(grid.set_start(-1) is Err(_))
  // 与终点重叠（终点默认下标 8）。
  assert_true(grid.set_start(8) is Err(_))
  // 障碍格：先在下标 4 放置障碍，再尝试把起点放上去。
  let withobs = grid.toggle_obstacle(4).unwrap()
  let rejected = withobs.set_start(4)
  assert_true(rejected is Err(_))
  // 被拒后入参不变。
  @test.assert_eq(withobs.start, 0)
}

///|
test "Grid::set_goal 合法移动返回新网格且不改入参" {
  let grid = @playground.Grid::new(3, 3).unwrap()
  let moved = grid.set_goal(4).unwrap()
  @test.assert_eq(moved.goal, 4)
  @test.assert_eq(grid.goal, 8)
}

///|
test "Grid::set_goal 拒绝与起点重叠" {
  let grid = @playground.Grid::new(3, 3).unwrap()
  // 起点默认下标 0。
  assert_true(grid.set_goal(0) is Err(_))
}

///|
test "Grid::toggle_obstacle 合法切换并可来回切换" {
  let grid = @playground.Grid::new(3, 3).unwrap()
  let on = grid.toggle_obstacle(4).unwrap()
  @test.assert_eq(on.blocked[4], true)
  // 入参未变。
  @test.assert_eq(grid.blocked[4], false)
  // 再次切换还原。
  let off = on.toggle_obstacle(4).unwrap()
  @test.assert_eq(off.blocked[4], false)
}

///|
test "Grid::toggle_obstacle 拒绝端点格与越界" {
  let grid = @playground.Grid::new(3, 3).unwrap()
  // 起点格（0）/终点格（8）。
  assert_true(grid.toggle_obstacle(0) is Err(_))
  assert_true(grid.toggle_obstacle(8) is Err(_))
  // 越界。
  assert_true(grid.toggle_obstacle(9) is Err(_))
  // 被拒后障碍布局不变。
  @test.assert_eq(grid.blocked[0], false)
}

///|
test "Grid::to_successors 产出 4-邻接均匀单位权且按升序" {
  let grid = @playground.Grid::new(3, 3).unwrap()
  let succ = grid.to_successors()
  // 中心格 4 的邻居：上1、左3、右5、下7（升序），权均为 1。
  @test.assert_eq(succ(4), [(1, 1), (3, 1), (5, 1), (7, 1)])
  // 角落格 0：只有右1、下3。
  @test.assert_eq(succ(0), [(1, 1), (3, 1)])
  // 越界节点产出空。
  @test.assert_eq(succ(9), [])
}

///|
test "Grid::to_successors 障碍单元格无出边且不作为邻居" {
  let grid = @playground.Grid::new(3, 3).unwrap()
  // 将下标 1（中心格 4 的上邻居）设为障碍。
  let g = grid.toggle_obstacle(1).unwrap()
  let succ = g.to_successors()
  // 障碍格自身无出边。
  @test.assert_eq(succ(1), [])
  // 中心格 4 的邻居不再包含 1。
  @test.assert_eq(succ(4), [(3, 1), (5, 1), (7, 1)])
}

///|
test "Grid::manhattan 计算曼哈顿距离" {
  let grid = @playground.Grid::new(3, 3).unwrap()
  let h = grid.manhattan(8) // goal 在 (2,2)
  @test.assert_eq(h(0), 4) // (0,0) -> (2,2) = 2+2
  @test.assert_eq(h(8), 0) // 自身
  @test.assert_eq(h(4), 2) // (1,1) -> (2,2) = 1+1
}

///|
test "Grid 编辑后接入 trace_search 可在网格上找到最短路" {
  // 3x3 全通网格，起点 0、终点 8，A* + 曼哈顿启发。
  let grid = @playground.Grid::new(3, 3).unwrap()
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::AStar,
    grid.start,
    grid.goal,
    grid.to_successors(),
    grid.manhattan(grid.goal),
  )
  @test.assert_eq(trace.reachable, true)
  let path = trace.final_path.unwrap()
  // 最短路径长度为 5 个节点（曼哈顿距离 4 + 起点）。
  @test.assert_eq(path.length(), 5)
  @test.assert_eq(path[0], 0)
  @test.assert_eq(path[path.length() - 1], 8)
}

///|
test "Grid 障碍布局变化导致目标不可达" {
  // 3x3 网格，用障碍把终点 8 完全围死：阻断其上邻居 5 与左邻居 7。
  let grid = @playground.Grid::new(3, 3).unwrap()
  let g = grid.toggle_obstacle(5).unwrap().toggle_obstacle(7).unwrap()
  let trace = @playground.trace_search(
    @playground.PlaygroundAlgo::BFS,
    g.start,
    g.goal,
    g.to_successors(),
    g.manhattan(g.goal),
  )
  @test.assert_eq(trace.reachable, false)
  @test.assert_eq(trace.final_path, None)
}
