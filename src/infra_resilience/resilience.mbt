// resilience.mbt —— 韧性原语：重试退避 / 熔断器 / 令牌桶 / 滑动窗口限流。
//
// 设计要点：所有组件以**显式时钟参数**（毫秒时间戳由调用方传入）驱动，
// 不读真实时间——与本仓库 DST（确定性仿真测试）哲学一致，任何时序行为
// 都能在测试里逐毫秒重放。
//
// paper-to-code：
// - 指数退避 + 去相关抖动：AWS Architecture Blog *Exponential Backoff
//   and Jitter*（2015）——`min(cap, base·2^attempt)` 的 full-jitter 变体，
//   抖动由调用方注入的确定性随机数驱动；
// - 熔断器：Nygard *Release It!* 的 Closed → Open → HalfOpen 三态机，
//   连续失败阈值触发跳闸、冷却窗口后半开试探、试探成功闭合；
// - 令牌桶：经典 token bucket（RFC 2697 srTCM 的单桶核心）——按流逝
//   时间连续补充令牌、桶容量封顶、整数毫秒精度；
// - 滑动窗口限流：时间戳队列精确计数（非近似分桶），窗口外条目惰性淘汰。

///|
/// 指数退避策略（毫秒）。
pub(all) struct BackoffPolicy {
  base_ms : Int // 首次重试延迟
  cap_ms : Int // 延迟上限
  max_retries : Int
} derive(Eq, Debug)

///|
/// 第 attempt 次重试（0 起）的确定性延迟：min(cap, base·2^attempt)。
pub fn backoff_delay(policy : BackoffPolicy, attempt : Int) -> Int {
  if attempt < 0 {
    return policy.base_ms
  }
  let mut d = policy.base_ms.to_int64()
  for _ in 0..<attempt {
    d = d * 2L
    if d >= policy.cap_ms.to_int64() {
      return policy.cap_ms
    }
  }
  if d > policy.cap_ms.to_int64() {
    policy.cap_ms
  } else {
    d.to_int()
  }
}

///|
/// full-jitter 延迟：uniform[0, backoff_delay]，随机源由调用方注入
/// （jitter_unit 取 0..1000 的千分比）。
pub fn backoff_delay_jittered(
  policy : BackoffPolicy,
  attempt : Int,
  jitter_permille : Int,
) -> Int {
  let full = backoff_delay(policy, attempt)
  let j = if jitter_permille < 0 {
    0
  } else if jitter_permille > 1000 {
    1000
  } else {
    jitter_permille
  }
  full * j / 1000
}

///|
/// 重试驱动器：给定每次尝试的结果序列语义，返回总尝试次数与是否成功。
/// f 返回 true 表示成功；attempt 超过 max_retries 后放弃。
pub fn retry_run(policy : BackoffPolicy, f : (Int) -> Bool) -> (Bool, Int) {
  let mut attempt = 0
  while attempt <= policy.max_retries {
    if f(attempt) {
      return (true, attempt + 1)
    }
    attempt = attempt + 1
  }
  (false, attempt)
}

///|
/// 熔断器状态。
pub(all) enum CircuitState {
  Closed
  Open
  HalfOpen
} derive(Eq, Debug)

///|
/// 诊断输出。
pub impl Show for CircuitState with fn output(self, logger) {
  match self {
    Closed => logger.write_string("Closed")
    Open => logger.write_string("Open")
    HalfOpen => logger.write_string("HalfOpen")
  }
}

///|
/// 熔断器（Nygard 三态机，显式时钟）。
pub struct CircuitBreaker {
  failure_threshold : Int // 连续失败多少次跳闸
  cooldown_ms : Int // Open → HalfOpen 冷却时长
  mut state : CircuitState
  mut consecutive_failures : Int
  mut opened_at_ms : Int64
}

///|
/// 构造（初始 Closed）。
pub fn CircuitBreaker::create(
  failure_threshold : Int,
  cooldown_ms : Int,
) -> CircuitBreaker {
  {
    failure_threshold: if failure_threshold < 1 {
      1
    } else {
      failure_threshold
    },
    cooldown_ms,
    state: Closed,
    consecutive_failures: 0,
    opened_at_ms: 0L,
  }
}

///|
/// 当前是否放行请求（Open 状态冷却到期自动转 HalfOpen 并放行一次试探）。
pub fn CircuitBreaker::allow(self : CircuitBreaker, now_ms : Int64) -> Bool {
  match self.state {
    Closed => true
    HalfOpen => true
    Open =>
      if now_ms - self.opened_at_ms >= self.cooldown_ms.to_int64() {
        self.state = HalfOpen
        true
      } else {
        false
      }
  }
}

///|
/// 上报成功：HalfOpen 试探成功 → Closed；Closed 清零失败计数。
pub fn CircuitBreaker::record_success(self : CircuitBreaker) -> Unit {
  self.state = Closed
  self.consecutive_failures = 0
}

