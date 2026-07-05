// progress_test.mbt —— T5.2 `$/progress` 编解码往返与生命周期校验的行为锁定。

///|
test "T5.2: progress_notification 编码——begin 全字段与规范字段名一致" {
  let msg = progress_notification(
    TokNum(7),
    Begin(
      title="indexing",
      cancellable=Some(true),
      message=Some("scanning"),
      percentage=Some(0),
    ),
  )
  match msg {
    Notification(method_name~, params~) => {
      assert_eq(method_name, "$/progress")
      // 经字节编解码往返后 params 结构保持（含 token 与 value.kind）。
      match progress_of(params) {
        Some((tok, v)) => {
          assert_true(tok == TokNum(7))
          assert_true(
            v ==
            Begin(
              title="indexing",
              cancellable=Some(true),
              message=Some("scanning"),
              percentage=Some(0),
            ),
          )
        }
        None => fail("params 应可解析")
      }
    }
    _ => fail("应为 Notification")
  }
}

///|
test "T5.2: progress_of 非法输入——缺 token / 缺 title / kind 非法返回 None" {
  // 缺 token。
  assert_true(
    progress_of(JObj([("value", JObj([("kind", JStr("end"))]))])) is None,
  )
  // begin 缺 title。
  assert_true(
    progress_of(
      JObj([("token", JNum("1")), ("value", JObj([("kind", JStr("begin"))]))]),
    )
    is None,
  )
  // kind 非法。
  assert_true(
    progress_of(
      JObj([("token", JNum("1")), ("value", JObj([("kind", JStr("bogus"))]))]),
    )
    is None,
  )
  // params 非对象。
  assert_true(progress_of(JStr("x")) is None)
}

///|
test "T5.2: ProgressTracker 合法生命周期 begin → report* → end" {
  let t0 = ProgressTracker::new()
  let tok : ProgressToken = TokStr("job")
  let t1 = match
    t0.observe(
      tok,
      Begin(title="t", cancellable=None, message=None, percentage=Some(0)),
    ) {
    Ok(t) => t
    Err(e) => fail(e)
  }
  let t2 = match
    t1.observe(tok, Report(cancellable=None, message=None, percentage=Some(50))) {
    Ok(t) => t
    Err(e) => fail(e)
  }
  let t3 = match
    t2.observe(
      tok,
      Report(cancellable=None, message=None, percentage=Some(100)),
    ) {
    Ok(t) => t
    Err(e) => fail(e)
  }
  match t3.observe(tok, End(message=Some("done"))) {
    Ok(_) => ()
    Err(e) => fail(e)
  }
  // 不可变性：t0 仍是空跟踪器，可对同一令牌重新 begin。
  assert_true(
    t0.observe(
      tok,
      Begin(title="t", cancellable=None, message=None, percentage=None),
    )
    is Ok(_),
  )
}

///|
test "T5.2: ProgressTracker 违规序列全部拒绝" {
  let t0 = ProgressTracker::new()
  let tok : ProgressToken = TokNum(1)
  // begin 前 report / end。
  assert_true(
    t0.observe(tok, Report(cancellable=None, message=None, percentage=None))
    is Err(_),
  )
  assert_true(t0.observe(tok, End(message=None)) is Err(_))
  let t1 = match
    t0.observe(
      tok,
      Begin(title="t", cancellable=None, message=None, percentage=Some(40)),
    ) {
    Ok(t) => t
    Err(e) => fail(e)
  }
  // 重复 begin。
  assert_true(
    t1.observe(
      tok,
      Begin(title="t", cancellable=None, message=None, percentage=None),
    )
    is Err(_),
  )
  // percentage 回退与越界。
  assert_true(
    t1.observe(tok, Report(cancellable=None, message=None, percentage=Some(30)))
    is Err(_),
  )
  assert_true(
    t1.observe(
      tok,
      Report(cancellable=None, message=None, percentage=Some(101)),
    )
    is Err(_),
  )
  // end 之后 report / 重复 end。
  let t2 = match t1.observe(tok, End(message=None)) {
    Ok(t) => t
    Err(e) => fail(e)
  }
  assert_true(
    t2.observe(tok, Report(cancellable=None, message=None, percentage=None))
    is Err(_),
  )
  assert_true(t2.observe(tok, End(message=None)) is Err(_))
  // 数值令牌 1 与字符串令牌 "1" 互不碰撞。
  assert_true(
    t2.observe(
      TokStr("1"),
      Begin(title="t", cancellable=None, message=None, percentage=None),
    )
    is Ok(_),
  )
}

///|
/// 随机进度 value 生成器（三态 + 随机可选字段）。
fn gen_progress() -> @infra_pbt.Gen[(ProgressToken, WorkDoneProgress)] {
  @infra_pbt.Gen::new(fn(rng) {
    let tok : ProgressToken = if rng.next_bool() {
      TokNum(rng.next_range(0, 1000))
    } else {
      TokStr("tok\{rng.next_below(100)}")
    }
    let cancellable : Bool? = if rng.next_bool() {
      Some(rng.next_bool())
    } else {
      None
    }
    let message : String? = if rng.next_bool() {
      Some("m\{rng.next_below(100)}")
    } else {
      None
    }
    let percentage : Int? = if rng.next_bool() {
      Some(rng.next_range(0, 100))
    } else {
      None
    }
    let v : WorkDoneProgress = match rng.next_below(3) {
      0 =>
        Begin(
          title="t\{rng.next_below(10)}",
          cancellable~,
          message~,
          percentage~,
        )
      1 => Report(cancellable~, message~, percentage~)
      _ => End(message~)
    }
    (tok, v)
  })
}

///|
/// Feature: moonbit-infra-suite, T5.2: `$/progress` 全链路往返属性
///
/// 对任意随机 (token, value)，`progress_notification` 合成的通知经
/// `encode_framed`（Content-Length 成帧）→ `decode_framed` 字节往返后，
/// `progress_of` 还原出的 (token, value) 与原值逐字段相等。
///
/// **Validates: T5.2（协议完整性：进度 + 成帧往返 PBT）**
test "T5.2 property: progress notification framed round-trip (100 iters)" {
  let ok = @infra_pbt.holds_for_all(gen_progress(), fn(pair) {
    let (tok, v) = pair
    let msg = progress_notification(tok, v)
    match decode_framed(encode_framed(msg)) {
      Ok(Notification(method_name~, params~)) => {
        let restored = progress_of(params)
        method_name == "$/progress" &&
        (match restored {
          Some((tok2, v2)) => tok2 == tok && v2 == v
          None => false
        })
      }
      _ => false
    }
  })
  assert_true(ok)
}
