// sampling.mbt —— 确定性采样与限流（任务 5.1 / 5.3 / 5.6）。
//
// 设计依据：design.md §4.4「确定性采样与限流」（Requirement 3.*）。采样分两种
// 互补机制，均确定性、可重放、三后端逐位一致：
//
//   * `sample_trace(rate, trace, seed)` —— trace 内一致采样（Requirement 3.3 /
//     3.6）：决策仅由 trace 标识与配置（rate, seed）决定，故同一 trace 的全部
//     事件得到相同决策（全采或全弃）。`keep ⟺ (mix(trace, seed) mod DENOM) <
//     floor(rate*DENOM)`；rate=0 恒弃、rate=1 恒采（Requirement 3.2）。
//   * `sample_stream(rate, events, rng)` —— 事件流系统采样（systematic
//     sampling，Requirement 3.1 / 3.7）：确定性保留恰 `floor(rate*n)` 条事件，
//     `rng` 仅决定保留相位（起点）不改条数，故保留占比可证有界且可重放
//     （Requirement 3.4）。
//   * `RateLimiter` —— 逻辑时间窗（tumbling window）限流（Requirement 3.5）：
//     窗内放行至 `limit` 条后丢弃超额事件，窗口到期重置。
//
// 三后端一致性（Requirement 13.1）：`mix` 为纯 `UInt64` 整型混合（不依赖浮点、
// 不依赖哈希表顺序），采样相位取自确定性 `@infra_pbt.Rng`。

///|
/// 采样量化分母（DENOM）：采样率被量化到 `[0, DENOM]` 的整数阈值。
let sampling_denom : UInt64 = 1_000_000UL

///|
/// 纯整型混合函数（FNV-1a 字节混合 + xorshift/MurmurHash 终混）。
///
/// 把 64 位 trace 标识与 64 位种子混合为均匀散布的 64 位散列。全程 `UInt64`
/// 算术（乘法按模 2^64 回绕），三后端（wasm-gc / js / native）逐位一致，
/// 不依赖平台整型宽度或浮点。
pub fn mix(value : UInt64, seed : UInt64) -> UInt64 {
  // FNV-1a 基础：以种子扰动初始偏移，逐字节混入 value 的 8 个字节。
  let mut h = seed ^ 0xcbf29ce484222325UL
  let mut x = value
  for _i = 0; _i < 8; _i = _i + 1 {
    let b = x & 0xffUL
    h = (h ^ b) * 0x100000001b3UL
    x = x >> 8
  }
  // MurmurHash3 fmix64 终混，提升雪崩效应（均匀散布）。
  h = h ^ (h >> 33)
  h = h * 0xff51afd7ed558ccdUL
  h = h ^ (h >> 33)
  h = h * 0xc4ceb9fe1a85ec53UL
  h = h ^ (h >> 33)
  h
}

///|
/// 把采样率量化为 `[0, DENOM]` 的整数阈值 `floor(rate*DENOM)`。
fn sampling_threshold(rate : Double) -> UInt64 {
  if rate <= 0.0 {
    return 0UL
  }
  if rate >= 1.0 {
    return sampling_denom
  }
  let t = (rate * sampling_denom.to_double()).to_int64()
  if t <= 0L {
    0UL
  } else if t >= 1_000_000L {
    sampling_denom
  } else {
    t.reinterpret_as_uint64()
  }
}

///|
/// trace 内一致采样判定（Requirement 3.1 / 3.2 / 3.3 / 3.6）。
///
/// 决策仅由 `trace` 标识与配置（`rate`, `seed`）决定，对同一 trace 恒定，
/// 故该 trace 的全部事件要么全部被采样、要么全部被丢弃（trace-coherent）。
/// 边界：`rate <= 0.0` 恒弃，`rate >= 1.0` 恒采。
pub fn sample_trace(rate : Double, trace : TraceId, seed : UInt64) -> Bool {
  if rate <= 0.0 {
    return false
  }
  if rate >= 1.0 {
    return true
  }
  let threshold = sampling_threshold(rate)
  let h = mix(trace.value.reinterpret_as_uint64(), seed) % sampling_denom
  h < threshold
}

