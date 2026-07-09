// runtime_family_proof_test.mbt —— 运行时家族（actor / dst / logging /
// lsp_server / parser_combinator）证明谓词的真实实现接地测试（INFRA
// 第十一批）。此前这些谓词仅由 direction_proofs_test.mbt 以合成数据
// 驱动，本批改由真实包实现产出输入：
//   * actor：邮箱 FIFO 顺序 fifo_order_preserved（随机消息计划 PBT）
//     + replay_consistent 同种子重放一致；
//   * dst：explore_bounded 同种子两次探索报告一致（deterministic_replay）；
//   * logging：Level::is_enabled 与 level_threshold_filter 全阈值矩阵一致；
//   * lsp_server：非法帧解码失败但解码器可继续服务
//     （illegal_message_keeps_alive）；
//   * parser_combinator：alt/字符类失败不消费输入（fail_does_not_consume）。

// --- actor：FIFO 顺序 + 重放一致 ---

///|
fn rf_plan_gen() -> @infra_pbt.Gen[Array[Int]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 16)
    let out : Array[Int] = []
    for _i in 0..<n {
      out.push(rng.next_range(-100, 100))
    }
    out
  })
}

///|
fn rf_prop_mailbox_fifo(plan : Array[Int]) -> Bool {
  let sys : @actor.ActorSystem[Array[Int], Int] = @actor.ActorSystem::new()
  let a = sys.spawn(
    [],
    @actor.Behavior::new(fn(_c, st : Array[Int], m : Int) {
      let next = st.copy()
      next.push(m)
      @actor.Updated(next)
    }),
  )
  for m in plan {
    a.send(m)
  }
  sys.run_until_idle()
  match sys.state_of(a) {
    Some(processed) => fifo_order_preserved(plan, processed)
    None => false
  }
}

///|
test "actor mailbox processes messages in fifo send order" {
  let ok = @infra_pbt.holds_for_all(
    rf_plan_gen(),
    rf_prop_mailbox_fifo,
    iters=128,
  )
  assert_true(ok)
}

///|
test "actor system replays consistently under the same seed" {
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.Gen::new(fn(rng) { rng.next() }),
    fn(seed : UInt64) -> Bool {
      @actor.replay_consistent(seed, fn(s : UInt64) {
        let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::with_seed(
          s,
        )
        let actors : Array[@actor.ActorRef[Int]] = []
        for _i in 0..<3 {
          actors.push(
            sys.spawn(
              0,
              @actor.Behavior::new(fn(_c, st, m) { @actor.Updated(st + m) }),
            ),
          )
        }
        for i in 0..<3 {
          for j in 0..<4 {
            actors[i].send(i * 10 + j)
          }
        }
        sys
      })
    },
    iters=64,
  )
  assert_true(ok)
}

// --- dst：同种子探索报告一致 ---

///|
test "bounded exploration replays deterministically under the same seed" {
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.Gen::new(fn(rng) { rng.next() }),
    fn(seed : UInt64) -> Bool {
      let scenario = @dst.demo_replication_scenario(3)
      let r1 = @dst.explore_bounded(seed, scenario, 24)
      let scenario2 = @dst.demo_replication_scenario(3)
      let r2 = @dst.explore_bounded(seed, scenario2, 24)
      // 报告编码为整数序列后交给 deterministic_replay 判定。
      let enc = fn(r : @dst.ExploreReport) -> Array[Int] {
        let out : Array[Int] = [r.explored]
        match r.failing {
          Some(f) => {
            out.push(1)
            out.push(f.1.length())
          }
          None => out.push(0)
        }
        out
      }
      deterministic_replay(enc(r1), enc(r2))
    },
    iters=32,
  )
  assert_true(ok)
}

// --- logging：阈值过滤矩阵一致 ---

///|
test "level threshold filtering agrees with is_enabled over the full matrix" {
  let levels : Array[@logging.Level] = [Trace, Debug, Info, Warn, Error]
  for ei in 0..<levels.length() {
    for ti in 0..<levels.length() {
      let emitted = levels[ei].is_enabled(levels[ti])
      assert_true(level_threshold_filter(ei, ti, emitted))
    }
  }
}

// --- lsp_server：非法帧不致崩溃 ---

///|
test "illegal frames fail to decode but the decoder keeps serving" {
  let illegal = [
    "", "Content-Length: abc\r\n\r\n{}", "no headers at all", "Content-Length: 5\r\n\r\n{\"jsonrpc\"",
  ]
  for msg in illegal {
    let failed = @lsp_server.decode_frame(msg) is Err(_)
    // 解码失败（error_responded=true 语义上等价于礼貌拒绝）且进程存活：
    // 随后一个合法帧仍可解码成功即为存活证据。
    let body = "{\"jsonrpc\":\"2.0\"}"
    let legal = "Content-Length: \{body.length()}\r\n\r\n" + body
    let alive = @lsp_server.decode_frame(legal) is Ok(_)
    assert_true(illegal_message_keeps_alive(!failed, failed, alive))
  }
}

// --- parser_combinator：失败不消费 ---

///|
test "failed parsers do not consume input" {
  let p = @parser_combinator.ptoken("hello")
  for src in ["world", "", "hell", "hexlo"] {
    let input = @parser_combinator.Input::from_string(src)
    match p.parse(input) {
      Ok(_, _) => abort("expected failure on \{src}")
      Fail(pos, expected=_) =>
        assert_true(fail_does_not_consume(false, input.pos.offset, pos.offset))
    }
  }
}
