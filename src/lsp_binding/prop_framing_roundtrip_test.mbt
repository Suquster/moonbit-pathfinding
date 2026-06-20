// prop_framing_roundtrip_test.mbt —— LSP Base Protocol 头部帧往返属性测试
// （任务 1.3，Property 12）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 12「头部帧往返」：
//
//   *对任意* 由生成器产出的 `JsonRpcMessage` `m`，
//   `decode_framed(encode_framed(m))` 得到与 `m` 相等的消息；
//   *且对任意* 消息序列，依次写入帧后由 `FrameReader` 逐条切出的消息序列
//   与原序列按序相等（最终缓冲为空，`next` 返回 `Ok(None)`）。
//
// **Validates: Requirements 2.1, 2.2**
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `round_trip` / `holds_for_all`
// 模板（每条属性 ≥100 次迭代，由模板默认 `iters=100` / `default_iters` 保证）。
//
// 生成器复用：随机 `JsonRpcMessage` 生成器（`gen_message` / `gen_json_rpc_message`
// 及其依赖 `gen_id` / `gen_json` / `gen_ascii_string` 等）已在同包文件
// `prop_roundtrip_test.mbt` 定义，本文件直接复用，不重复定义（同包重名会冲突）。

// ---------------------------------------------------------------------------
// Bytes 解码桥接（供 round_trip 模板使用）
// ---------------------------------------------------------------------------

///|
/// 解码适配：将 `decode_framed` 的 `Result[JsonRpcMessage, RpcError]` 适配为
/// `round_trip` 模板所需的 `(Bytes) -> JsonRpcMessage?`；解码失败映射为 `None`
/// （往返失败）。
fn decode_framed_opt(bytes : Bytes) -> JsonRpcMessage? {
  match decode_framed(bytes) {
    Ok(msg) => Some(msg)
    Err(_) => None
  }
}

// ---------------------------------------------------------------------------
// 多消息序列生成器
// ---------------------------------------------------------------------------

///|
/// 生成一个随机长度（0..6）的 `JsonRpcMessage` 序列，复用同包既有的单消息
/// 生成器 `gen_message`。长度上界刻意保持较小以保证缓冲规模有界、迭代高效。
fn gen_message_seq(rng : @infra_pbt.Rng) -> Array[JsonRpcMessage] {
  let n = rng.next_below(7)
  let msgs : Array[JsonRpcMessage] = []
  let mut i = 0
  while i < n {
    msgs.push(gen_message(rng))
    i = i + 1
  }
  msgs
}

///|
/// 随机 `JsonRpcMessage` 序列生成器（封装为 @infra_pbt.Gen）。
fn gen_message_sequence() -> @infra_pbt.Gen[Array[JsonRpcMessage]] {
  @infra_pbt.Gen::new(fn(rng) { gen_message_seq(rng) })
}

///|
/// 顺序拼接两段 `Bytes`，返回新 `Bytes`（测试本地 helper）。
fn pf_concat(a : Bytes, b : Bytes) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < a.length() {
    arr.push(a[i])
    i = i + 1
  }
  i = 0
  while i < b.length() {
    arr.push(b[i])
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
/// 将一个消息序列依次写帧后拼接进单一 `FrameReader`，反复 `next` 逐条切出，
/// 返回切出的消息序列；遇到错误或在序列耗尽前出现 `Ok(None)` 则返回 `None`
/// （视为往返失败）。要求最终缓冲恰好为空（最后一次 `next` 为 `Ok(None)`）。
fn drain_frames(msgs : Array[JsonRpcMessage]) -> Array[JsonRpcMessage]? {
  // 依次写帧并拼接为单一字节流。
  let mut stream : Bytes = Bytes::from_array([])
  for m in msgs {
    stream = pf_concat(stream, encode_framed(m))
  }
  // 逐条切出。
  let out : Array[JsonRpcMessage] = []
  let mut reader = FrameReader::new().push(stream)
  let mut done = false
  while not(done) {
    match reader.next() {
      Ok(Some((msg, rest))) => {
        out.push(msg)
        reader = rest
      }
      Ok(None) => done = true
      Err(_) => return None
    }
  }
  Some(out)
}

// ---------------------------------------------------------------------------
// 属性测试（Property 12）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 12: 头部帧往返（round_trip 模板）
///
/// 对任意由生成器产出的合法 `JsonRpcMessage` `m`，经「写帧 → Bytes → 解帧」的
/// 往返应还原为相等消息（`decode_framed(encode_framed(m)) ≡ m`）。复用
/// @infra_pbt 的 `round_trip` 往返断言模板，默认迭代 100 次（满足 ≥100 迭代）。
///
/// **Validates: Requirements 2.1, 2.2**
test "Feature: lsp, Property 12: decode_framed(encode_framed(m)) round-trips (round_trip template)" {
  let ok = @infra_pbt.round_trip(
    gen_json_rpc_message(),
    encode_framed,
    decode_framed_opt,
  )
  assert_true(ok)
}

///|
/// Feature: lsp, Property 12: 头部帧往返（holds_for_all 模板）
///
/// 同一往返性质的直接谓词形式：对任意生成的消息 `m`，
/// `decode_framed(encode_framed(m))` 应恰好为 `Ok(m)`。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 2.1, 2.2**
test "Feature: lsp, Property 12: decode_framed(encode_framed(m)) equals Ok(m) (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(gen_json_rpc_message(), fn(m) {
    decode_framed(encode_framed(m)) == Ok(m)
  })
  assert_true(ok)
}

///|
/// Feature: lsp, Property 12: 多消息依次写帧后由 FrameReader 逐条切出与原序列按序相等
///
/// 对任意 `JsonRpcMessage` 序列，依次 `encode_framed` 拼接进单一缓冲后，由
/// `FrameReader` 反复 `next` 逐条切出的消息序列与原序列按序逐条相等，且最终缓冲
/// 为空（最后一次 `next` 为 `Ok(None)`）。复用 @infra_pbt 的 `holds_for_all`
/// 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 2.1, 2.2**
test "Feature: lsp, Property 12: FrameReader cuts a message sequence equal to the original in order" {
  let ok = @infra_pbt.holds_for_all(gen_message_sequence(), fn(msgs) {
    match drain_frames(msgs) {
      Some(out) => out == msgs
      None => false
    }
  })
  assert_true(ok)
}
