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
