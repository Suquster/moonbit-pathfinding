// timer_wheel_test.mbt —— TimerWheel 黑盒测试：定向（跨层 cascade/取消/边界）
// + 与朴素 O(n) 扫描定时器的差分 PBT（同操作序列逐 tick 到期集合一致）。

///|
test "timer basic schedule/advance within level 0" {
  let w = @infra_timer.TimerWheel::new()
  let a = w.schedule(1)
  let b = w.schedule(3)
  assert_eq(w.pending(), 2)
  assert_eq(w.now(), 0)
  // tick 1：a 到期。
  let f1 = w.advance()
  assert_eq(f1.length(), 1)
  assert_eq(f1[0], a)
  assert_eq(w.now(), 1)
  assert_eq(w.pending(), 1)
  // tick 2：无。
  assert_eq(w.advance().length(), 0)
  // tick 3：b 到期。
  let f3 = w.advance()
  assert_eq(f3.length(), 1)
  assert_eq(f3[0], b)
  assert_eq(w.pending(), 0)
}

///|
test "timer cascade across levels (delay > wheel size)" {
  let w = @infra_timer.TimerWheel::new()
  // 64/65/200 均跨第 0 层（size=64），需 cascade 到第 0 层再触发。
  let x = w.schedule(64)
  let y = w.schedule(65)
  let z = w.schedule(200)
  let fired = w.advance_by(199)
  // 199 tick 内 x、y 已触发，z（tick200）未触发。
  assert_true(fired.contains(x))
  assert_true(fired.contains(y))
  assert_true(fired.contains(z) == false)
  assert_eq(w.pending(), 1)
  // 精确落点。
  let more = w.advance()
  assert_eq(more.length(), 1)
  assert_eq(more[0], z)
  assert_eq(w.now(), 200)
}

///|
test "timer cancel: before fire (incl. across cascade)" {
  let w = @infra_timer.TimerWheel::new()
  let a = w.schedule(10)
  let b = w.schedule(130) // 跨两层
  assert_true(w.cancel(a))
  assert_true(w.cancel(a) == false) // 幂等
  assert_eq(w.pending(), 1)
  // a 已取消，前进不触发它。
  let f = w.advance_by(130)
  assert_true(f.contains(a) == false)
  assert_true(f.contains(b))
  // 已触发的不能再取消。
  assert_true(w.cancel(b) == false)
  assert_eq(w.pending(), 0)
}

///|
/// 朴素参照定时器：每 tick 扫描全部条目 O(n)。
struct NaiveTimers {
  expiry : Array[Int]
  cancelled : Array[Bool]
  fired : Array[Bool]
  mut tick : Int
}

///|
fn NaiveTimers::new() -> NaiveTimers {
  { expiry: [], cancelled: [], fired: [], tick: 0 }
}

///|
fn NaiveTimers::schedule(self : NaiveTimers, delay : Int) -> Int {
  let d = if delay < 1 { 1 } else { delay }
  let id = self.expiry.length()
  self.expiry.push(self.tick + d)
  self.cancelled.push(false)
  self.fired.push(false)
  id
}

///|
fn NaiveTimers::cancel(self : NaiveTimers, id : Int) -> Bool {
  if id < 0 || id >= self.expiry.length() {
    return false
  }
  if self.cancelled[id] || self.fired[id] {
    return false
  }
  self.cancelled[id] = true
  true
}

///|
fn NaiveTimers::advance(self : NaiveTimers) -> Array[Int] {
  self.tick = self.tick + 1
  let out : Array[Int] = []
  for id in 0..<self.expiry.length() {
    if !self.cancelled[id] && !self.fired[id] && self.expiry[id] == self.tick {
      self.fired[id] = true
      out.push(id)
    }
  }
  out
}

///|
fn NaiveTimers::pending(self : NaiveTimers) -> Int {
  let mut n = 0
  for id in 0..<self.expiry.length() {
    if !self.cancelled[id] && !self.fired[id] {
      n = n + 1
    }
  }
  n
}

///|
test "E4 property: timer wheel ≡ naive O(n) timers (200 iters)" {
  let rng = @infra_pbt.rng_new(20260709)
  for _iter in 0..<200 {
    let w = @infra_timer.TimerWheel::new()
    let ref_t = NaiveTimers::new()
    let rounds = 40 + rng.next_below(60)
    for _ in 0..<rounds {
      let dice = rng.next_below(10)
      if dice < 5 {
        // schedule：延迟 1..~5000（覆盖多层 cascade）。
        let delay = 1 + rng.next_below(5000)
        let id1 = w.schedule(delay)
        let id2 = ref_t.schedule(delay)
        assert_eq(id1, id2)
      } else if dice < 7 {
        // cancel 一个已存在 id。
        let n = ref_t.expiry.length()
        if n > 0 {
          let id = rng.next_below(n)
          assert_true(w.cancel(id) == ref_t.cancel(id))
        }
      } else {
        // advance 若干 tick，逐 tick 到期集合（排序后）一致。
        let steps = 1 + rng.next_below(400)
        for _ in 0..<steps {
          let fa = w.advance()
          let fb = ref_t.advance()
          let sa = fa.copy()
          let sb = fb.copy()
          sa.sort()
          sb.sort()
          assert_eq(sa.length(), sb.length())
          for k in 0..<sa.length() {
            assert_eq(sa[k], sb[k])
          }
        }
        assert_eq(w.now(), ref_t.tick)
        assert_eq(w.pending(), ref_t.pending())
      }
    }
  }
}
