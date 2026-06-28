// prop_lifecycle_test.mbt —— 生命周期合法转移属性测试（任务 5.4，Property 4）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 4「生命周期合法转移」：
//
//   *对任意* 由生成器产出的生命周期事件序列，逐步驱动纯状态转移 `step` 时：
//     (a) 每一步转移后的状态，必等于「声明的合法转移」之一——以一个独立的参照
//         实现 `expected_state(state, event)` 重述 design.md §3.1 的转移规则，
//         断言 `step` 所得状态与参照一致（即状态仅经声明的合法转移变化）；
//     (b) 在收到 shutdown 之后（即当前状态为 `ShuttingDown`），对任何非 `exit`
//         的**请求**事件（EvInitialize / EvShutdown / EvRequest），`step` 必回
//         携带 `invalid_request_code` 的错误响应且不改变状态。
//
// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.8**
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认
// `iters=100`，满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。

// ---------------------------------------------------------------------------
// 随机生成器（生命周期事件序列）
// ---------------------------------------------------------------------------

///|
/// 一组用于 `EvRequest` / `EvNotification` 的非生命周期 method 名（任意挑选，
/// 覆盖「非 initialize/initialized/shutdown/exit」的常规消息）。
let sample_methods : Array[String] = [
  "textDocument/completion", "textDocument/definition", "textDocument/hover", "$/cancelRequest",
  "workspace/symbol",
]

///|
/// 生成单个随机生命周期事件：在 6 种事件构造子中等概率选取，
/// `EvRequest` / `EvNotification` 携带随机 method 名。
fn gen_lifecycle_event(rng : @infra_pbt.Rng) -> LifecycleEvent {
  let method_name = sample_methods[rng.next_below(sample_methods.length())]
  match rng.next_below(6) {
    0 => EvInitialize(InitializeParamsExt::empty())
    1 => EvInitialized
    2 => EvShutdown
    3 => EvExit
    4 => EvRequest(method_name~)
    _ => EvNotification(method_name~)
  }
}

///|
/// 生成一个随机长度（0..12）的生命周期事件序列。
fn gen_lifecycle_events(rng : @infra_pbt.Rng) -> Array[LifecycleEvent] {
  let n = rng.next_below(13)
  let events : Array[LifecycleEvent] = []
  let mut i = 0
  while i < n {
    events.push(gen_lifecycle_event(rng))
    i = i + 1
  }
  events
}

///|
/// 生命周期事件序列生成器（封装为 @infra_pbt.Gen）。
fn gen_lifecycle_sequences() -> @infra_pbt.Gen[Array[LifecycleEvent]] {
  @infra_pbt.Gen::new(fn(rng) { gen_lifecycle_events(rng) })
}

// ---------------------------------------------------------------------------
// 参照实现：独立重述「声明的合法转移」（design.md §3.1，Requirement 1.1–1.8）
// ---------------------------------------------------------------------------

///|
/// 参照转移表：给定当前状态与事件，返回声明的合法转移所应到达的新状态。
/// 这是与被测 `step` **相互独立**的规则重述，用于交叉验证状态机只经合法转移变化。
///   * EvInitialize：仅 Uninitialized → Initializing；其余状态不变（非法请求，1.3/1.8）
///   * EvInitialized：仅 Initializing → Initialized；其余不变（1.2）
///   * EvShutdown：仅 Initialized → ShuttingDown；其余不变（非法请求，1.5/1.8）
///   * EvExit：任意状态 → Exited（1.6）
///   * EvRequest / EvNotification：状态不变（按当前状态裁决，1.3/1.5/1.8）
fn expected_state(
  state : LifecycleState,
  event : LifecycleEvent,
) -> LifecycleState {
  match event {
    EvInitialize(_) =>
      match state {
        Uninitialized => Initializing
        _ => state
      }
    EvInitialized =>
      match state {
        Initializing => Initialized
        _ => state
      }
    EvShutdown =>
      match state {
        Initialized => ShuttingDown
        _ => state
      }
    EvExit => Exited
    EvRequest(method_name=_) => state
    EvNotification(method_name=_) => state
  }
}

///|
/// 判定一个事件是否为「请求」类事件（请求才需应答；通知无应答）。
/// EvInitialize / EvShutdown / EvRequest 为请求；EvInitialized / EvNotification
/// 为通知；EvExit 是通知（且为生命周期允许的退出转移），不纳入「非 exit 请求」。
fn is_request_event(event : LifecycleEvent) -> Bool {
  match event {
    EvInitialize(_) => true
    EvShutdown => true
    EvRequest(method_name=_) => true
    _ => false
  }
}

// ---------------------------------------------------------------------------
// 属性测试（Property 4）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 4: 生命周期合法转移
///
/// 对任意由生成器产出的生命周期事件序列，逐步折叠 `step` 维护 (state,
/// shutdown_seen)，并在每一步断言：
///   (a) `step` 所得新状态等于独立参照 `expected_state(state, event)`（状态仅经
///       声明的合法转移变化）；
///   (b) 当前状态为 `ShuttingDown` 时，对任何非 exit 的请求事件，`step` 回携带
///       `invalid_request_code` 的错误响应且状态不变（shutdown 后拒绝非 exit 请求）。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.8**
test "Feature: lsp, Property 4: lifecycle legal-transition holds for random event sequences" {
  let ok = @infra_pbt.holds_for_all(gen_lifecycle_sequences(), fn(events) {
    let mut state : LifecycleState = Uninitialized
    let mut shutdown_seen = false
    let mut holds = true
    for event in events {
      let result = step(state, shutdown_seen, event, @lsp_binding.IdNum(1))

      // (a) 状态仅经声明的合法转移变化（与独立参照一致）。
      if result.state != expected_state(state, event) {
        holds = false
      }

      // (b) shutdown 后（当前 ShuttingDown）对非 exit 请求以 invalid_request_code 拒绝且状态不变。
      if state == ShuttingDown && is_request_event(event) {
        if result.state != ShuttingDown {
          holds = false
        }
        match result.reply {
          Some(@lsp_binding.Response(id~, result=res, error~)) => {
            if id != @lsp_binding.IdNum(1) {
              holds = false
            }
            if res != None {
              holds = false
            }
            match error {
              Some(e) =>
                if e.code != @lsp_binding.invalid_request_code {
                  holds = false
                }
              None => holds = false
            }
          }
          _ => holds = false
        }
      }

      // 折叠推进（与 LspSession::handle 一致：进入 ShuttingDown 即记忆 shutdown_seen）。
      state = result.state
      shutdown_seen = shutdown_seen || result.state == ShuttingDown
    }
    holds
  })
  assert_true(ok)
}
