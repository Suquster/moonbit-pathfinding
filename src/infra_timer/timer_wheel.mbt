// timer_wheel.mbt —— E4 层级定时器轮（Hierarchical Timing Wheel）。
//
// paper-to-code：Varghese & Lauck. *Hashed and Hierarchical Timing Wheels:
// Data Structures for the Efficient Implementation of a Timer Facility.*
// SOSP 1987（Linux 内核 timer wheel / Netty HashedWheelTimer 底层模型）。
//
// LEVELS 级轮，每级 WHEEL_SIZE 个槽：定时器按到期绝对 tick 落入「最低能容纳其
// 剩余延迟」的层。时钟每前进一 tick 触发第 0 层当前槽；当第 0 层回绕即把更高层
// 的当前槽 cascade（降级重插）到更低层——insert/cancel/expire 摊销 O(1)（对比
// 朴素每 tick O(n) 扫描全部定时器）。
//
// 单线程确定性：`advance` 明确返回本 tick 到期（未取消）的 id 序列，同操作序列
// 逐 tick 可复现，满足 DST/PBT 证据链。
//
// 对外 API：new / now / pending / schedule / cancel / advance / advance_by。

///|
const WHEEL_BITS : Int = 6

///|
const WHEEL_SIZE : Int = 64

///|
const WHEEL_MASK : Int = 63

///|
const TIMER_LEVELS : Int = 5

///|
struct TimerEntry {
  expiry : Int
  mut cancelled : Bool
  mut active : Bool
}

///|
/// 层级定时器轮。`wheels[level][slot]` 为该槽挂载的定时器 id 列表（FIFO）。
pub struct TimerWheel {
  wheels : Array[Array[Array[Int]]]
  entries : Array[TimerEntry]
  mut current_tick : Int
  mut active_count : Int
}

///|
/// 空定时器轮（时钟起点 tick=0）。
pub fn TimerWheel::new() -> TimerWheel {
  let wheels : Array[Array[Array[Int]]] = []
  for _lvl in 0..<TIMER_LEVELS {
    let slots : Array[Array[Int]] = []
    for _s in 0..<WHEEL_SIZE {
      slots.push([])
    }
    wheels.push(slots)
  }
  { wheels, entries: [], current_tick: 0, active_count: 0 }
}

///|
/// 当前时钟 tick。
pub fn TimerWheel::now(self : TimerWheel) -> Int {
  self.current_tick
}

///|
/// 尚未触发且未取消的定时器个数。
pub fn TimerWheel::pending(self : TimerWheel) -> Int {
  self.active_count
}

///|
/// 依剩余延迟把定时器 id 落到合适层的槽。
fn TimerWheel::place(self : TimerWheel, id : Int, expiry : Int) -> Unit {
  let d = expiry - self.current_tick
  let mut level = 0
  while level < TIMER_LEVELS {
    // 该层可容纳的最大剩余延迟 = WHEEL_SIZE^(level+1)。
    let capacity = 1 << (WHEEL_BITS * (level + 1))
    if d < capacity || level == TIMER_LEVELS - 1 {
      let slot = (expiry >> (WHEEL_BITS * level)) & WHEEL_MASK
      self.wheels[level][slot].push(id)
      return
    }
    level = level + 1
  }
}

///|
/// 注册延迟 `delay`（tick 数，`<1` 归一到 1）触发的定时器；返回其 id。
pub fn TimerWheel::schedule(self : TimerWheel, delay : Int) -> Int {
  let d = if delay < 1 { 1 } else { delay }
  let expiry = self.current_tick + d
  let id = self.entries.length()
  self.entries.push({ expiry, cancelled: false, active: true })
  self.active_count = self.active_count + 1
  self.place(id, expiry)
  id
}

///|
/// 取消定时器（幂等，O(1) 打标记）；返回是否确实取消了一个未触发定时器。
pub fn TimerWheel::cancel(self : TimerWheel, id : Int) -> Bool {
  if id < 0 || id >= self.entries.length() {
    return false
  }
  let e = self.entries[id]
  if e.cancelled || !e.active {
    return false
  }
  e.cancelled = true
  e.active = false
  self.active_count = self.active_count - 1
  true
}

///|
/// 把 `wheels[level][slot]` 的定时器降级重插到更低层（时钟前进后剩余延迟变小）。
fn TimerWheel::cascade(self : TimerWheel, level : Int, slot : Int) -> Unit {
  let bucket = self.wheels[level][slot]
  self.wheels[level][slot] = []
  for id in bucket {
    let e = self.entries[id]
    if !e.cancelled && e.active {
      self.place(id, e.expiry)
    }
  }
}

///|
/// 时钟前进一 tick；返回本 tick 到期（未取消）的定时器 id 序列。
pub fn TimerWheel::advance(self : TimerWheel) -> Array[Int] {
  self.current_tick = self.current_tick + 1
  let idx0 = self.current_tick & WHEEL_MASK
  // 第 0 层回绕：逐级 cascade 高层当前槽，直到某级不回绕。
  if idx0 == 0 {
    let mut level = 1
    while level < TIMER_LEVELS {
      let cidx = (self.current_tick >> (WHEEL_BITS * level)) & WHEEL_MASK
      self.cascade(level, cidx)
      if cidx != 0 {
        break
      }
      level = level + 1
    }
  }
  let fired : Array[Int] = []
  let bucket = self.wheels[0][idx0]
  self.wheels[0][idx0] = []
  for id in bucket {
    let e = self.entries[id]
    if !e.cancelled && e.active {
      e.active = false
      self.active_count = self.active_count - 1
      fired.push(id)
    }
  }
  fired
}

///|
/// 时钟前进 `ticks` 个 tick，累积返回期间所有触发的定时器 id（按 tick 升序、
/// 同 tick 内按轮内顺序）。
pub fn TimerWheel::advance_by(self : TimerWheel, ticks : Int) -> Array[Int] {
  let all : Array[Int] = []
  for _ in 0..<ticks {
    for id in self.advance() {
      all.push(id)
    }
  }
  all
}
