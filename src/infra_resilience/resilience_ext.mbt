// resilience_ext.mbt —— 韧性补深：Bulkhead / Hedging / 自适应限流。
//
// paper-to-code：
// - Bulkhead（舱壁隔离）：Nygard *Release It!* / resilience4j Bulkhead——
//   并发上限 + 有界等待队列，超限立即拒绝（fail-fast），防止单依赖
//   拖垮全部工作线程；
// - Hedged requests（对冲请求）：Dean & Barroso *The Tail at Scale*
//   （CACM 2013）——首请求超过 p95 级延迟阈值后并行发副本，取先完成者，
//   显著削尾延迟、代价可控（论文报告 ~5% 额外负载削掉 96% 尾延迟）；
//   本实现为确定性调度模型：调用方注入各副本完成时刻，策略给出
//   发射时刻表与胜者判定；
// - AIMD 自适应限流：TCP 拥塞控制同款加性增/乘性减（Chiu & Jain 1989），
//   成功线性加、失败乘性减，收敛到公平稳态。
//
// 与既有组件一致：显式时钟/事件参数，无墙钟，三后端一致。

// ───────────────────────────── Bulkhead ──────────────────────────────────

///|
/// 舱壁隔离：并发上限 + 有界等待队列（resilience4j 语义）。
pub struct Bulkhead {
  max_concurrent : Int
  max_queue : Int
  mut in_flight : Int
  mut queued : Int
  mut rejected_total : Int
}

///|
/// 新建舱壁：并发上限 + 等待队列上限。
pub fn Bulkhead::create(max_concurrent : Int, max_queue : Int) -> Bulkhead {
  { max_concurrent, max_queue, in_flight: 0, queued: 0, rejected_total: 0 }
}

///|
/// 准入结果。
pub(all) enum Admission {
  Admitted // 直接执行
  Enqueued // 进入等待队列
  Rejected // 舱满且队满，快速失败
} derive(Eq, Debug)

///|
/// 尝试准入：有空位直接执行；否则若队列未满则排队；再否则拒绝。
pub fn Bulkhead::try_acquire(self : Bulkhead) -> Admission {
  if self.in_flight < self.max_concurrent {
    self.in_flight = self.in_flight + 1
    Admitted
  } else if self.queued < self.max_queue {
    self.queued = self.queued + 1
    Enqueued
  } else {
    self.rejected_total = self.rejected_total + 1
    Rejected
  }
}

///|
/// 完成一次执行：释放舱位；若有排队者立即顶替（返回 true 表示有顶替）。
pub fn Bulkhead::release(self : Bulkhead) -> Bool {
  if self.in_flight > 0 {
    self.in_flight = self.in_flight - 1
  }
  if self.queued > 0 && self.in_flight < self.max_concurrent {
    self.queued = self.queued - 1
    self.in_flight = self.in_flight + 1
    true
  } else {
    false
  }
}

///|
/// 当前在飞数。
pub fn Bulkhead::in_flight_count(self : Bulkhead) -> Int {
  self.in_flight
}

///|
/// 当前排队数。
pub fn Bulkhead::queued_count(self : Bulkhead) -> Int {
  self.queued
}

///|
/// 累计拒绝数。
pub fn Bulkhead::rejected_count(self : Bulkhead) -> Int {
  self.rejected_total
}

// ───────────────────────────── Hedged requests ───────────────────────────

///|
/// 对冲策略：首请求发出后每过 `hedge_after_ms` 追发一个副本，
/// 至多 `max_hedges` 个副本（Dean & Barroso, The Tail at Scale）。
pub(all) struct HedgePolicy {
  hedge_after_ms : Int
  max_hedges : Int
} derive(Eq, Debug)

///|
/// 各请求副本的发射时刻表（相对首发时刻，毫秒）：
/// [0, hedge_after, 2×hedge_after, ...]，共 1 + max_hedges 项。
pub fn hedge_schedule(policy : HedgePolicy) -> Array[Int] {
  let out : Array[Int] = [0]
  for k in 1..<=policy.max_hedges {
    out.push(k * policy.hedge_after_ms)
  }
  out
}

