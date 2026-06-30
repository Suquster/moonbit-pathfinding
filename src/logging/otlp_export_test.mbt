// otlp_export_test.mbt —— 方向七 T7.1「真·OTLP 导出器」的属性测试与回归测试。
//
// 核心验证手段：把 span 经 `otlp_export_trace` 编码为 OTLP/protobuf 字节后，
// **用方向九 @serialization 的真实 protobuf 解码器逐层解码**（独立 oracle），
// 断言 trace/span id 长度与字节、名称、kind、起止时间、属性条数、事件条数与
// 状态逐字段往返一致。这证明导出字节确为合法 protobuf、字段编号与 OTel 数据
// 模型对齐，可被真实 collector 接收（Requirement 7.*）。

///|
/// 测试侧独立 oracle：64 位无符号整数大端 8 字节（与导出器实现相互印证）。
fn otlp_t_u64_be(v : UInt64) -> Bytes {
  let a : Array[Byte] = []
  for i in 0..<8 {
    a.push(((v >> ((7 - i) * 8)) & 0xFFUL).to_int().to_byte())
  }
  Bytes::from_array(a)
}

///|
/// 测试侧独立 oracle：16 字节 trace_id（高 8 字节零 + 低 8 字节大端）。
fn otlp_t_trace_bytes(value : Int64) -> Bytes {
  let a : Array[Byte] = []
  for _ in 0..<8 {
    a.push((0).to_byte())
  }
  for b in otlp_t_u64_be(value.reinterpret_as_uint64()) {
    a.push(b)
  }
  Bytes::from_array(a)
}

///|
/// 测试侧独立 oracle：ASCII 字符串字节（共享生成器 `sh_string` 取值恒为 ASCII，
/// 故每字符占一字节，等同其 UTF-8 形态）。
fn otlp_t_ascii(s : String) -> Bytes {
  let a : Array[Byte] = []
  for ch in s {
    a.push(ch.to_int().to_byte())
  }
  Bytes::from_array(a)
}

///|
/// 无 schema 解码：把 protobuf 字节解为通用 `Message`（字段表）。
fn otlp_t_decode(b : Bytes) -> @serialization.Message {
  match @serialization.decode(b, @serialization.Schema::empty()) {
    Ok(m) => m
    Err(_) => @serialization.Message::from_fields([])
  }
}

///|
/// 取出消息中某字段号的全部取值（保序）。
fn otlp_t_values(
  m : @serialization.Message,
  num : Int,
) -> Array[@serialization.FieldValue] {
  let out : Array[@serialization.FieldValue] = []
  for fe in m.fields {
    if fe.number == num {
      out.push(fe.value)
    }
  }
  out
}

///|
/// 取出消息中某字段号的首个取值。
fn otlp_t_first(
  m : @serialization.Message,
  num : Int,
) -> @serialization.FieldValue? {
  for fe in m.fields {
    if fe.number == num {
      return Some(fe.value)
    }
  }
  None
}

///|
/// 从 `FieldValue` 抽取长度分隔字节。
fn otlp_t_as_bytes(v : @serialization.FieldValue) -> Bytes? {
  match v {
    @serialization.VBytes(b) => Some(b)
    _ => None
  }
}

///|
/// 从 `FieldValue` 抽取 varint。
fn otlp_t_as_varint(v : @serialization.FieldValue) -> UInt64? {
  match v {
    @serialization.VVarint(u) => Some(u)
    _ => None
  }
}

///|
/// 从 `FieldValue` 抽取 fixed64。
fn otlp_t_as_i64(v : @serialization.FieldValue) -> UInt64? {
  match v {
    @serialization.VI64(u) => Some(u)
    _ => None
  }
}

///|
/// 从一条 OTLP `ExportTraceServiceRequest` 字节中逐层解出全部 `Span` 子消息：
/// request(1) → ResourceSpans(2) → ScopeSpans(2) → Span。
fn otlp_t_extract_spans(bytes : Bytes) -> Array[@serialization.Message] {
  let spans : Array[@serialization.Message] = []
  let req = otlp_t_decode(bytes)
  for rsv in otlp_t_values(req, 1) {
    match otlp_t_as_bytes(rsv) {
      Some(rb) => {
        let rs = otlp_t_decode(rb)
        for ssv in otlp_t_values(rs, 2) {
          match otlp_t_as_bytes(ssv) {
            Some(sb) => {
              let ss = otlp_t_decode(sb)
              for spv in otlp_t_values(ss, 2) {
                match otlp_t_as_bytes(spv) {
                  Some(pb) => spans.push(otlp_t_decode(pb))
                  None => ()
                }
              }
            }
            None => ()
          }
        }
      }
      None => ()
    }
  }
  spans
}

