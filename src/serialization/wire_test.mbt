// wire_test.mbt —— protobuf wire format 编解码（任务 7.2）的单元测试。
//
// 在 7.1 的通用往返/错误契约测试（见 serialization_test.mbt）之外，本文件聚焦
// 加固后的 wire 编解码，逐项覆盖四类 wire 类型的正确编解码与边界健壮性：
//   1. Varint：与 protobuf 规范一致的字节布局、单/多字节、64 位最大值；
//   2. I64 / I32：定长小端布局、最大值与零值；
//   3. Len：长度前缀、空字节序列、含零字节的二进制内容；
//   4. 边界：空消息、字段顺序保持、超大字段号、同号重复字段；
//   5. 错误契约（Requirement 9.4）：过长 varint、定长截断、Len 越界均返回含
//      字节偏移的错误，且不产生部分构造对象。
//
// 编解码往返性质（Property 20）与非法字节错误条件（Property 21）的属性测试由
// 任务 7.3 / 7.4 单独承载；本文件仅以确定性夹具校验逐字节正确性与边界。

// ─────────────────────────── Varint 正确编码 ─────────────────────────────

///|
/// 字段 1、Varint 150 应编码为 protobuf 规范字节 `08 96 01`（经典示例）。
test "encode varint matches protobuf canonical bytes" {
  let msg = Message::from_fields([FieldEntry::new(1, FieldValue::varint(150UL))])
  assert_true(encode(msg) == b"\x08\x96\x01")
}

///|
/// 单字节 varint（< 128）：值 1 → tag `08` + `01`。
test "encode single-byte varint" {
  let msg = Message::from_fields([FieldEntry::new(1, FieldValue::varint(1UL))])
  assert_true(encode(msg) == b"\x08\x01")
}

///|
/// 64 位最大值 varint 往返（最长 10 字节边界）。
test "varint max u64 roundtrips" {
  let msg = Message::from_fields([
    FieldEntry::new(1, FieldValue::varint(0xFFFFFFFFFFFFFFFFUL)),
  ])
  let bytes = encode(msg)
  // tag 1 字节 + 10 字节 varint。
  @test.assert_eq(bytes.length(), 11)
  match decode(bytes, Schema::empty()) {
    Ok(out) => assert_true(out == msg)
    Err(e) => fail("最大 varint 往返不应失败：\{e}")
  }
}

///|
/// 多个 varint 取值（含 0、边界 127/128）逐一往返。
test "varint boundary values roundtrip" {
  for v in [0UL, 127UL, 128UL, 16383UL, 16384UL, 300UL] {
    let msg = Message::from_fields([FieldEntry::new(7, FieldValue::varint(v))])
    match decode(encode(msg), Schema::empty()) {
      Ok(out) => assert_true(out == msg)
      Err(e) => fail("varint \{v} 往返不应失败：\{e}")
    }
  }
}

// ─────────────────────────── 定长 I64 / I32 ──────────────────────────────

///|
/// I64 定长小端布局：值按 8 字节低位在前写出。
test "encode fixed64 little-endian layout" {
  let msg = Message::from_fields([
    FieldEntry::new(1, FieldValue::i64(0x0102030405060708UL)),
  ])
  // tag = (1<<3)|1 = 0x09，随后 8 字节小端。
  assert_true(encode(msg) == b"\x09\x08\x07\x06\x05\x04\x03\x02\x01")
}

///|
/// I32 定长小端布局：值按 4 字节低位在前写出。
test "encode fixed32 little-endian layout" {
  let msg = Message::from_fields([
    FieldEntry::new(1, FieldValue::i32(0x01020304U)),
  ])
  // tag = (1<<3)|5 = 0x0d，随后 4 字节小端。
  assert_true(encode(msg) == b"\x0d\x04\x03\x02\x01")
}

///|
/// I64 / I32 的最大值与零值均往返。
test "fixed integers max and zero roundtrip" {
  let msg = Message::from_fields([
    FieldEntry::new(1, FieldValue::i64(0xFFFFFFFFFFFFFFFFUL)),
    FieldEntry::new(2, FieldValue::i64(0UL)),
    FieldEntry::new(3, FieldValue::i32(0xFFFFFFFFU)),
    FieldEntry::new(4, FieldValue::i32(0U)),
  ])
  match decode(encode(msg), Schema::empty()) {
    Ok(out) => assert_true(out == msg)
    Err(e) => fail("定长最大/零值往返不应失败：\{e}")
  }
}

// ──────────────────────────── 长度前缀 Len ───────────────────────────────

///|
/// Len 字段：长度前缀 + 原始字节，与 protobuf 规范一致（字段 2、字符串 "testing"）。
test "encode length-delimited matches protobuf canonical bytes" {
  let msg = Message::from_fields([
    FieldEntry::new(2, FieldValue::bytes(b"testing")),
  ])
  // tag = (2<<3)|2 = 0x12，长度 7 = 0x07，随后原始字节。
  assert_true(encode(msg) == b"\x12\x07testing")
}