///|
/// 对冲结局：给定每个副本的**单独耗时**（副本 i 从发射到完成的毫秒数），
/// 返回 (胜者下标, 端到端完成时刻, 实际发射的副本数)。
/// 副本 i 的完成时刻 = 发射时刻 + durations[i]；若某副本在下一副本
/// 发射前已完成，后续副本不再发射（真实 hedging 的取消语义）。
pub fn hedge_outcome(
  policy : HedgePolicy,
  durations : Array[Int],
) -> (Int, Int, Int) {
  let schedule = hedge_schedule(policy)
  let n = if durations.length() < schedule.length() {
    durations.length()
  } else {
    schedule.length()
  }
  let mut best_idx = 0
  let mut best_finish = schedule[0] + durations[0]
  let mut launched = 1
  for i in 1..<n {
    // 若已有副本在本副本发射前完成，则不再发射。
    if best_finish <= schedule[i] {
      break
    }
    launched = launched + 1
    let finish = schedule[i] + durations[i]
    if finish < best_finish {
      best_finish = finish
      best_idx = i
    }
  }
  (best_idx, best_finish, launched)
}

// ───────────────────────────── AIMD 自适应限流 ───────────────────────────

///|
/// AIMD 限流器（Chiu & Jain 1989 / TCP 拥塞控制）：
/// 成功 +additive、失败 ×multiplicative（0<m<1，定点千分数表达），
/// 限额夹在 [min_limit, max_limit]。
pub struct AimdLimiter {
  min_limit : Int
  max_limit : Int
  additive : Int
  decrease_permille : Int // 失败后保留千分比（如 500 = 减半）
  mut limit : Int
}

///|
/// 新建 AIMD 限流器（初始限额 + 上下界 + 增减参数）。
pub fn AimdLimiter::create(
  initial : Int,
  min_limit : Int,
  max_limit : Int,
  additive? : Int = 1,
  decrease_permille? : Int = 500,
) -> AimdLimiter {
  { min_limit, max_limit, additive, decrease_permille, limit: initial }
}

///|
/// 当前限额。
pub fn AimdLimiter::current_limit(self : AimdLimiter) -> Int {
  self.limit
}

///|
/// 成功反馈：加性增（封顶 max_limit）。
pub fn AimdLimiter::on_success(self : AimdLimiter) -> Unit {
  let next = self.limit + self.additive
  self.limit = if next > self.max_limit { self.max_limit } else { next }
}

///|
/// 失败/过载反馈：乘性减（保底 min_limit）。
pub fn AimdLimiter::on_overload(self : AimdLimiter) -> Unit {
  let next = self.limit * self.decrease_permille / 1000
  self.limit = if next < self.min_limit { self.min_limit } else { next }
}

// ───────────────────── 滑动窗口错误率熔断（resilience4j COUNT_BASED） ────

///|
/// 计数型滑动窗口错误率熔断器（resilience4j `COUNT_BASED` 语义）：
/// 环形记录最近 `window_size` 次调用结果，样本满 `minimum_calls`
/// 且错误率 ≥ `failure_rate_permille`（千分比）时熔断。
pub struct RateBreaker {
  window_size : Int
  minimum_calls : Int
  failure_rate_permille : Int
  ring : Array[Bool] // true = 失败
  mut count : Int // 已记录样本数（≤ window_size）
  mut head : Int // 下一写入位置
  mut failures : Int // 窗口内失败数
  mut open : Bool
}

///|
/// 新建计数型错误率熔断器。
pub fn RateBreaker::create(
  window_size : Int,
  minimum_calls : Int,
  failure_rate_permille : Int,
) -> RateBreaker {
  {
    window_size,
    minimum_calls,
    failure_rate_permille,
    ring: Array::make(window_size, false),
    count: 0,
    head: 0,
    failures: 0,
    open: false,
  }
}

