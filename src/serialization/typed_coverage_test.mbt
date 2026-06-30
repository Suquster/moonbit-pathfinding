// typed_coverage_test.mbt —— 类型化编解码（typed.mbt）的边界/错误分支覆盖。
//
// 复用同包测试辅助 `jc_field` / `jc_msg` / `jc_schema`（见 json_coverage_test.mbt）。
// 补齐 get_or_default 的未设置默认、UTF-8 多字节码点编解码与 lossy 还原、各类
// 类型不符的编码/解码错误与错误向上传播等冷分支，作为类型化模型的负例回归。

///|
/// 编码（期望成功，否则 abort 让测试失败）。
fn tc_enc(schema : ProtoSchema, name : String, m : TypedMessage) -> Bytes {
  match encode_typed(schema, name, m) {
    Ok(b) => b
    Err(e) => abort("encode_typed 不应失败：\{e}")
  }
}

///|
/// 解码（期望成功）。
fn tc_dec(schema : ProtoSchema, name : String, b : Bytes) -> TypedMessage {
  match decode_typed(schema, name, b) {
    Ok(m) => m
    Err(e) => abort("decode_typed 不应失败：\{e}")
  }
}

///|
fn tc_enc_err(schema : ProtoSchema, name : String, m : TypedMessage) -> Bool {
  match encode_typed(schema, name, m) {
    Ok(_) => false
    Err(_) => true
  }
}

///|
fn tc_dec_err(schema : ProtoSchema, name : String, b : Bytes) -> Bool {
  match decode_typed(schema, name, b) {
    Ok(_) => false
    Err(_) => true
  }
}

// ───────────────────────── get_or_default 默认补齐 ─────────────────────────

///|
test "get_or_default returns value, scalar/bytes default, empty list/map" {
  let schema = jc_schema([
    jc_msg(
      "M",
      [
        jc_field("a", 1, PInt32, LSingular),
        jc_field("b", 10, PBytes, LSingular),
        jc_field("r", 20, PInt32, LRepeated(packed=true)),
      ],
      [MapEntry::{ name: "m", number: 30, key: PInt32, value: PInt32 }],
    ),
  ])
  let pmsg = match schema.message("M") {
    Some(p) => p
    None => abort("schema 应含 M")
  }
  let set1 = TypedMessage::new().set(1, TInt(7L))
  assert_true(set1.get_or_default(pmsg, 1) == TInt(7L)) // Some(v)
  let empty = TypedMessage::new()
  assert_true(empty.get_or_default(pmsg, 1) == TInt(0L)) // 标量默认
  assert_true(empty.get_or_default(pmsg, 10) == TBytesV(b"")) // bytes 默认
  assert_true(empty.get_or_default(pmsg, 20) == TList([])) // repeated 空
  assert_true(empty.get_or_default(pmsg, 30) == TMap([])) // map 空
}

// ─────────────────────── UTF-8 多字节编解码与 lossy ────────────────────────

///|
test "encode/decode_typed round-trips multibyte UTF-8 and bytes" {
  let schema = jc_schema([
    jc_msg(
      "M",
      [
        jc_field("s", 1, PString, LSingular),
        jc_field("d", 2, PBytes, LSingular),
      ],
      [],
    ),
  ])
  // "é中𝄞" 覆盖 2/3/4 字节码点（string_to_bytes 与 bytes_to_string 多字节分支）。
  let m = TypedMessage::new()
    .set(1, TStringV("é中𝄞"))
    .set(2, TBytesV(b"\x00\x01\xff"))
  let out = tc_dec(schema, "M", tc_enc(schema, "M", m))
  assert_true(out.get(1) == Some(TStringV("é中𝄞")))
  assert_true(out.get(2) == Some(TBytesV(b"\x00\x01\xff")))
}

///|
test "decode_typed lossily replaces invalid UTF-8 bytes as a string" {
  // 写为 bytes（非法 UTF-8），按 string 解释 → U+FFFD 替换（保证终止）。
  let enc_schema = jc_schema([
    jc_msg("M", [jc_field("f", 1, PBytes, LSingular)], []),
  ])
  let dec_schema = jc_schema([
    jc_msg("M", [jc_field("f", 1, PString, LSingular)], []),
  ])
  let m = TypedMessage::new().set(1, TBytesV(b"\xff\xfe"))
  let out = tc_dec(dec_schema, "M", tc_enc(enc_schema, "M", m))
  assert_true(out.get(1) is Some(TStringV(_)))
}

// ─────────────────────────────── 编码错误 ──────────────────────────────────