///|
/// 空字节序列（长度 0）应往返为等价空 Len 字段。
test "empty length-delimited field roundtrips" {
  let msg = Message::from_fields([FieldEntry::new(1, FieldValue::bytes(b""))])
  let bytes = encode(msg)
  // tag `0a` + 长度 `00`。
  assert_true(bytes == b"\x0a\x00")
  match decode(bytes, Schema::empty()) {
    Ok(out) => assert_true(out == msg)
    Err(e) => fail("空 Len 字段往返不应失败：\{e}")
  }
}

///|
/// 含零字节的二进制内容（非文本）应原样往返。
test "binary bytes with embedded nul roundtrip" {
  let msg = Message::from_fields([
    FieldEntry::new(9, FieldValue::bytes(b"\x00\xff\x00\x10\x00")),
  ])
  match decode(encode(msg), Schema::empty()) {
    Ok(out) => assert_true(out == msg)
    Err(e) => fail("含零字节内容往返不应失败：\{e}")
  }
}

// ─────────────────────────────── 边界 ────────────────────────────────────

///|
/// 空消息编码为空字节，解码回空消息。
test "empty message encodes to empty bytes" {
  let bytes = encode(Message::empty())
  @test.assert_eq(bytes.length(), 0)
  match decode(bytes, Schema::empty()) {
    Ok(out) => assert_true(out == Message::empty())
    Err(e) => fail("空消息不应解码失败：\{e}")
  }
}

///|
/// 混合四类 wire 类型且乱序的字段，解码后**保持原始字段顺序**。
test "mixed fields preserve order on roundtrip" {
  let msg = Message::from_fields([
    FieldEntry::new(5, FieldValue::i32(7U)),
    FieldEntry::new(1, FieldValue::varint(150UL)),
    FieldEntry::new(3, FieldValue::bytes(b"abc")),
    FieldEntry::new(2, FieldValue::i64(99UL)),
  ])
  match decode(encode(msg), Schema::empty()) {
    Ok(out) => {
      assert_true(out == msg)
      // 显式校验顺序（字段号序列与构造一致）。
      let nums = out.fields.map(fn(e) { e.number })
      assert_true(nums == [5, 1, 3, 2])
    }
    Err(e) => fail("混合字段往返不应失败：\{e}")
  }
}

///|
/// 超大字段号（2^29 - 1，protobuf 允许的最大字段号）应正确编解码。
test "max field number roundtrips" {
  let msg = Message::from_fields([
    FieldEntry::new(536870911, FieldValue::varint(42UL)),
  ])
  match decode(encode(msg), Schema::empty()) {
    Ok(out) => {
      @test.assert_eq(out.fields[0].number, 536870911)
      assert_true(out == msg)
    }
    Err(e) => fail("最大字段号往返不应失败：\{e}")
  }
}

///|
/// 同一字段号出现多次（repeated 的 wire 形态）应保留全部记录与顺序。
test "repeated entries with same field number roundtrip" {
  let msg = Message::from_fields([
    FieldEntry::new(4, FieldValue::varint(1UL)),
    FieldEntry::new(4, FieldValue::varint(2UL)),
    FieldEntry::new(4, FieldValue::varint(3UL)),
  ])
  match decode(encode(msg), Schema::empty()) {
    Ok(out) => {
      @test.assert_eq(out.fields.length(), 3)
      assert_true(out == msg)
    }
    Err(e) => fail("同号重复字段往返不应失败：\{e}")
  }
}

// ─────────────────── 错误契约补充（Requirement 9.4）──────────────────────

///|
/// 过长 varint（10 字节续位标志均置位）→ 含偏移的 MalformedVarint，且无对象。
test "decode overlong varint reports malformed with offset" {
  let bytes = b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"
  match decode(bytes, Schema::empty()) {
    Ok(_) => fail("过长 varint 不应解码成功")
    Err(MalformedVarint(offset~)) => @test.assert_eq(offset, 0)
    Err(other) => fail("期望 MalformedVarint，实际：\{other}")
  }
}

///|
/// 定长 I64 字节不足 → 含偏移的 UnexpectedEof（偏移指向数据起点）。
test "decode truncated fixed64 reports offset" {
  // 字段号 1、wire I64(1)，但仅 3 字节数据（需 8）。
  let bytes = b"\x09\x01\x02\x03"
  match decode(bytes, Schema::empty()) {
    Ok(_) => fail("I64 字节不足不应解码成功")
    Err(UnexpectedEof(offset~)) => @test.assert_eq(offset, 1) // tag 占 1 字节。
    Err(other) => fail("期望 UnexpectedEof，实际：\{other}")
  }
}

///|
/// Len 长度前缀越界（远超剩余字节，无符号比较防溢出）→ 含偏移的 UnexpectedEof。
test "decode length overflow reports offset" {
  // 字段号 1、wire Len(2)，声明长度 200 但仅 2 字节内容。
  let bytes = b"\x0a\xc8\x01ab"
  match decode(bytes, Schema::empty()) {
    Ok(_) => fail("Len 长度越界不应解码成功")
    Err(UnexpectedEof(offset~)) => assert_true(offset >= 0)
    Err(other) => fail("期望 UnexpectedEof，实际：\{other}")
  }
}