///|
/// 记录一次调用结果并重估状态；返回记录后是否处于熔断态。
pub fn RateBreaker::record(self : RateBreaker, failed : Bool) -> Bool {
  if self.count == self.window_size {
    // 覆盖最旧样本。
    if self.ring[self.head] {
      self.failures = self.failures - 1
    }
  } else {
    self.count = self.count + 1
  }
  self.ring[self.head] = failed
  if failed {
    self.failures = self.failures + 1
  }
  self.head = (self.head + 1) % self.window_size
  self.open = self.count >= self.minimum_calls &&
    self.failures * 1000 >= self.failure_rate_permille * self.count
  self.open
}

///|
/// 当前是否熔断。
pub fn RateBreaker::is_open(self : RateBreaker) -> Bool {
  self.open
}

///|
/// 窗口内当前错误率（千分比；样本为空返回 0）。
pub fn RateBreaker::failure_rate(self : RateBreaker) -> Int {
  if self.count == 0 {
    0
  } else {
    self.failures * 1000 / self.count
  }
}

// ───────────────────── 时间型滑动窗口错误率熔断（TIME_BASED） ─────────────

///|
/// 时间型滑动窗口错误率熔断器（resilience4j `TIME_BASED` 语义）：
/// 以秒为桶聚合最近 `window_seconds` 秒的调用结果，样本满
/// `minimum_calls` 且错误率 ≥ `failure_rate_permille` 时熔断；
/// 窗口随时间滑动，过期桶整体退出统计（Hystrix rolling window 同族）。
pub struct TimeRateBreaker {
  window_seconds : Int
  minimum_calls : Int
  failure_rate_permille : Int
  bucket_calls : Array[Int] // 每秒桶：调用数
  bucket_failures : Array[Int] // 每秒桶：失败数
  bucket_epoch : Array[Int64] // 桶归属的秒纪元（-1 = 空）
  mut open : Bool
}

///|
/// 新建时间型错误率熔断器。
pub fn TimeRateBreaker::create(
  window_seconds : Int,
  minimum_calls : Int,
  failure_rate_permille : Int,
) -> TimeRateBreaker {
  {
    window_seconds,
    minimum_calls,
    failure_rate_permille,
    bucket_calls: Array::make(window_seconds, 0),
    bucket_failures: Array::make(window_seconds, 0),
    bucket_epoch: Array::make(window_seconds, -1L),
    open: false,
  }
}

///|
/// 记录一次调用结果（`now_ms` 为单调毫秒时钟）并重估状态；
/// 返回记录后是否处于熔断态。
pub fn TimeRateBreaker::record(
  self : TimeRateBreaker,
  now_ms : Int64,
  failed : Bool,
) -> Bool {
  let sec = now_ms / 1000L
  let idx = (sec % self.window_seconds.to_int64()).to_int()
  // 桶过期（属于旧一轮窗口）→ 清零复用。
  if self.bucket_epoch[idx] != sec {
    self.bucket_epoch[idx] = sec
    self.bucket_calls[idx] = 0
    self.bucket_failures[idx] = 0
  }
  self.bucket_calls[idx] = self.bucket_calls[idx] + 1
  if failed {
    self.bucket_failures[idx] = self.bucket_failures[idx] + 1
  }
  self.evaluate(sec)
}

///|
/// 按当前秒纪元统计窗口内样本并重估熔断态。
fn TimeRateBreaker::evaluate(self : TimeRateBreaker, now_sec : Int64) -> Bool {
  let mut calls = 0
  let mut failures = 0
  for i in 0..<self.window_seconds {
    let e = self.bucket_epoch[i]
    if e >= 0L && now_sec - e < self.window_seconds.to_int64() {
      calls = calls + self.bucket_calls[i]
      failures = failures + self.bucket_failures[i]
    }
  }
  self.open = calls >= self.minimum_calls &&
    failures * 1000 >= self.failure_rate_permille * calls
  self.open
}