///|
/// 测试侧 SpanKind → OTLP 枚举值映射（独立 oracle）。
fn otlp_t_kind(k : SpanKind) -> UInt64 {
  match k {
    Internal => 1
    Server => 2
    Client => 3
    Producer => 4
    Consumer => 5
  }
}

///|
/// 随机生成一条 OTLP span 输入（确定性、可重放）。
fn otlp_t_gen(rng : @infra_pbt.Rng) -> OtlpSpanInput {
  let id = SpanId::{ value: rng.next_range(0, 1_000_000).to_int64() }
  let parent = if rng.next_bool() {
    Some(SpanId::{ value: rng.next_range(0, 1_000_000).to_int64() })
  } else {
    None
  }
  let start = rng.next_range(0, 2_000_000_000).to_int64()
  let end = if rng.next_bool() {
    Some(start + rng.next_range(0, 1000).to_int64())
  } else {
    None
  }
  let sd = SpanData::new(Span::{ id, parent, start, end })
  let na = rng.next_range(0, 4)
  for i in 0..<na {
    sd.set_attribute("a\{i}", sh_scalar_value(rng))
  }
  let ne = rng.next_range(0, 3)
  for j in 0..<ne {
    let efields : Map[String, Value] = {}
    let nf = rng.next_range(0, 3)
    for k in 0..<nf {
      efields["e\{k}"] = sh_scalar_value(rng)
    }
    sd.add_event("ev\{j}", rng.next_range(-100, 100).to_int64(), efields)
  }
  match rng.next_below(3) {
    0 => sd.set_status(SpanStatus::Unset)
    1 => sd.set_status(SpanStatus::Ok)
    _ => sd.set_status(SpanStatus::Error)
  }
  match rng.next_below(5) {
    0 => sd.set_kind(Internal)
    1 => sd.set_kind(Server)
    2 => sd.set_kind(Client)
    3 => sd.set_kind(Producer)
    _ => sd.set_kind(Consumer)
  }
  OtlpSpanInput::{
    trace: TraceId::{ value: rng.next_range(0, 1_000_000).to_int64() },
    name: sh_string(rng),
    data: sd,
  }
}

