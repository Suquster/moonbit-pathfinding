// benches/infra_timer_bench — E4 层级定时器轮 vs 朴素扫描的吞吐基准。
//
// 负载：n 个定时器随机延迟 ∈ [1, 4096]（覆盖多层 cascade），时钟推进 4096 tick
// 至全部触发。timer wheel 每 tick 只碰当前槽（摊销 O(1)/定时器）；朴素实现每
// tick 扫描全部 n 条 O(n)，总量 O(n·T)。确定性 xorshift 负载保证可复现。

///|
fn xorshift(x : UInt64) -> UInt64 {
  let mut v = x
  v = v ^ (v << 13)
  v = v ^ (v >> 7)
  v = v ^ (v << 17)
  v
}

///|
fn make_delays(n : Int, seed : UInt64) -> Array[Int] {
  let out : Array[Int] = []
  let mut s = seed
  for _ in 0..<n {
    s = xorshift(s)
    out.push(1 + (s % 4096UL).to_int())
  }
  out
}

///|
test "bench: timer wheel vs naive scan (n=1000/4000/16000)" (b : @bench.T) {
  for n in [1000, 4000, 16000] {
    let delays = make_delays(n, 20260709UL)
    b.bench(name="timer_wheel_\{n}", fn() {
      let w = @tw.TimerWheel::new()
      for d in delays {
        let _ = w.schedule(d)
      }
      let mut fired = 0
      for _ in 0..<4096 {
        fired = fired + w.advance().length()
      }
      b.keep(fired)
    })
    b.bench(name="naive_scan_\{n}", fn() {
      // 朴素：expiry 数组，每 tick 全扫描。
      let expiry : Array[Int] = []
      let done : Array[Bool] = []
      for d in delays {
        expiry.push(d)
        done.push(false)
      }
      let mut fired = 0
      for t in 1..<=4096 {
        for i in 0..<expiry.length() {
          if !done[i] && expiry[i] == t {
            done[i] = true
            fired = fired + 1
          }
        }
      }
      b.keep(fired)
    })
  }
}

///|
test "bench: priority sched O(1) bitmap vs naive linear scan (churn, live~2048)" (
  b : @bench.T,
) {
  // 稳态 churn：保持 ~2048 就绪任务，交替 enqueue（2/3）/pick_next（1/3），
  // 共 n 次操作。位图调度 O(1)/操作；朴素参照每次 pick 线性扫描全部就绪。
  for n in [32000, 128000] {
    b.bench(name="prio_sched_bitmap_\{n}", fn() {
      let s : @tw.PrioritySched[Int] = @tw.PrioritySched::new()
      let mut acc = 0
      let mut seed = 20260712UL
      for i in 0..<n {
        seed = xorshift(seed)
        if s.len() < 2048 && (s.is_empty() || seed % 3UL != 0UL) {
          s.enqueue((seed % 64UL).to_int(), i)
        } else {
          match s.pick_next() {
            Some((p, t)) => acc = acc + p + t
            None => ()
          }
        }
      }
      b.keep(acc)
    })
    b.bench(name="naive_linear_scan_\{n}", fn() {
      let live : Array[(Int, Int, Int)] = []
      let mut acc = 0
      let mut seq = 0
      let mut seed = 20260712UL
      for i in 0..<n {
        seed = xorshift(seed)
        if live.length() < 2048 && (live.length() == 0 || seed % 3UL != 0UL) {
          live.push(((seed % 64UL).to_int(), seq, i))
          seq = seq + 1
        } else {
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
          acc = acc + bp + bt
        }
      }
      b.keep(acc)
    })
  }
}

///|
test "bench: work deque vs naive array queue (mixed push/pop/steal)" (
  b : @bench.T,
) {
  for n in [4000, 16000, 64000] {
    b.bench(name="work_deque_mixed_\{n}", fn() {
      let d : @tw.WorkDeque[Int] = @tw.WorkDeque::new()
      let mut acc = 0
      let mut s = 20260710UL
      for i in 0..<n {
        d.push(i)
        s = xorshift(s)
        // 1/2 概率 owner pop，1/4 概率 thief steal。
        if (s & 1UL) == 0UL {
          match d.pop() {
            Some(v) => acc = acc + v
            None => ()
          }
        } else if (s & 2UL) == 0UL {
          match d.steal() {
            Some(v) => acc = acc + v
            None => ()
          }
        }
      }
      while d.size() > 0 {
        match d.steal() {
          Some(v) => acc = acc + v
          None => ()
        }
      }
      b.keep(acc)
    })
    b.bench(name="naive_array_queue_\{n}", fn() {
      let q : Array[Int] = []
      let mut acc = 0
      let mut s = 20260710UL
      for i in 0..<n {
        q.push(i)
        s = xorshift(s)
        if (s & 1UL) == 0UL {
          match q.pop() {
            Some(v) => acc = acc + v
            None => ()
          }
        } else if (s & 2UL) == 0UL {
          if q.length() > 0 {
            acc = acc + q.remove(0) // 头部出队 O(n) 移位
          }
        }
      }
      while q.length() > 0 {
        acc = acc + q.remove(0)
      }
      b.keep(acc)
    })
  }
}
