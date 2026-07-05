// work_stealing.mbt —— E4 工作窃取双端队列 + 确定性调度器建模。
//
// paper-to-code：Chase & Lev. *Dynamic Circular Work-Stealing Deque.*
// SPAA 2005（Tokio/Rayon/Cilk 调度器底层结构）。owner 在底端 push/pop
// （LIFO，缓存亲和），thief 在顶端 steal（FIFO，窃取最旧任务），环形缓冲
// 按需倍增——全部操作摊销 O(1)。
//
// 单线程确定性建模：不含原子操作，保留 Chase-Lev 的 top/bottom 索引 + 环形
// 增长结构；`WorkStealingScheduler` 以确定轮转驱动 n 个 worker（本地 pop、
// 空则按固定顺序窃取），同输入产生逐位一致的执行 trace（DST 前提）。

///|
/// Chase-Lev 双端队列（环形缓冲，容量按需倍增）。
pub struct WorkDeque[T] {
  mut buf : Array[T?]
  mut top : Int
  mut bottom : Int
}

///|
/// 空队列（初始容量 8）。
pub fn[T] WorkDeque::new() -> WorkDeque[T] {
  { buf: Array::make(8, None), top: 0, bottom: 0 }
}

///|
/// 当前任务数。
pub fn[T] WorkDeque::size(self : WorkDeque[T]) -> Int {
  self.bottom - self.top
}

///|
/// 环形缓冲倍增（保留 [top, bottom) 的逻辑位置）。
fn[T] WorkDeque::grow(self : WorkDeque[T]) -> Unit {
  let old = self.buf
  let cap = old.length()
  let next : Array[T?] = Array::make(cap * 2, None)
  for i in self.top..<self.bottom {
    next[i % (cap * 2)] = old[i % cap]
  }
  self.buf = next
}

///|
/// owner 端：底端压入（摊销 O(1)）。
pub fn[T] WorkDeque::push(self : WorkDeque[T], v : T) -> Unit {
  if self.bottom - self.top >= self.buf.length() {
    self.grow()
  }
  self.buf[self.bottom % self.buf.length()] = Some(v)
  self.bottom = self.bottom + 1
}

///|
/// owner 端：底端弹出（LIFO，O(1)）。
pub fn[T] WorkDeque::pop(self : WorkDeque[T]) -> T? {
  if self.bottom <= self.top {
    return None
  }
  self.bottom = self.bottom - 1
  let idx = self.bottom % self.buf.length()
  let v = self.buf[idx]
  self.buf[idx] = None
  v
}

///|
/// thief 端：顶端窃取最旧任务（FIFO，O(1)）。
pub fn[T] WorkDeque::steal(self : WorkDeque[T]) -> T? {
  if self.top >= self.bottom {
    return None
  }
  let idx = self.top % self.buf.length()
  let v = self.buf[idx]
  self.buf[idx] = None
  self.top = self.top + 1
  v
}

///|
/// 待执行任务：id + 展开出的子任务数（建模 fork-join 任务树）。
pub struct WsTask {
  id : Int
  spawn_count : Int
}

///|
/// 确定性工作窃取调度器：n 个 worker 轮转驱动，空闲即按固定顺序窃取。
pub struct WorkStealingScheduler {
  deques : Array[WorkDeque[WsTask]]
  mut next_id : Int
  /// 每个任务再派生子任务的数量由外部注入函数决定前的静态描述。
  executed : Array[Int]
  mut steals : Int
}

///|
/// n 个 worker 的调度器。
pub fn WorkStealingScheduler::new(workers : Int) -> WorkStealingScheduler {
  let n = if workers < 1 { 1 } else { workers }
  let deques : Array[WorkDeque[WsTask]] = []
  for _ in 0..<n {
    deques.push(WorkDeque::new())
  }
  { deques, next_id: 0, executed: [], steals: 0 }
}

///|
/// worker 数。
pub fn WorkStealingScheduler::workers(self : WorkStealingScheduler) -> Int {
  self.deques.length()
}

///|
/// 累计窃取次数（负载迁移量度）。
pub fn WorkStealingScheduler::steal_count(self : WorkStealingScheduler) -> Int {
  self.steals
}

///|
/// 向指定 worker 提交根任务；spawn_count 为其执行时派生的子任务数。
pub fn WorkStealingScheduler::submit(
  self : WorkStealingScheduler,
  worker : Int,
  spawn_count : Int,
) -> Int {
  let id = self.next_id
  self.next_id = self.next_id + 1
  self.deques[worker % self.deques.length()].push({ id, spawn_count })
  id
}

///|
/// 确定性轮转执行至全部任务完成；返回执行 trace（(worker, task_id) 序列）。
/// 每轮各 worker 依次执行一个任务：优先本地 pop（LIFO），空则从
/// (self+1..self+n-1) 固定顺序窃取（FIFO）。任务执行时派生
/// spawn_count 个子任务（子任务不再派生），压入执行者本地队列。
pub fn WorkStealingScheduler::run(
  self : WorkStealingScheduler,
) -> Array[(Int, Int)] {
  let n = self.deques.length()
  let trace : Array[(Int, Int)] = []
  let mut idle_rounds = 0
  while idle_rounds < 1 {
    let mut any = false
    for w in 0..<n {
      let task = match self.deques[w].pop() {
        Some(t) => Some(t)
        None => {
          // 确定顺序窃取。
          let mut got : WsTask? = None
          for k in 1..<n {
            let victim = (w + k) % n
            match self.deques[victim].steal() {
              Some(t) => {
                self.steals = self.steals + 1
                got = Some(t)
                break
              }
              None => ()
            }
          }
          got
        }
      }
      match task {
        Some(t) => {
          any = true
          trace.push((w, t.id))
          self.executed.push(t.id)
          for _ in 0..<t.spawn_count {
            let cid = self.next_id
            self.next_id = self.next_id + 1
            self.deques[w].push({ id: cid, spawn_count: 0 })
          }
        }
        None => ()
      }
    }
    if any {
      idle_rounds = 0
    } else {
      idle_rounds = idle_rounds + 1
    }
  }
  trace
}
