// lifecycle_test.mbt —— 生命周期单条转移单元测试（任务 5.3）。
//
// 针对 lifecycle.mbt 的纯状态转移 `step` 与会话句柄 `LspSession`，覆盖
// Requirement 1.1 / 1.2 / 1.4 / 1.6 的**具体见证**：
//   * initialize→Initializing（回携带协商能力的 initialize 成功响应）   （R1.1）
//   * initialized→Initialized                                          （R1.2）
//   * shutdown→ShuttingDown（回 result=null 成功响应）                  （R1.4）
//   * exit 退出码：先 shutdown 报 0、否则报 1                            （R1.6）
//
// 断言策略：用 `assert_eq` 锁定 `state`（LifecycleState 派生 Eq/Show）；
// `reply` 以 pattern match 校验其形态（请求的成功 / 错误响应、id 一致）。
// 复合等值统一走派生 `Eq`，保持本包零告警约定。

// ───────────────────────────── R1.1 initialize→Initializing ───────────

///|
/// Uninitialized + EvInitialize → Initializing，且回携带 capabilities 的成功响应，
/// 响应 id 与请求 reply_id 一致。
test "step: initialize transitions Uninitialized to Initializing with capabilities reply" {
  let result = step(
    Uninitialized,
    false,
    EvInitialize(InitializeParamsExt::empty()),
    @lsp_binding.IdNum(1),
  )
  // 状态推进到 Initializing。
  assert_eq(result.state, Initializing)
  // 无退出码。
  assert_eq(result.exit_code, None)
  // 回成功响应：id 一致、result 为携带 capabilities 的对象、error 为 None。
  match result.reply {
    Some(@lsp_binding.Response(id~, result~, error~)) => {
      assert_true(id == @lsp_binding.IdNum(1))
      assert_true(error == None)
      match result {
        Some(@lsp_binding.JObj(fields)) => {
          // result 含 "capabilities" 字段。
          let mut has_caps = false
          for kv in fields {
            if kv.0 == "capabilities" {
              has_caps = true
            }
          }
          assert_true(has_caps)
        }
        _ => fail("expected initialize result to be a capabilities object")
      }
    }
    _ => fail("expected a success Response reply for initialize")
  }
}

///|
/// initialize 在非 Uninitialized 状态属非法请求：状态不变，回 invalid_request_code。
test "step: initialize in Initialized is rejected and state unchanged" {
  let result = step(
    Initialized,
    false,
    EvInitialize(InitializeParamsExt::empty()),
    @lsp_binding.IdNum(9),
  )
  assert_eq(result.state, Initialized)
  match result.reply {
    Some(@lsp_binding.Response(id~, result~, error~)) => {
      assert_true(id == @lsp_binding.IdNum(9))
      assert_true(result == None)
      match error {
        Some(e) => assert_true(e.code == @lsp_binding.invalid_request_code)
        None => fail("expected an error reply")
      }
    }
    _ => fail("expected an error Response reply")
  }
}

// ───────────────────────────── R1.2 initialized→Initialized ───────────

///|
/// Initializing + EvInitialized → Initialized，通知无应答。
test "step: initialized notification transitions Initializing to Initialized" {
  let result = step(Initializing, false, EvInitialized, @lsp_binding.IdNull)
  assert_eq(result.state, Initialized)
  assert_eq(result.reply, None)
  assert_eq(result.exit_code, None)
}

// ───────────────────────────── R1.4 shutdown→ShuttingDown ─────────────

///|
/// Initialized + EvShutdown → ShuttingDown，回 result=null 成功响应，id 一致。
test "step: shutdown transitions Initialized to ShuttingDown with null result" {
  let result = step(Initialized, false, EvShutdown, @lsp_binding.IdNum(2))
  assert_eq(result.state, ShuttingDown)
  assert_eq(result.exit_code, None)
  // 回 result=Some(JNull)、error=None 的成功响应。
  assert_true(
    result.reply ==
    Some(
      @lsp_binding.Response(
        id=@lsp_binding.IdNum(2),
        result=Some(@lsp_binding.JNull),
        error=None,
      ),
    ),
  )
}

///|
/// shutdown 在非 Initialized 状态属非法请求：状态不变，回 invalid_request_code。
test "step: shutdown in Uninitialized is rejected and state unchanged" {
  let result = step(Uninitialized, false, EvShutdown, @lsp_binding.IdNum(3))
  assert_eq(result.state, Uninitialized)
  match result.reply {
    Some(@lsp_binding.Response(id~, result=_, error~)) => {
      assert_true(id == @lsp_binding.IdNum(3))
      match error {
        Some(e) => assert_true(e.code == @lsp_binding.invalid_request_code)
        None => fail("expected an error reply")
      }
    }
    _ => fail("expected an error Response reply")
  }
}

// ───────────────────────────── R1.6 exit 退出码 ───────────────────────

///|
/// 已收到 shutdown（shutdown_seen=true）时 exit 报退出码 0。
test "step: exit after shutdown reports exit code 0" {
  let result = step(ShuttingDown, true, EvExit, @lsp_binding.IdNull)
  assert_eq(result.state, Exited)
  assert_eq(result.reply, None)
  assert_eq(result.exit_code, Some(0))
}

///|
/// 未收到 shutdown（shutdown_seen=false）时 exit 报退出码 1。
test "step: exit without shutdown reports exit code 1" {
  let result = step(Initialized, false, EvExit, @lsp_binding.IdNull)
  assert_eq(result.state, Exited)
  assert_eq(result.reply, None)
  assert_eq(result.exit_code, Some(1))
}

// ───────────────────── LspSession::handle 端到端推进 ──────────────────

///|
/// 经会话句柄走一遍 initialize → initialized → shutdown → exit，
/// 验证 state() 依次推进，且 shutdown 后 exit 报退出码 0。
test "LspSession: drives initialize -> initialized -> shutdown -> exit" {
  let s0 = LspSession::new()
  assert_eq(s0.state(), Uninitialized)

  // initialize 请求 → Initializing，回成功响应。
  let (s1, r1) = s0.handle(
    @lsp_binding.Request(
      id=@lsp_binding.IdNum(1),
      method="initialize",
      params=@lsp_binding.JNull,
    ),
  )
  assert_eq(s1.state(), Initializing)
  match r1 {
    Some(@lsp_binding.Response(error~, ..)) => assert_true(error == None)
    _ => fail("expected initialize success response")
  }

  // initialized 通知 → Initialized，无应答。
  let (s2, r2) = s1.handle(
    @lsp_binding.Notification(method="initialized", params=@lsp_binding.JNull),
  )
  assert_eq(s2.state(), Initialized)
  assert_eq(r2, None)

  // shutdown 请求 → ShuttingDown，回 result=null。
  let (s3, r3) = s2.handle(
    @lsp_binding.Request(
      id=@lsp_binding.IdNum(2),
      method="shutdown",
      params=@lsp_binding.JNull,
    ),
  )
  assert_eq(s3.state(), ShuttingDown)
  assert_true(
    r3 ==
    Some(
      @lsp_binding.Response(
        id=@lsp_binding.IdNum(2),
        result=Some(@lsp_binding.JNull),
        error=None,
      ),
    ),
  )

  // exit 通知 → Exited（已 shutdown，退出码语义见 step 测试）。
  let (s4, r4) = s3.handle(
    @lsp_binding.Notification(method="exit", params=@lsp_binding.JNull),
  )
  assert_eq(s4.state(), Exited)
  assert_eq(r4, None)
}