///|
/// 给定事件数 `n` 与采样率，系统采样保留条数 = `floor(rate*n)`（≤ `rate*n`）。
///
/// 边界：`rate <= 0.0` 保留 0 条，`rate >= 1.0` 保留全部 `n` 条。
pub fn retained_count(rate : Double, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if rate <= 0.0 {
    return 0
  }
  if rate >= 1.0 {
    return n
  }
  let r = (rate * n.to_double()).to_int()
  if r < 0 {
    0
  } else if r > n {
    n
  } else {
    r
  }
}

///|
/// 事件流系统采样（Requirement 3.1 / 3.2 / 3.4 / 3.7）。
///
/// 确定性保留恰 `retained_count(rate, n) = floor(rate*n)` 条事件，使保留占比
/// 有上界（Property 6）。以 `rng` 决定保留相位（起点）但**不改变保留条数**，
/// 故相同配置与相同种子重放同一序列得逐条相同结果（Property 7）。保留事件
/// 保持原始顺序。
pub fn sample_stream(
  rate : Double,
  events : Array[Event],
  rng : @infra_pbt.Rng,
) -> Array[Event] {
  let n = events.length()
  let keep = retained_count(rate, n)
  let out : Array[Event] = []
  if keep <= 0 {
    return out
  }
  if keep >= n {
    for e in events {
      out.push(e)
    }
    return out
  }
  // 系统采样：以 rng 取相位起点，按 floor(j*n/keep) 的等距步长选取 keep 个
  // 互异下标（n >= keep ⇒ floor(j*n/keep) 严格递增且落在 [0,n)，加相位后
  // 模 n 仍互异）。仅决定「选哪些」不改「选几个」，故条数恒为 keep。
  let phase = rng.next_below(n)
  let keepset = Array::make(n, false)
  for j = 0; j < keep; j = j + 1 {
    let idx = (phase + j * n / keep) % n
    keepset[idx] = true
  }
  for i = 0; i < n; i = i + 1 {
    if keepset[i] {
      out.push(events[i])
    }
  }
  out
}

///|
/// 逻辑时间窗限流器（Requirement 3.5）。
///
/// 对每个 key 维护一个 tumbling window：`(窗口起点, 窗内已放行条数)`。窗内
/// 放行至 `limit` 条后丢弃超额事件；逻辑时间 `ts` 超出当前窗口（`ts - start
/// >= window`）则重置窗口起点与计数。
pub(all) struct RateLimiter {
  window : Int64
  limit : Int
  mut state : Map[String, (Int64, Int)]
}

///|
/// 构造一个限流器：窗口长度 `window`（逻辑时间单位）与每窗配额 `limit`。
pub fn RateLimiter::new(window : Int64, limit : Int) -> RateLimiter {
  { window, limit, state: Map::new() }
}

///|
/// 在逻辑时间 `ts` 对 `key` 申请通过（Requirement 3.5）。
///
/// 窗内未超配额则放行并计数返回 true；超额则丢弃返回 false。`ts` 超出当前
/// 窗口则开启新窗口（起点 = `ts`，计数清零后再判定）。任一逻辑时间窗内对
/// 同一 key 放行条数不超过 `limit`（Property 8）。
pub fn RateLimiter::allow(self : RateLimiter, key : String, ts : Int64) -> Bool {
  let mut wstart = ts
  let mut wcount = 0
  match self.state.get(key) {
    Some((start, count)) =>
      if ts - start < self.window {
        // 仍在当前窗口内：沿用窗口起点与已放行计数。
        wstart = start
        wcount = count
      }
    // 否则窗口到期：保持 wstart=ts、wcount=0（开启新窗口）。
    None => ()
  }
  if wcount < self.limit {
    self.state[key] = (wstart, wcount + 1)
    true
  } else {
    self.state[key] = (wstart, wcount)
    false
  }
}
