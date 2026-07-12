// 黑盒测试：覆盖率审计收口（INFRA 第六十五批）——
// 障碍设置幂等成功路与步进边界读取成功臂。

///|
test "pg_set_obstacle：目标状态已满足时幂等成功" {
  assert_eq(@playground.pg_reset(3, 3), 0)
  assert_eq(@playground.pg_set_obstacle(4, 1), 0)
  assert_eq(@playground.pg_set_obstacle(4, 1), 0)
  assert_eq(@playground.pg_set_obstacle(4, 0), 0)
  assert_eq(@playground.pg_set_obstacle(4, 0), 0)
  assert_eq(@playground.pg_last_error(), 0)
}

///|
test "pg_step_frontier_at：合法步与下标读取成功" {
  assert_eq(@playground.pg_reset(3, 3), 0)
  assert_eq(@playground.pg_set_start(0), 0)
  assert_eq(@playground.pg_set_goal(8), 0)
  let steps = @playground.pg_compute()
  assert_true(steps >= 1)
  let mut hit = false
  for s in 0..<steps {
    if @playground.pg_step_frontier_len(s) >= 1 {
      assert_true(@playground.pg_step_frontier_at(s, 0) >= 0)
      hit = true
      break
    }
  }
  assert_true(hit)
  assert_eq(@playground.pg_last_error(), 0)
}
