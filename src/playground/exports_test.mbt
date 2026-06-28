// wasm-gc 导出层（exports.mbt）冒烟单元测试（任务 26.2）。
//
// 设计依据：design.md §「方向 1 · 1.3 wasm-gc 导出层与体积优化」；
// 需求依据：R1.2（逐步执行返回 已访问/边界/当前/终止 单步可观察输出）、
// R1.3（缺失/非法算法入口返回携带错误码的失败结果而非静默落空）。
//
// 这里只做「示例 + 边界」级别的冒烟校验，验证整型句柄协议三类关键行为：
//   1. `pg_reset` 合法/非法（行列非正）的返回码；
//   2. 编辑 + `pg_select_algo` + `pg_compute` 返回正步数，且 `pg_step_*`
//      可读取首帧/末帧的 已访问/边界/当前/终止标志（R1.2）；
//   3. `pg_last_error` 对 `@graph.PathError` 的错误码映射（R1.3），含非法
//      算法码、越界与重叠编辑等情形；
//   4. 不可达布局下 `pg_final_path_len` 返回 `-1` 而 `pg_last_error` 仍为 0
//      （R3.4 的合法计算结果语义，区别于操作错误）。
//
// 注意：导出层维持「单一全局会话句柄」，会话状态在测试用例间共享，因此每个
// 用例均先以 `pg_reset` 重置网格、并显式 `pg_select_algo` 选定算法，以避免
// 顺序耦合（不依赖其它用例遗留的算法/轨迹状态）。

///|
/// 稳定错误码（与 `exports.mbt` 中的 `@graph.PathError` 映射一一对应，构成
/// 宿主可依赖的 ABI）。在黑盒测试包内以命名常量复刻，避免裸魔法数字。
let ok : Int = 0

///|
/// `InvalidArgument`（含越界/非法参数/算法码非法）的稳定错误码。
let invalid_argument : Int = 5

///|
/// 算法码：BFS（`0=BFS`、`1=DFS`、`2=Dijkstra`、`3=A*`、`4=JPS`）。
let algo_code_bfs : Int = 0

///|
/// `pg_step_flags` 的 done 位（bit0）。
let flag_done_bit : Int = 1

///|
/// `pg_step_flags` 的 found 位（bit1）。
let flag_found_bit : Int = 2

///|
/// 「无对应节点 / 越界 / 不可达」的整型哨兵值。
let sentinel : Int = -1

///|
test "pg_reset 合法返回 0、非法（行列非正）返回 InvalidArgument 码" {
  // 合法网格：3×3 全通行，返回成功码。
  @test.assert_eq(@playground.pg_reset(3, 3), ok)
  @test.assert_eq(@playground.pg_last_error(), ok)
  // 行数非正：Grid::new 拒绝，映射为 InvalidArgument 码且不改动既有网格。
  @test.assert_eq(@playground.pg_reset(0, 3), invalid_argument)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
  // 列数为负：同样拒绝。
  @test.assert_eq(@playground.pg_reset(3, -1), invalid_argument)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
  // 单元格不足 2（1×1 无法容纳互异起终点）：拒绝。
  @test.assert_eq(@playground.pg_reset(1, 1), invalid_argument)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
}

///|
test "编辑 + 选择算法 + pg_compute 返回正步数" {
  @test.assert_eq(@playground.pg_reset(3, 3), ok)
  // 在既非起点（0）也非终点（8）的可通行格上设置一个障碍。
  @test.assert_eq(@playground.pg_set_obstacle(4, 1), ok)
  @test.assert_eq(@playground.pg_last_error(), ok)
  @test.assert_eq(@playground.pg_select_algo(algo_code_bfs), ok)
  // 计算逐步轨迹：起点必被弹出至少一帧，故步数恒为正。
  let count = @playground.pg_compute()
  @test.assert_eq(count > 0, true)
  @test.assert_eq(@playground.pg_last_error(), ok)
}