///|
/// 查询指定时刻的熔断态（不记录新样本，仅按窗口重估）。
pub fn TimeRateBreaker::is_open(self : TimeRateBreaker, now_ms : Int64) -> Bool {
  self.evaluate(now_ms / 1000L)
}

// ───────────────────────── 重试预算（Finagle RetryBudget） ────────────────

///|
/// 重试预算（Twitter Finagle `RetryBudget` 语义）：防重试风暴——
/// 每次正常请求向预算桶存入 `retry_percent_permille`‰ 个令牌，
/// 每次重试消费 1000 个微令牌；另有 `min_retries_per_sec × ttl_seconds`
/// 的保底存款，保证低流量下仍可少量重试。桶容量以 ttl 窗口内
/// 存款上限封顶（Finagle 默认：ttl=10s、retryPercent=20%、minRetriesPerSec=10）。
pub struct RetryBudget {
  retry_percent_permille : Int // 每千次请求可获得的重试数（‰）
  min_deposit_per_sec : Int // 保底：每秒固定存入的重试数
  ttl_seconds : Int
  mut micro_tokens : Int64 // 微令牌（1 次重试 = 1000）
  mut last_tick_sec : Int64
}

///|
/// 新建重试预算（Finagle 默认参数：20%、10/s 保底、10s ttl）。
pub fn RetryBudget::create(
  retry_percent_permille? : Int = 200,
  min_deposit_per_sec? : Int = 10,
  ttl_seconds? : Int = 10,
) -> RetryBudget {
  {
    retry_percent_permille,
    min_deposit_per_sec,
    ttl_seconds,
    // 初始预算 = 一个 ttl 窗口的保底存款。
    micro_tokens: (min_deposit_per_sec * ttl_seconds).to_int64() * 1000L,
    last_tick_sec: 0L,
  }
}

///|
/// 预算上限（微令牌）：一个 ttl 窗口内保底存款的封顶值 ×2
/// （Finagle 实现的滑动窗口近似）；下限保证纯比例模式（无保底）
/// 仍可积累至少 10 次重试的余量。
fn RetryBudget::cap(self : RetryBudget) -> Int64 {
  let base = (self.min_deposit_per_sec * self.ttl_seconds).to_int64() * 2000L
  if base < 10000L {
    10000L
  } else {
    base
  }
}

///|
/// 时间推进：补足保底存款（按经过秒数），并封顶。
fn RetryBudget::tick(self : RetryBudget, now_ms : Int64) -> Unit {
  let sec = now_ms / 1000L
  if sec > self.last_tick_sec {
    let elapsed = sec - self.last_tick_sec
    self.micro_tokens = self.micro_tokens +
      elapsed * self.min_deposit_per_sec.to_int64() * 1000L
    self.last_tick_sec = sec
  }
  if self.micro_tokens > self.cap() {
    self.micro_tokens = self.cap()
  }
}

///|
/// 记录一次正常请求：按 retry_percent 比例存入微令牌。
pub fn RetryBudget::deposit(self : RetryBudget, now_ms : Int64) -> Unit {
  self.tick(now_ms)
  self.micro_tokens = self.micro_tokens + self.retry_percent_permille.to_int64()
  if self.micro_tokens > self.cap() {
    self.micro_tokens = self.cap()
  }
}

///|
/// 尝试消费一次重试额度：预算足够（≥1000 微令牌）返回 true 并扣减，
/// 否则 false（调用方应放弃重试，Finagle `tryWithdraw` 语义）。
pub fn RetryBudget::try_withdraw(self : RetryBudget, now_ms : Int64) -> Bool {
  self.tick(now_ms)
  if self.micro_tokens >= 1000L {
    self.micro_tokens = self.micro_tokens - 1000L
    true
  } else {
    false
  }
}

///|
/// 当前可用重试次数（向下取整，观测用）。
pub fn RetryBudget::balance(self : RetryBudget, now_ms : Int64) -> Int {
  self.tick(now_ms)
  (self.micro_tokens / 1000L).to_int()
}
