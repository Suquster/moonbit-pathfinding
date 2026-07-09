// resilience_diff_proof.mbt —— INFRA 家族第二批证明谓词：韧性原语
// （infra_resilience：退避/AIMD/舱壁/熔断器）与文本 diff 引擎
// （infra_diff：diff/patch/revert）的不变量全量接入。
//
// 复用约定：与其余 `*_proof.mbt` 相同——每条不变量编码为纯、全（total）的
// `Bool` 谓词，proofs 生产代码不引入新依赖（仅 @core），跨包驱动只发生在
// 测试期（resilience_diff_proof_test.mbt 以真实包实现接地）。
//
// 覆盖的不变量家族：
//   * 有界性（backoff 延迟 ≤ cap、AIMD limit ∈ [min, max]、舱壁并发/队列硬上界）；
//   * 单调性（指数退避未达 cap 前非降）；
//   * 状态机合法迁移（熔断器 Closed→Open→HalfOpen→{Closed,Open} 迁移闭包）；
//   * 往返恒等（patch_apply∘diff == 恒等、patch_revert∘diff == 恒等）。

///|
/// `all_within(xs, lo, hi)` —— 有界性谓词：序列中每个元素均落在闭区间
/// `[lo, hi]` 内。用于退避延迟上限（`backoff_delay ≤ cap_ms`）、AIMD 并发
/// 限额（`limit ∈ [min_limit, max_limit]`）、舱壁计数（`in_flight ≤
/// max_concurrent`、`queued ≤ max_queue`）等一切硬预算不变量。
/// 纯、全函数，对任意序列恒返回 `Bool`（空序列平凡为真）。
pub fn all_within(xs : Array[Int], lo : Int, hi : Int) -> Bool {
  let mut i = 0
  while i < xs.length() {
    if xs[i] < lo || xs[i] > hi {
      return false
    }
    i += 1
  }
  true
}

///|
/// `non_decreasing(xs)` —— 单调性谓词：序列逐对非降（`xs[i] <= xs[i+1]`）。
/// 用于指数退避在未达 cap 前的延迟单调增长、HdrHistogram 分位数随 q 单调等
/// 性质。纯、全函数（长度 < 2 平凡为真）。
pub fn non_decreasing(xs : Array[Int]) -> Bool {
  let mut i = 0
  while i + 1 < xs.length() {
    if xs[i] > xs[i + 1] {
      return false
    }
    i += 1
  }
  true
}

///|
/// `transitions_legal(states, allowed)` —— 状态机合法迁移谓词：观测到的状态
/// 序列中每一步 `(states[i], states[i+1])` 要么原地不动（自迁移恒合法），
/// 要么落在迁移关系 `allowed` 内。以 `Int` 编码状态（调用侧负责枚举→Int 的
/// 单射映射），保持谓词与具体状态机类型解耦。用于熔断器
/// Closed(0)→Open(1)→HalfOpen(2)→{Closed, Open} 的迁移闭包校验。
/// 纯、全函数（长度 < 2 平凡为真）。
pub fn transitions_legal(
  states : Array[Int],
  allowed : (Int, Int) -> Bool,
) -> Bool {
  let mut i = 0
  while i + 1 < states.length() {
    let a = states[i]
    let b = states[i + 1]
    if a != b && !allowed(a, b) {
      return false
    }
    i += 1
  }
  true
}

///|
/// `breaker_transition_allowed(a, b)` —— 熔断器三态机的迁移关系
/// （编码：Closed=0、Open=1、HalfOpen=2）：
///   * Closed → Open（连续失败达阈值跳闸）；
///   * Open → HalfOpen（冷却期满放行探针）；
///   * HalfOpen → Closed（探针成功恢复）；
///   * HalfOpen → Open（探针失败再跳闸）。
/// 其余跨态迁移（如 Closed→HalfOpen、Open→Closed 直达）均非法。
/// 纯、全函数，供 `transitions_legal` 组合使用。
pub fn breaker_transition_allowed(a : Int, b : Int) -> Bool {
  (a == 0 && b == 1) ||
  (a == 1 && b == 2) ||
  (a == 2 && b == 0) ||
  (a == 2 && b == 1)
}

///|
/// `patch_round_trip_eq(before, after, forward)` —— diff/patch 往返恒等谓词
/// 的通用骨架：`forward(before, after)` 产出「从 before 到 after 的重放
/// 闭包结果」，当且仅当其为 `Some(x)` 且 `x == after` 时成立。
///
/// 调用侧以闭包捕获具体引擎：
///   * 正向：`forward = fn(a, b) { patch_apply(a, diff_lines(a, b)) }`，
///     期望还原 `after`；
///   * 反向：`forward = fn(a, b) { patch_revert(b, diff_lines(a, b)) }`
///     以 `(after, before)` 调用，期望还原 `before`。
/// 解码失败（`None`）视为往返破坏。要求 `T : Eq`。纯、全函数。
pub fn[T : Eq] patch_round_trip_eq(
  before : T,
  after : T,
  forward : (T, T) -> T?,
) -> Bool {
  match forward(before, after) {
    Some(x) => x == after
    None => false
  }
}