///|
/// T7.1：导出字节经真实 protobuf 解码器逐字段往返一致（≥100 迭代）。
test "T7.1: OTLP export round-trips span structure through a real decoder" {
  let rng = @infra_pbt.rng_new(0x07_10_20_26)
  for _iter in 0..<100 {
    let n = rng.next_range(0, 3)
    let inputs : Array[OtlpSpanInput] = []
    for _ in 0..<n {
      inputs.push(otlp_t_gen(rng))
    }
    let bytes = otlp_export_trace(inputs)
    let spans = otlp_t_extract_spans(bytes)
    assert_eq(spans.length(), inputs.length())
    for idx in 0..<inputs.length() {
      let inp = inputs[idx]
      let sp = spans[idx]
      // trace_id（字段 1，16 字节）与 span_id（字段 2，8 字节）。
      let tid = otlp_t_as_bytes(otlp_t_first(sp, 1).unwrap()).unwrap()
      assert_true(tid == otlp_t_trace_bytes(inp.trace.value))
      let sid = otlp_t_as_bytes(otlp_t_first(sp, 2).unwrap()).unwrap()
      assert_true(
        sid == otlp_t_u64_be(inp.data.span.id.value.reinterpret_as_uint64()),
      )
      // parent_span_id（字段 4）仅在存在父 span 时出现。
      match inp.data.span.parent {
        Some(p) => {
          let pid = otlp_t_as_bytes(otlp_t_first(sp, 4).unwrap()).unwrap()
          assert_true(pid == otlp_t_u64_be(p.value.reinterpret_as_uint64()))
        }
        None => assert_true(otlp_t_first(sp, 4) is None)
      }
      // name（字段 5）。
      let nm = otlp_t_as_bytes(otlp_t_first(sp, 5).unwrap()).unwrap()
      assert_true(nm == otlp_t_ascii(inp.name))
      // kind（字段 6，varint）。
      assert_eq(
        otlp_t_as_varint(otlp_t_first(sp, 6).unwrap()).unwrap(),
        otlp_t_kind(inp.data.kind),
      )
      // start_time（字段 7，fixed64）与 end_time（字段 8，仅在已结束时）。
      assert_eq(
        otlp_t_as_i64(otlp_t_first(sp, 7).unwrap()).unwrap(),
        inp.data.span.start.reinterpret_as_uint64(),
      )
      match inp.data.span.end {
        Some(e) =>
          assert_eq(
            otlp_t_as_i64(otlp_t_first(sp, 8).unwrap()).unwrap(),
            e.reinterpret_as_uint64(),
          )
        None => assert_true(otlp_t_first(sp, 8) is None)
      }
      // 属性条数（字段 9）与事件条数（字段 11）。
      assert_eq(otlp_t_values(sp, 9).length(), inp.data.attributes.length())
      assert_eq(otlp_t_values(sp, 11).length(), inp.data.events.length())
      // 状态（字段 15）仅在非 Unset 时出现，且其 code（字段 3）匹配。
      match inp.data.status {
        Unset => assert_true(otlp_t_first(sp, 15) is None)
        SpanStatus::Ok => {
          let st = otlp_t_decode(
            otlp_t_as_bytes(otlp_t_first(sp, 15).unwrap()).unwrap(),
          )
          assert_eq(otlp_t_as_varint(otlp_t_first(st, 3).unwrap()).unwrap(), 1)
        }
        SpanStatus::Error => {
          let st = otlp_t_decode(
            otlp_t_as_bytes(otlp_t_first(sp, 15).unwrap()).unwrap(),
          )
          assert_eq(otlp_t_as_varint(otlp_t_first(st, 3).unwrap()).unwrap(), 2)
        }
      }
    }
  }
}

///|
/// T7.1：导出是确定性的——相同输入两次导出字节逐字节一致（三后端可对比）。
test "T7.1: OTLP export is deterministic across repeated calls" {
  let rng = @infra_pbt.rng_new(0x5EED_5EED)
  for _iter in 0..<100 {
    let n = rng.next_range(1, 4)
    let inputs : Array[OtlpSpanInput] = []
    for _ in 0..<n {
      inputs.push(otlp_t_gen(rng))
    }
    assert_true(otlp_export_trace(inputs) == otlp_export_trace(inputs))
  }
}

///|
/// T7.1：`otlp_any_value` 标量映射到正确的 AnyValue 字段并经解码器还原。
test "T7.1: otlp_any_value encodes scalars to the correct AnyValue field" {
  // VStr → string_value(1)
  let s = otlp_t_decode(@serialization.encode(otlp_any_value(VStr("hi"))))
  assert_true(
    otlp_t_as_bytes(otlp_t_first(s, 1).unwrap()).unwrap() == otlp_t_ascii("hi"),
  )
  // VBool → bool_value(2)
  let b = otlp_t_decode(@serialization.encode(otlp_any_value(VBool(true))))
  assert_eq(otlp_t_as_varint(otlp_t_first(b, 2).unwrap()).unwrap(), 1)
  // VInt → int_value(3), 两补码 varint
  let i = otlp_t_decode(@serialization.encode(otlp_any_value(VInt(-7L))))
  assert_eq(
    otlp_t_as_varint(otlp_t_first(i, 3).unwrap()).unwrap(),
    (-7L).reinterpret_as_uint64(),
  )
  // VFloat → double_value(4), IEEE-754 位型
  let d = otlp_t_decode(@serialization.encode(otlp_any_value(VFloat(1.5))))
  assert_eq(
    otlp_t_as_i64(otlp_t_first(d, 4).unwrap()).unwrap(),
    @serialization.double_to_bits(1.5),
  )
}