///|
/// 上报失败：Closed 累计到阈值跳闸；HalfOpen 试探失败立即回 Open。
pub fn CircuitBreaker::record_failure(
  self : CircuitBreaker,
  now_ms : Int64,
) -> Unit {
  match self.state {
    HalfOpen => {
      self.state = Open
      self.opened_at_ms = now_ms
    }
    Closed => {
      self.consecutive_failures = self.consecutive_failures + 1
      if self.consecutive_failures >= self.failure_threshold {
        self.state = Open
        self.opened_at_ms = now_ms
      }
    }
    Open => ()
  }
}

///|
/// 当前状态（只读观察）。
pub fn CircuitBreaker::state_of(self : CircuitBreaker) -> CircuitState {
  self.state
}

///|
/// 令牌桶限流器（毫秒精度连续补充，显式时钟）。
pub struct TokenBucket {
  capacity : Int // 桶容量（最大突发）
  refill_per_sec : Int // 每秒补充令牌数
  mut tokens_milli : Int64 // 千分之一令牌为单位，避免浮点
  mut last_ms : Int64
}

///|
/// 构造（初始满桶）。
pub fn TokenBucket::create(capacity : Int, refill_per_sec : Int) -> TokenBucket {
  let cap = if capacity < 1 { 1 } else { capacity }
  {
    capacity: cap,
    refill_per_sec: if refill_per_sec < 0 {
      0
    } else {
      refill_per_sec
    },
    tokens_milli: cap.to_int64() * 1000L,
    last_ms: 0L,
  }
}

///|
/// 按流逝时间补充令牌（封顶容量）。
fn TokenBucket::refill(self : TokenBucket, now_ms : Int64) -> Unit {
  if now_ms > self.last_ms {
    let elapsed = now_ms - self.last_ms
    self.tokens_milli = self.tokens_milli +
      elapsed * self.refill_per_sec.to_int64()
    let cap_milli = self.capacity.to_int64() * 1000L
    if self.tokens_milli > cap_milli {
      self.tokens_milli = cap_milli
    }
    self.last_ms = now_ms
  }
}

///|
/// 尝试取 1 个令牌；成功返回 true。
pub fn TokenBucket::try_acquire(self : TokenBucket, now_ms : Int64) -> Bool {
  self.refill(now_ms)
  if self.tokens_milli >= 1000L {
    self.tokens_milli = self.tokens_milli - 1000L
    true
  } else {
    false
  }
}

///|
/// 当前整令牌数（观察用）。
pub fn TokenBucket::available(self : TokenBucket, now_ms : Int64) -> Int {
  self.refill(now_ms)
  (self.tokens_milli / 1000L).to_int()
}

///|
/// 滑动窗口限流器：窗口内精确计数（时间戳环形队列，惰性淘汰）。
pub struct SlidingWindowLimiter {
  window_ms : Int
  max_events : Int
  stamps : Array[Int64] // 按到达序保存的时间戳
  mut head : Int // 已淘汰前缀
}

///|
/// 构造。
pub fn SlidingWindowLimiter::create(
  window_ms : Int,
  max_events : Int,
) -> SlidingWindowLimiter {
  {
    window_ms: if window_ms < 1 {
      1
    } else {
      window_ms
    },
    max_events: if max_events < 1 {
      1
    } else {
      max_events
    },
    stamps: [],
    head: 0,
  }
}

///|
/// 淘汰窗口外条目；周期性压缩底层数组防泄漏。
fn SlidingWindowLimiter::evict(
  self : SlidingWindowLimiter,
  now_ms : Int64,
) -> Unit {
  while self.head < self.stamps.length() &&
        now_ms - self.stamps[self.head] >= self.window_ms.to_int64() {
    self.head = self.head + 1
  }
  if self.head > 1024 && self.head * 2 > self.stamps.length() {
    let kept : Array[Int64] = []
    for i in self.head..<self.stamps.length() {
      kept.push(self.stamps[i])
    }
    self.stamps.clear()
    for s in kept {
      self.stamps.push(s)
    }
    self.head = 0
  }
}

///|
/// 尝试放行一次事件；窗口内已满返回 false。
pub fn SlidingWindowLimiter::try_acquire(
  self : SlidingWindowLimiter,
  now_ms : Int64,
) -> Bool {
  self.evict(now_ms)
  if self.stamps.length() - self.head < self.max_events {
    self.stamps.push(now_ms)
    true
  } else {
    false
  }
}

///|
/// 窗口内当前事件数（观察用）。
pub fn SlidingWindowLimiter::in_flight(
  self : SlidingWindowLimiter,
  now_ms : Int64,
) -> Int {
  self.evict(now_ms)
  self.stamps.length() - self.head
}