///|
test "pg_step_* 读取首帧与末帧（visited/frontier/current/flags）" {
  @test.assert_eq(@playground.pg_reset(3, 3), ok)
  @test.assert_eq(@playground.pg_select_algo(algo_code_bfs), ok)
  let count = @playground.pg_compute()
  @test.assert_eq(count > 0, true)

  // —— 首帧（step 0）：起点刚被弹出并 closed ——
  // 已访问恰含起点一个节点。
  @test.assert_eq(@playground.pg_step_visited_len(0), 1)
  // 已访问下标 0 即起点（线性下标 0）。
  @test.assert_eq(@playground.pg_step_visited_at(0, 0), 0)
  // 当前扩展节点为起点。
  @test.assert_eq(@playground.pg_step_current(0), 0)
  // 边界长度为合法非负读取（不是 -1 错误哨兵）。
  @test.assert_eq(@playground.pg_step_frontier_len(0) >= 0, true)
  // 首帧通常未终止（起点非终点）。
  @test.assert_eq(@playground.pg_step_flags(0) & flag_done_bit, 0)
  @test.assert_eq(@playground.pg_last_error(), ok)

  // —— 末帧（step count-1）：目标可达，命中并终止 ——
  let last = count - 1
  // done 位置位（终止帧）。
  @test.assert_eq(
    @playground.pg_step_flags(last) & flag_done_bit,
    flag_done_bit,
  )
  // found 位置位（命中目标帧）。
  @test.assert_eq(
    @playground.pg_step_flags(last) & flag_found_bit,
    flag_found_bit,
  )
  // 末帧当前节点即终点（3×3 网格终点线性下标 8）。
  @test.assert_eq(@playground.pg_step_current(last), 8)
  @test.assert_eq(@playground.pg_last_error(), ok)

  // —— 最终路径读取：含起点与终点 ——
  let path_len = @playground.pg_final_path_len()
  @test.assert_eq(path_len > 0, true)
  @test.assert_eq(@playground.pg_last_error(), ok)
  @test.assert_eq(@playground.pg_final_path_at(0), 0)
  @test.assert_eq(@playground.pg_final_path_at(path_len - 1), 8)
}

///|
test "pg_step_* 越界读取返回 -1 并置 InvalidArgument 错误码" {
  @test.assert_eq(@playground.pg_reset(3, 3), ok)
  @test.assert_eq(@playground.pg_select_algo(algo_code_bfs), ok)
  let count = @playground.pg_compute()
  @test.assert_eq(count > 0, true)
  // 帧序越界：返回 -1 并置错误码。
  @test.assert_eq(@playground.pg_step_visited_len(count), sentinel)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
  // 帧内下标越界：返回 -1 并置错误码。
  @test.assert_eq(@playground.pg_step_visited_at(0, 999), sentinel)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
  @test.assert_eq(@playground.pg_step_frontier_at(0, 999), sentinel)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
}

///|
test "不可达布局下 pg_final_path_len 返回 -1 且 pg_last_error 为 0" {
  // 2×2 网格：起点 0=(0,0)、终点 3=(1,1)。封死终点的两个正交邻居（1 与 2），
  // 使终点孤立、从起点不可达。
  @test.assert_eq(@playground.pg_reset(2, 2), ok)
  @test.assert_eq(@playground.pg_set_obstacle(1, 1), ok)
  @test.assert_eq(@playground.pg_set_obstacle(2, 1), ok)
  @test.assert_eq(@playground.pg_select_algo(algo_code_bfs), ok)
  let count = @playground.pg_compute()
  // 仍至少产出一帧（起点被弹出）。
  @test.assert_eq(count > 0, true)
  // 不可达是合法计算结果：路径长度返回 -1，错误码保持成功（非操作失败）。
  @test.assert_eq(@playground.pg_final_path_len(), sentinel)
  @test.assert_eq(@playground.pg_last_error(), ok)
}

///|
test "非法算法码 pg_select_algo 返回 InvalidArgument 且 last_error 映射正确" {
  @test.assert_eq(@playground.pg_reset(3, 3), ok)
  // 算法码超出 0..4：缺失算法入口，返回 InvalidArgument 码而非静默落空（R1.3）。
  @test.assert_eq(@playground.pg_select_algo(99), invalid_argument)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
  // 负算法码：同样拒绝。
  @test.assert_eq(@playground.pg_select_algo(-1), invalid_argument)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
}

///|
test "编辑非法时 pg_last_error 映射为 InvalidArgument" {
  @test.assert_eq(@playground.pg_reset(3, 3), ok)
  // 障碍格越界：返回 InvalidArgument 码。
  @test.assert_eq(@playground.pg_set_obstacle(999, 1), invalid_argument)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
  // 起点拖到终点（重叠）：拒绝并置错误码。
  @test.assert_eq(@playground.pg_set_start(8), invalid_argument)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
  // 终点越界：拒绝并置错误码。
  @test.assert_eq(@playground.pg_set_goal(999), invalid_argument)
  @test.assert_eq(@playground.pg_last_error(), invalid_argument)
}
