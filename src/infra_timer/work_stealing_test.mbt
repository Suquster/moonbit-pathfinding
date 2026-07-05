// work_stealing_test.mbt —— WorkDeque / WorkStealingScheduler 黑盒测试：
// 定向（LIFO/FIFO 两端语义、环形增长）+ 调度不变量 PBT（无丢失无重复、
// 同输入 trace 逐位一致确定性重放）。

///|
test "work deque: owner LIFO / thief FIFO / growth" {
  let d : @infra_timer.WorkDeque[Int] = @infra_timer.WorkDeque::new()
  assert_eq(d.size(), 0)
  assert_true(d.pop() == None)
  assert_true(d.steal() == None)
  // 压入 100（超过初始容量 8，触发多次倍增）。
  for i in 0..<100 {
    d.push(i)
  }
  assert_eq(d.size(), 100)
  // thief 端窃取最旧。
  assert_true(d.steal() == Some(0))
  assert_true(d.steal() == Some(1))
  // owner 端弹出最新。
  assert_true(d.pop() == Some(99))
  assert_true(d.pop() == Some(98))
  assert_eq(d.size(), 96)
  // 清空后两端都取不到。
  for _ in 0..<96 {
    let _ = d.pop()
  }
  assert_true(d.pop() == None)
  assert_true(d.steal() == None)
  assert_eq(d.size(), 0)
}

///|
test "work stealing: idle workers steal from busy one" {
  let s = @infra_timer.WorkStealingScheduler::new(4)
  // 全部根任务堆在 worker 0，各派生 3 个子任务。
  for _ in 0..<20 {
    let _ = s.submit(0, 3)
  }
  let trace = s.run()
  // 20 根 + 60 子 = 80 个任务全部执行。
  assert_eq(trace.length(), 80)
  // 发生了窃取（其它 worker 分担了负载）。
  assert_true(s.steal_count() > 0)
  let mut nonzero_workers = 0
  for w in 0..<4 {
    let mut cnt = 0
    for e in trace {
      if e.0 == w {
        cnt = cnt + 1
      }
    }
    if cnt > 0 {
      nonzero_workers = nonzero_workers + 1
    }
  }
  assert_true(nonzero_workers >= 2)
}

///|
test "E4 property: work stealing loses/dups nothing + deterministic replay (120 iters)" {
  let rng = @infra_pbt.rng_new(20260710)
  for _iter in 0..<120 {
    let workers = 1 + rng.next_below(6)
    let roots = 1 + rng.next_below(40)
    let plan : Array[(Int, Int)] = []
    for _ in 0..<roots {
      plan.push((rng.next_below(workers), rng.next_below(5)))
    }
    let run_once = fn() {
      let s = @infra_timer.WorkStealingScheduler::new(workers)
      let mut expected = 0
      for p in plan {
        let _ = s.submit(p.0, p.1)
        expected = expected + 1 + p.1
      }
      (s.run(), expected)
    }
    let (t1, expected) = run_once()
    // 无丢失无重复：执行的 task_id 排序后 = 0..expected-1。
    assert_eq(t1.length(), expected)
    let ids : Array[Int] = []
    for e in t1 {
      ids.push(e.1)
    }
    ids.sort()
    for i in 0..<expected {
      assert_eq(ids[i], i)
    }
    // 确定性重放：同输入 trace 逐位一致。
    let (t2, _) = run_once()
    assert_eq(t1.length(), t2.length())
    for i in 0..<t1.length() {
      assert_eq(t1[i].0, t2[i].0)
      assert_eq(t1[i].1, t2[i].1)
    }
  }
}
