// priority_sched_test.mbt —— PrioritySched 黑盒测试：定向（优先级序/级内
// FIFO/位图边界）+ 与朴素参照差分 PBT + 确定性 trace 重放。

///|
test "priority sched basic: strict priority order, FIFO within level" {
  let s : @infra_timer.PrioritySched[String] = @infra_timer.PrioritySched::new()
  assert_true(s.is_empty())
  assert_true(s.pick_next() is None)
  assert_true(s.peek_priority() is None)
  s.enqueue(5, "e")
  s.enqueue(1, "a")
  s.enqueue(5, "f")
  s.enqueue(0, "z")
  s.enqueue(1, "b")
  assert_eq(s.len(), 5)
  assert_true(s.peek_priority() == Some(0))
  assert_true(s.pick_next() == Some((0, "z")))
  assert_true(s.pick_next() == Some((1, "a")))
  assert_true(s.pick_next() == Some((1, "b")))
  assert_true(s.pick_next() == Some((5, "e")))
  assert_true(s.pick_next() == Some((5, "f")))
  assert_true(s.pick_next() is None)
  assert_true(s.is_empty())
}

///|
test "priority sched: boundary priorities 0/63 and clamping" {
  let s : @infra_timer.PrioritySched[Int] = @infra_timer.PrioritySched::new()
  s.enqueue(63, 1)
  s.enqueue(0, 2)
  s.enqueue(100, 3) // 夹取到 63
  s.enqueue(-7, 4) // 夹取到 0
  assert_true(s.pick_next() == Some((0, 2)))
  assert_true(s.pick_next() == Some((0, 4)))
  assert_true(s.pick_next() == Some((63, 1)))
  assert_true(s.pick_next() == Some((63, 3)))
}

///|
test "priority sched: interleaved enqueue/dequeue keeps invariants" {
  let s : @infra_timer.PrioritySched[Int] = @infra_timer.PrioritySched::new()
  // 排空一级后重新入队，位图应正确翻转。
  s.enqueue(7, 1)
  assert_true(s.pick_next() == Some((7, 1)))
  assert_true(s.peek_priority() is None)
  s.enqueue(7, 2)
  assert_true(s.peek_priority() == Some(7))
  assert_true(s.pick_next() == Some((7, 2)))
  // 大量同级循环（环形缓冲回绕）。
  for round in 0..<50 {
    for i in 0..<17 {
      s.enqueue(3, round * 100 + i)
    }
    for i in 0..<17 {
      assert_true(s.pick_next() == Some((3, round * 100 + i)))
    }
  }
  assert_true(s.is_empty())
}

///|
test "priority sched differential PBT vs naive reference (200 iterations)" {
  let rng = @infra_pbt.rng_new(0xE4_5C4EDUL)
  for _iter in 0..<200 {
    let s : @infra_timer.PrioritySched[Int] = @infra_timer.PrioritySched::new()
    // 朴素参照：(prio, seq, task) 数组，pop = 最小 prio 中最小 seq。
    let live : Array[(Int, Int, Int)] = []
    let mut seq = 0
    let steps = 5 + rng.next_below(80)
    for step in 0..<steps {
      if live.length() == 0 || rng.next_below(3) < 2 {
        let p = rng.next_below(64)
        s.enqueue(p, step)
        live.push((p, seq, step))
        seq = seq + 1
      } else {
        // 参照挑选：最小 prio、同级最小 seq。
        let mut best = 0
        for j in 1..<live.length() {
          let (bp, bs, _) = live[best]
          let (jp, js, _) = live[j]
          if jp < bp || (jp == bp && js < bs) {
            best = j
          }
        }
        let (bp, _, bt) = live[best]
        let _ = live.remove(best)
        assert_true(s.pick_next() == Some((bp, bt)))
      }
      assert_eq(s.len(), live.length())
      // peek 与参照最小 prio 一致。
      if live.length() > 0 {
        let mut minp = 64
        for e in live {
          if e.0 < minp {
            minp = e.0
          }
        }
        assert_true(s.peek_priority() == Some(minp))
      } else {
        assert_true(s.peek_priority() is None)
      }
    }
  }
}

///|
test "priority sched: deterministic trace replay (same ops => identical trace)" {
  fn run(seed : UInt64) -> Array[(Int, Int)] {
    let rng = @infra_pbt.rng_new(seed)
    let s : @infra_timer.PrioritySched[Int] = @infra_timer.PrioritySched::new()
    let trace : Array[(Int, Int)] = []
    for step in 0..<500 {
      if s.is_empty() || rng.next_below(3) < 2 {
        s.enqueue(rng.next_below(64), step)
      } else {
        match s.pick_next() {
          Some(pt) => trace.push(pt)
          None => ()
        }
      }
    }
    while true {
      match s.pick_next() {
        Some(pt) => trace.push(pt)
        None => break
      }
    }
    trace
  }

  let t1 = run(0xABCDEFUL)
  let t2 = run(0xABCDEFUL)
  assert_eq(t1.length(), t2.length())
  for i in 0..<t1.length() {
    assert_true(t1[i] == t2[i])
  }
}