///|
test "encode_typed rejects mismatched and malformed values" {
  // 单值标量类型不符。
  let s1 = jc_schema([jc_msg("M", [jc_field("a", 1, PInt32, LSingular)], [])])
  assert_true(
    tc_enc_err(s1, "M", TypedMessage::new().set(1, TList([TInt(1L)]))),
  )
  // repeated 字段被赋非 TList。
  let s2 = jc_schema([
    jc_msg("M", [jc_field("r", 1, PInt32, LRepeated(packed=true))], []),
  ])
  assert_true(tc_enc_err(s2, "M", TypedMessage::new().set(1, TInt(5L))))
  // packed repeated 元素类型不符。
  assert_true(
    tc_enc_err(s2, "M", TypedMessage::new().set(1, TList([TStringV("x")]))),
  )
  // 非 packed repeated 元素类型不符。
  let s3 = jc_schema([
    jc_msg("M", [jc_field("r", 1, PInt32, LRepeated(packed=false))], []),
  ])
  assert_true(
    tc_enc_err(s3, "M", TypedMessage::new().set(1, TList([TStringV("x")]))),
  )
  // 未知消息名。
  assert_true(tc_enc_err(s1, "NOPE", TypedMessage::new().set(1, TInt(1L))))
}

///|
test "encode_typed map errors: non-map, bad key, bad value" {
  let sch = fn(key : ProtoType, value : ProtoType) -> ProtoSchema {
    jc_schema([
      jc_msg("M", [], [MapEntry::{ name: "m", number: 1, key, value }]),
    ])
  }
  // map 字段被赋非 TMap。
  assert_true(
    tc_enc_err(sch(PInt32, PInt32), "M", TypedMessage::new().set(1, TInt(9L))),
  )
  // map 键类型不符。
  assert_true(
    tc_enc_err(
      sch(PInt32, PInt32),
      "M",
      TypedMessage::new().set(1, TMap([(TStringV("k"), TInt(1L))])),
    ),
  )
  // map 值类型不符。
  assert_true(
    tc_enc_err(
      sch(PInt32, PInt32),
      "M",
      TypedMessage::new().set(1, TMap([(TInt(1L), TStringV("v"))])),
    ),
  )
}

///|
test "encode_typed propagates nested message encode error" {
  let schema = jc_schema([
    jc_msg("M", [jc_field("inner", 1, PMessage("Inner"), LSingular)], []),
    jc_msg("Inner", [jc_field("g", 1, PInt32, LSingular)], []),
  ])
  // 内层字段类型不符 → 编码错误向上传播。
  let bad_inner = TypedMessage::new().set(1, TStringV("x"))
  let m = TypedMessage::new().set(1, TMsg(bad_inner))
  assert_true(tc_enc_err(schema, "M", m))
}

// ─────────────────────────────── 解码错误 ──────────────────────────────────

///|
test "decode_typed rejects wire-type mismatch and unknown message" {
  // 编码为 int（varint），按 string 解码 → wire 类型不符。
  let enc_schema = jc_schema([
    jc_msg("M", [jc_field("f", 1, PInt32, LSingular)], []),
  ])
  let dec_schema = jc_schema([
    jc_msg("M", [jc_field("f", 1, PString, LSingular)], []),
  ])
  let bytes = tc_enc(enc_schema, "M", TypedMessage::new().set(1, TInt(5L)))
  assert_true(tc_dec_err(dec_schema, "M", bytes))
  // 未知消息名。
  assert_true(tc_dec_err(enc_schema, "NOPE", bytes))
}

///|
test "decode_typed preserves and re-emits unknown fields" {
  // 用富 schema 编码字段 2，再以仅含字段 1 的 schema 解码 → 字段 2 进 unknown。
  let full = jc_schema([
    jc_msg(
      "M",
      [jc_field("a", 1, PInt32, LSingular), jc_field("b", 2, PInt32, LSingular)],
      [],
    ),
  ])
  let lean = jc_schema([jc_msg("M", [jc_field("a", 1, PInt32, LSingular)], [])])
  let bytes = tc_enc(
    full,
    "M",
    TypedMessage::new().set(1, TInt(1L)).set(2, TInt(2L)),
  )
  let decoded = tc_dec(lean, "M", bytes)
  // 重新编码保留未知字段，再用富 schema 解码可读回字段 2。
  let re = tc_enc(lean, "M", decoded)
  let back = tc_dec(full, "M", re)
  assert_true(back.get(2) == Some(TInt(2L)))
}
