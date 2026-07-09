// exports_gaps_wbtest.mbt —— playground 导出 ABI 分支覆盖收口
// （INFRA 第二十批）：算法码全谱、错误码映射、轨迹缺失/帧越界哨兵、
// 不可达路径与旗标查询的确定性见证。

///|
test "playground 算法码全谱与非法码拒绝" {
  assert_true(pg_reset(4, 4) == err_ok)
  assert_true(pg_set_start(0) == err_ok)
  assert_true(pg_set_goal(15) == err_ok)
  for code in [algo_bfs, algo_dfs, algo_dijkstra, algo_astar, algo_jps] {
    assert_true(pg_select_algo(code) == err_ok)
    assert_true(pg_compute() > 0)
    assert_true(pg_final_path_len() > 0)
  }
  assert_true(pg_select_algo(99) == err_invalid_argument)
}

///|
test "playground 轨迹缺失与帧越界哨兵" {
  assert_true(pg_reset(3, 3) == err_ok)
  // 未 compute：全部查询返回哨兵并置 InvalidArgument。
  assert_true(pg_step_visited_len(0) == sentinel_none)
  assert_true(pg_last_error() == err_invalid_argument)
  assert_true(pg_step_visited_at(0, 0) == sentinel_none)
  assert_true(pg_step_frontier_len(0) == sentinel_none)
  assert_true(pg_step_frontier_at(0, 0) == sentinel_none)
  assert_true(pg_step_current(0) == sentinel_none)
  assert_true(pg_step_flags(0) == sentinel_none)
  assert_true(pg_final_path_len() == sentinel_none)
  assert_true(pg_last_error() == err_invalid_argument)
  assert_true(pg_final_path_at(0) == sentinel_none)
  // 物化后帧/下标越界。
  assert_true(pg_set_goal(8) == err_ok)
  assert_true(pg_select_algo(algo_bfs) == err_ok)
  assert_true(pg_set_start(0) == err_ok)
  let steps = pg_compute()
  assert_true(steps > 0)
  assert_true(pg_step_visited_len(steps) == sentinel_none)
  assert_true(pg_step_visited_at(0, 9999) == sentinel_none)
  assert_true(pg_step_frontier_at(0, -1) == sentinel_none)
  assert_true(pg_step_flags(-1) == sentinel_none)
  assert_true(pg_final_path_at(9999) == sentinel_none)
  // 末帧旗标：done|found。
  assert_true(pg_step_flags(steps - 1) == (flag_done | flag_found))
  // 首帧 current 与 frontier 合法读取。
  assert_true(pg_step_current(0) >= sentinel_none)
  assert_true(pg_step_frontier_len(steps - 1) >= 0)
}

///|
test "playground 不可达与错误码映射" {
  // 围墙隔离目标：不可达 → final_path_len 哨兵但 last_error=0。
  assert_true(pg_reset(3, 3) == err_ok)
  assert_true(pg_set_obstacle(1, 1) == err_ok)
  assert_true(pg_set_obstacle(3, 1) == err_ok)
  assert_true(pg_set_obstacle(4, 1) == err_ok)
  assert_true(pg_set_start(0) == err_ok)
  assert_true(pg_set_goal(8) == err_ok)
  assert_true(pg_select_algo(algo_bfs) == err_ok)
  assert_true(pg_compute() > 0)
  assert_true(pg_final_path_len() == sentinel_none)
  assert_true(pg_last_error() == err_ok)
  assert_true(pg_final_path_at(0) == sentinel_none)
  assert_true(pg_last_error() == err_invalid_argument)
  // error_code 全谱映射。
  assert_true(error_code(SourceNotFound) == err_source_not_found)
  assert_true(error_code(TargetNotFound) == err_target_not_found)
  assert_true(error_code(Unreachable) == err_unreachable)
  assert_true(error_code(NegativeCycle) == err_negative_cycle)
  assert_true(error_code(InvalidArgument("x")) == err_invalid_argument)
  // 非法 reset / 越界障碍 / 起终点重叠。
  assert_true(pg_reset(0, 3) == err_invalid_argument)
  assert_true(pg_reset(3, 3) == err_ok)
  assert_true(pg_set_obstacle(99, 1) == err_invalid_argument)
  assert_true(pg_set_start(0) == err_ok)
  assert_true(pg_set_goal(0) == err_invalid_argument)
}
