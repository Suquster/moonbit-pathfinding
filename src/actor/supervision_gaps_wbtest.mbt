// 白盒测试：覆盖率审计收口（INFRA 第六十三批）——
// 重启时刻窗口修剪：非正窗口早退与过半陈旧一次性压缩。

///|
test "prune_restart_times：非正窗口不修剪" {
  let times = [1, 2, 3]
  prune_restart_times(times, 100, 0)
  assert_true(times == [1, 2, 3])
}

///|
test "prune_restart_times：过半陈旧一次性压缩仅留窗口内时刻" {
  let times : Array[Int] = []
  for _ in 0..<128 {
    times.push(1)
  }
  times.push(995)
  times.push(996)
  prune_restart_times(times, 1000, 10)
  assert_true(times == [995, 996])
}
