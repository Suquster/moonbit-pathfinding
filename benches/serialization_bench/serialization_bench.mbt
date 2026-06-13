// benches/serialization_bench — Serialization_Framework 旗舰深化性能基准与回归 guard。
//
// 对应 design.md §4.10（R7）。四类工作负载：
//   * varint 密集：repeated int32 大量小整型（packed）；
//   * 大 repeated：repeated int64 长序列（packed 与非 packed 对比紧凑度）；
//   * 嵌套深度：链式嵌套消息（Node{v; next}）；
//   * 字符串密集：repeated string 大量字符串。
// 对 encode_typed / decode_typed / encode_canonical / encode_json 计时。
//
// 回归 guard（R7.3）：
//   * 往返正确性——各工作负载 decode_typed ∘ encode_typed 还原原消息；
//   * packed 紧凑度——大 repeated 的 packed 编码严格短于非 packed；
//   * 确定编码字节基线——固定 varint 工作负载的 encode_typed 字节长度精确等于内联
//     基线，偏离给出可审计失败报告。
//
// 运行（R7.4）：
//   moon test  -p Suquster/moonbit-pathfinding/benches/serialization_bench --target wasm-gc
//   moon bench -p Suquster/moonbit-pathfinding/benches/serialization_bench --target native
// native 运行前须先：export LIBRARY_PATH=/usr/lib64:/usr/lib
//
// _Requirements: 7.1, 7.2, 7.3, 7.4_

// ---------------------------------------------------------------------------
// 工作负载 schema 与消息构造
// ---------------------------------------------------------------------------

///|
/// 由 `.proto` 源构造富模式（失败回退空模式）。
fn schema_of(src : String) -> @ser.ProtoSchema {
  match @ser.parse_proto_full(src) {
    Ok(s) => s
    Err(_) => @ser.ProtoSchema::empty()
  }
}

///|
/// varint 密集：repeated int32（packed）。
fn varint_schema() -> @ser.ProtoSchema {
  schema_of(
    (
      #|syntax = "proto3";
      #|message M { repeated int32 xs = 1; }
    ),
  )
}

///|
/// 大 repeated：repeated int64（packed 由参数决定）。
fn repeated_schema(packed : Bool) -> @ser.ProtoSchema {
  if packed {
    schema_of(
      (
        #|syntax = "proto3";
        #|message M { repeated int64 xs = 1; }
      ),
    )
  } else {
    schema_of(
      (
        #|syntax = "proto3";
        #|message M { repeated int64 xs = 1 [packed = false]; }
      ),
    )
  }
}

///|
/// 嵌套深度：Node{ v; next }。
fn nest_schema() -> @ser.ProtoSchema {
  schema_of(
    (
      #|syntax = "proto3";
      #|message Node { int32 v = 1; Node next = 2; }
    ),
  )
}

///|
/// 字符串密集：repeated string。
fn string_schema() -> @ser.ProtoSchema {
  schema_of(
    (
      #|syntax = "proto3";
      #|message S { repeated string ss = 1; }
    ),
  )
}

///|
/// 构造 `n` 个 int32 元素（0..n-1）的消息。
fn varint_msg(n : Int) -> @ser.TypedMessage {
  let elems : Array[@ser.TypedValue] = []
  for i in 0..<n {
    elems.push(@ser.TInt(i.to_int64()))
  }
  @ser.TypedMessage::new().set(1, @ser.TList(elems))
}

///|
/// 构造 `n` 个 int64 元素的消息。
fn repeated_i64_msg(n : Int) -> @ser.TypedMessage {
  let elems : Array[@ser.TypedValue] = []
  for i in 0..<n {
    elems.push(@ser.TInt((i * 1000 + 7).to_int64()))
  }
  @ser.TypedMessage::new().set(1, @ser.TList(elems))
}

///|
/// 构造深度 `depth` 的链式嵌套消息（每节点 v 取非默认值以避免默认省略）。
fn nest_msg(depth : Int) -> @ser.TypedMessage {
  let base = @ser.TypedMessage::new().set(1, @ser.TInt((depth + 1).to_int64()))
  if depth <= 0 {
    base
  } else {
    base.set(2, @ser.TMsg(nest_msg(depth - 1)))
  }
}

///|
/// 构造 `n` 个固定字符串的消息。
fn string_msg(n : Int) -> @ser.TypedMessage {
  let elems : Array[@ser.TypedValue] = []
  for i in 0..<n {
    elems.push(@ser.TStringV("user_" + i.to_string() + "@example.com"))
  }
  @ser.TypedMessage::new().set(1, @ser.TList(elems))
}

// ---------------------------------------------------------------------------
// 冒烟 guard（correctness）：四类工作负载二进制往返自洽
// ---------------------------------------------------------------------------

///|
/// 校验某工作负载 decode_typed ∘ encode_typed 还原原消息。
fn roundtrips(
  schema : @ser.ProtoSchema,
  name : String,
  msg : @ser.TypedMessage,
) -> Bool {
  match @ser.encode_typed(schema, name, msg) {
    Ok(bytes) =>
      match @ser.decode_typed(schema, name, bytes) {
        Ok(out) => out == msg
        Err(_) => false
      }
    Err(_) => false
  }
}