///|
/// T7.1：`otlp_any_value` 对嵌套 `VMap` / `VList` 产出 kvlist/array 子消息。
test "T7.1: otlp_any_value encodes nested map and list values" {
  // VList → array_value(5) → ArrayValue{ values=1 repeated AnyValue }
  let lst = otlp_any_value(VList([VInt(1L), VInt(2L), VInt(3L)]))
  let arrmsg = otlp_t_decode(
    otlp_t_as_bytes(
      otlp_t_first(otlp_t_decode(@serialization.encode(lst)), 5).unwrap(),
    ).unwrap(),
  )
  assert_eq(otlp_t_values(arrmsg, 1).length(), 3)
  // VMap → kvlist_value(6) → KeyValueList{ values=1 repeated KeyValue }
  let m : Map[String, Value] = { "x": VInt(1L), "y": VStr("z") }
  let kvlmsg = otlp_t_decode(
    otlp_t_as_bytes(
      otlp_t_first(
        otlp_t_decode(@serialization.encode(otlp_any_value(VMap(m)))),
        6,
      ).unwrap(),
    ).unwrap(),
  )
  assert_eq(otlp_t_values(kvlmsg, 1).length(), 2)
}

///|
/// T7.1：具体回归——一条命名 span 的关键字段编码为 OTLP 后逐字段可读。
test "T7.1: a concrete named span encodes the expected OTLP fields" {
  let sd = SpanData::new(Span::{
    id: SpanId::{ value: 0x0102L },
    parent: None,
    start: 1000L,
    end: Some(2000L),
  })
  sd.set_kind(Server)
  sd.set_status(SpanStatus::Error)
  sd.set_attribute("http.method", VStr("GET"))
  let bytes = otlp_export_trace([
    OtlpSpanInput::{
      trace: TraceId::{ value: 0xABCDL },
      name: "GET /",
      data: sd,
    },
  ])
  let spans = otlp_t_extract_spans(bytes)
  assert_eq(spans.length(), 1)
  let sp = spans[0]
  assert_true(
    otlp_t_as_bytes(otlp_t_first(sp, 5).unwrap()).unwrap() ==
    otlp_t_ascii("GET /"),
  )
  assert_eq(otlp_t_as_varint(otlp_t_first(sp, 6).unwrap()).unwrap(), 2) // Server
  assert_eq(
    otlp_t_as_i64(otlp_t_first(sp, 7).unwrap()).unwrap(),
    1000L.reinterpret_as_uint64(),
  )
  assert_eq(otlp_t_values(sp, 9).length(), 1) // one attribute
  let st = otlp_t_decode(
    otlp_t_as_bytes(otlp_t_first(sp, 15).unwrap()).unwrap(),
  )
  assert_eq(otlp_t_as_varint(otlp_t_first(st, 3).unwrap()).unwrap(), 2) // Error
}

///|
/// T7.1：非 ASCII 名称/属性按 **UTF-8** 编码（覆盖 2/3/4 字节码点分支）。
/// 字符串 `"é中𝄞"` 含 U+00E9（2 字节 C3 A9）、U+4E2D（3 字节 E4 B8 AD）、
/// U+1D11E（4 字节 F0 9D 84 9E），用手算的 UTF-8 字节作独立 oracle 校验
/// span name（字段 5）与字符串属性值（AnyValue string_value，字段 1）。
test "T7.1: OTLP export encodes non-ASCII text as UTF-8" {
  let expect : Bytes = [
    0xC3, 0xA9, // é  U+00E9
     0xE4, 0xB8, 0xAD, // 中 U+4E2D
     0xF0, 0x9D, 0x84, 0x9E, // 𝄞 U+1D11E
  ]
  let sd = SpanData::new(Span::{
    id: SpanId::{ value: 7L },
    parent: None,
    start: 1L,
    end: None,
  })
  sd.set_attribute("k", VStr("é中𝄞"))
  let bytes = otlp_export_trace([
    OtlpSpanInput::{
      trace: TraceId::{ value: 9L },
      name: "é中𝄞",
      data: sd,
    },
  ])
  let sp = otlp_t_extract_spans(bytes)[0]
  // span name（字段 5）UTF-8 一致。
  assert_true(otlp_t_as_bytes(otlp_t_first(sp, 5).unwrap()).unwrap() == expect)
  // 字符串属性值：KeyValue(字段 9) -> value(字段 2) -> AnyValue.string_value(字段 1)。
  let kv = otlp_t_decode(otlp_t_as_bytes(otlp_t_first(sp, 9).unwrap()).unwrap())
  let any = otlp_t_decode(
    otlp_t_as_bytes(otlp_t_first(kv, 2).unwrap()).unwrap(),
  )
  assert_true(otlp_t_as_bytes(otlp_t_first(any, 1).unwrap()).unwrap() == expect)
}
