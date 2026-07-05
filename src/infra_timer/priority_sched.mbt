// priority_sched.mbt —— E4 并发调度深化：O(1) 位图优先级就绪队列。
//
// paper-to-code：对标 Linux O(1) 调度器（Ingo Molnar, 2002）就绪队列设计：
// 64 级优先级（0 最高），每级一条 FIFO 就绪链 + 一个 64 位占用位图；
// `pick_next` 用 find-first-set 定位最高非空优先级，enqueue/dequeue 均
// 严格 O(1)（与就绪任务数无关），同级任务 FIFO 轮转保证级内公平与
// 确定性 trace 重放。
//
// find-first-set 用 de Bruijn 乘法常数步实现（Leiserson, Prokop & Randall.
// *Using de Bruijn Sequences to Index a 1 in a Computer Word.* 1998）。
//
// 对外 API：PrioritySched::new / len / is_empty / enqueue / pick_next /
// peek_priority。

///|
/// 优先级数（0 = 最高，PRIO_LEVELS-1 = 最低）。
pub const PRIO_LEVELS : Int = 64

///|
/// 单级 FIFO 就绪链：环形缓冲，摊销 O(1) push/pop。
struct PrioQueue[T] {
  mut buf : Array[T?]
  mut head : Int
  mut count : Int
}

///|
fn[T] PrioQueue::new() -> PrioQueue[T] {
  { buf: [], head: 0, count: 0 }
}

///|
fn[T] PrioQueue::push(self : PrioQueue[T], v : T) -> Unit {
  let cap = self.buf.length()
  if self.count == cap {
    // 扩容：按 FIFO 序重排到 2 倍新缓冲（至少 8）。
    let ncap = if cap < 4 { 8 } else { cap * 2 }
    let nbuf : Array[T?] = Array::make(ncap, None)
    for i in 0..<self.count {
      nbuf[i] = self.buf[(self.head + i) % (if cap == 0 { 1 } else { cap })]
    }
    self.buf = nbuf
    self.head = 0
  }
  let cap2 = self.buf.length()
  self.buf[(self.head + self.count) % cap2] = Some(v)
  self.count = self.count + 1
}

///|
fn[T] PrioQueue::pop(self : PrioQueue[T]) -> T? {
  if self.count == 0 {
    return None
  }
  let v = self.buf[self.head]
  self.buf[self.head] = None
  self.head = (self.head + 1) % self.buf.length()
  self.count = self.count - 1
  v
}

///|
/// de Bruijn 序列常数：64 位 find-first-set。
const DEBRUIJN64 : UInt64 = 0x03F79D71B4CB0A89UL

///|
let debruijn_table : Array[Int] = [
  0, 1, 48, 2, 57, 49, 28, 3, 61, 58, 50, 42, 38, 29, 17, 4, 62, 55, 59, 36, 53,
  51, 43, 22, 45, 39, 33, 30, 24, 18, 12, 5, 63, 47, 56, 27, 60, 41, 37, 16, 54,
  35, 52, 21, 44, 32, 23, 11, 46, 26, 40, 15, 34, 20, 31, 10, 25, 14, 19, 9, 13,
  8, 7, 6,
]

///|
/// 最低置位位下标（x != 0）。常数步。
fn ctz64(x : UInt64) -> Int {
  debruijn_table[(((x & (x ^ (x - 1UL))) * DEBRUIJN64) >> 58).to_int()]
}

///|
/// O(1) 位图优先级就绪队列。
pub struct PrioritySched[T] {
  queues : Array[PrioQueue[T]]
  mut bitmap : UInt64
  mut total : Int
}

///|
/// 空调度器（64 级优先级）。
pub fn[T] PrioritySched::new() -> PrioritySched[T] {
  let queues : Array[PrioQueue[T]] = []
  for _ in 0..<PRIO_LEVELS {
    queues.push(PrioQueue::new())
  }
  { queues, bitmap: 0UL, total: 0 }
}

///|
/// 就绪任务总数。
pub fn[T] PrioritySched::len(self : PrioritySched[T]) -> Int {
  self.total
}

///|
pub fn[T] PrioritySched::is_empty(self : PrioritySched[T]) -> Bool {
  self.total == 0
}

///|
/// 以优先级 prio（0 最高；越界夹取）入队。O(1)。
pub fn[T] PrioritySched::enqueue(
  self : PrioritySched[T],
  prio : Int,
  task : T,
) -> Unit {
  let p = if prio < 0 {
    0
  } else if prio >= PRIO_LEVELS {
    PRIO_LEVELS - 1
  } else {
    prio
  }
  self.queues[p].push(task)
  self.bitmap = self.bitmap | (1UL << p)
  self.total = self.total + 1
}

///|
/// 当前最高非空优先级（空返回 None）。O(1)。
pub fn[T] PrioritySched::peek_priority(self : PrioritySched[T]) -> Int? {
  if self.bitmap == 0UL {
    None
  } else {
    Some(ctz64(self.bitmap))
  }
}

///|
/// 取出最高优先级中最早入队的任务（级内 FIFO）。O(1)。
pub fn[T] PrioritySched::pick_next(self : PrioritySched[T]) -> (Int, T)? {
  if self.bitmap == 0UL {
    return None
  }
  let p = ctz64(self.bitmap)
  let q = self.queues[p]
  match q.pop() {
    None => None // 位图不变量下不可达
    Some(task) => {
      if q.count == 0 {
        self.bitmap = self.bitmap & ((1UL << p) ^ 0xFFFFFFFFFFFFFFFFUL)
      }
      self.total = self.total - 1
      Some((p, task))
    }
  }
}