///|
/// Smoke: 四类工作负载二进制往返自洽（保护基准工作负载的正确性，R7.1）。
test "smoke: four workloads binary round-trip" {
  assert_true(roundtrips(varint_schema(), "M", varint_msg(200)))
  assert_true(roundtrips(repeated_schema(true), "M", repeated_i64_msg(200)))
  assert_true(roundtrips(repeated_schema(false), "M", repeated_i64_msg(200)))
  assert_true(roundtrips(nest_schema(), "Node", nest_msg(64)))
  assert_true(roundtrips(string_schema(), "S", string_msg(128)))
}

// ---------------------------------------------------------------------------
// 回归 guard（R7.3）：packed 紧凑度 + 确定编码字节基线
// ---------------------------------------------------------------------------

///|
/// 编码字节长度（失败回退 -1）。
fn encoded_len(
  schema : @ser.ProtoSchema,
  name : String,
  msg : @ser.TypedMessage,
) -> Int {
  match @ser.encode_typed(schema, name, msg) {
    Ok(bytes) => bytes.length()
    Err(_) => -1
  }
}

///|
/// Guard: 大 repeated 的 packed 编码严格短于非 packed（紧凑度回归保护，R7.3）。
test "guard: packed encoding is strictly smaller than non-packed" {
  let n = 256
  let msg = repeated_i64_msg(n)
  let packed_len = encoded_len(repeated_schema(true), "M", msg)
  let nonpacked_len = encoded_len(repeated_schema(false), "M", msg)
  if packed_len <= 0 || nonpacked_len <= 0 {
    fail("SER-BENCH GUARD FAIL [encode]: 工作负载编码失败")
  }
  if packed_len >= nonpacked_len {
    fail(
      "SER-BENCH GUARD FAIL [compactness]: packed len " +
      packed_len.to_string() +
      " 未短于 non-packed len " +
      nonpacked_len.to_string() +
      "（n=" +
      n.to_string() +
      "）；可能丢失 packed 紧凑度。",
    )
  }
}

///|
/// Guard: 固定 varint 工作负载的确定编码字节长度精确等于内联基线（R7.3）。
///
/// 10 个元素 0..9（packed int32）：tag(1) + 长度前缀(1) + 载荷(10×1) = 12 字节。
test "guard: deterministic encoded size matches inline baseline" {
  let baseline = 12
  let got = encoded_len(varint_schema(), "M", varint_msg(10))
  if got != baseline {
    fail(
      "SER-BENCH GUARD FAIL [byte-size]: varint(0..9) 编码长度 " +
      got.to_string() +
      " 偏离基线 " +
      baseline.to_string() +
      "。",
    )
  }
}

// ---------------------------------------------------------------------------
// 原生基准（@bench.T）：四类工作负载 × 编码/解码/规范/JSON（moon bench 下执行）
// ---------------------------------------------------------------------------

///|
/// 大 repeated（packed）：encode_typed / decode_typed / encode_canonical 计时。
test "bench: large repeated int64 encode/decode/canonical" (b : @bench.T) {
  let schema = repeated_schema(true)
  let msg = repeated_i64_msg(1000)
  let bytes = match @ser.encode_typed(schema, "M", msg) {
    Ok(x) => x
    Err(_) => return
  }
  b.bench(name="ser_repeated_encode_typed", fn() {
    b.keep(@ser.encode_typed(schema, "M", msg))
  })
  b.bench(name="ser_repeated_decode_typed", fn() {
    b.keep(@ser.decode_typed(schema, "M", bytes))
  })
  b.bench(name="ser_repeated_encode_canonical", fn() {
    b.keep(@ser.encode_canonical(schema, "M", msg))
  })
}

///|
/// varint 密集 + 字符串密集 + 嵌套深度：encode_typed 计时。
test "bench: varint-dense, string-dense, nesting encode_typed" (b : @bench.T) {
  let vschema = varint_schema()
  let vmsg = varint_msg(1000)
  let sschema = string_schema()
  let smsg = string_msg(500)
  let nschema = nest_schema()
  let nmsg = nest_msg(200)
  b.bench(name="ser_varint_encode_typed", fn() {
    b.keep(@ser.encode_typed(vschema, "M", vmsg))
  })
  b.bench(name="ser_string_encode_typed", fn() {
    b.keep(@ser.encode_typed(sschema, "S", smsg))
  })
  b.bench(name="ser_nesting_encode_typed", fn() {
    b.keep(@ser.encode_typed(nschema, "Node", nmsg))
  })
}

///|
/// JSON 编解码：字符串密集工作负载的 encode_json / decode_json 计时。
test "bench: string-dense JSON encode/decode" (b : @bench.T) {
  let schema = string_schema()
  let msg = string_msg(500)
  let json = match @ser.encode_json(schema, "S", msg) {
    Ok(x) => x
    Err(_) => return
  }
  b.bench(name="ser_string_encode_json", fn() {
    b.keep(@ser.encode_json(schema, "S", msg))
  })
  b.bench(name="ser_string_decode_json", fn() {
    b.keep(@ser.decode_json(schema, "S", json))
  })
}
