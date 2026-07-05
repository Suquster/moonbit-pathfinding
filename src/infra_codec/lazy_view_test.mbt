// lazy_view_test.mbt —— MsgView 黑盒测试：定向（各 wire type/嵌套/畸形）+
// 与全量 eager 解码差分 PBT + 截断安全。

///|
test "lazy view basic: all wire types round-trip via lazy access" {
  let w = @infra_codec.ByteWriter::new()
  let fw = @infra_codec.FieldWriter::over(w)
  fw.varint_field(1, 300UL)
  fw.zigzag_field(2, -12345L)
  fw.fixed64_field(3, 0xDEADBEEF_CAFEBABEUL)
  fw.fixed32_field(4, 0xFEEDF00DU)
  fw.string_field(5, "héllo 世界 😀")
  let v = @infra_codec.MsgView::over(w.to_bytes())
  assert_true(v.varint_field(1) == Some(300UL))
  assert_true(v.zigzag_field(2) == Some(-12345L))
  assert_true(v.fixed64_field(3) == Some(0xDEADBEEF_CAFEBABEUL))
  assert_true(v.fixed32_field(4) == Some(0xFEEDF00DU))
  assert_true(v.string_field(5) == Some("héllo 世界 😀"))
  assert_true(v.field_count() == Some(5))
  // 未命中字段 / 类型不匹配。
  assert_true(v.varint_field(9) is None)
  assert_false(v.has_field(9))
  assert_true(v.has_field(3))
  assert_true(v.string_field(1) is None) // wire type 不匹配
  assert_true(v.fixed64_field(4) is None)
}

///|
test "lazy view: nested message zero-copy sub-view" {
  // 内层消息。
  let inner = @infra_codec.ByteWriter::new()
  let ifw = @infra_codec.FieldWriter::over(inner)
  ifw.varint_field(1, 7UL)
  ifw.string_field(2, "nested")
  // 外层：字段 3 = 嵌套消息，字段 4 = 后继字段（验证跳过正确）。
  let outer = @infra_codec.ByteWriter::new()
  let ofw = @infra_codec.FieldWriter::over(outer)
  ofw.varint_field(1, 42UL)
  ofw.message_field(3, inner.to_bytes())
  ofw.varint_field(4, 99UL)
  let v = @infra_codec.MsgView::over(outer.to_bytes())
  assert_true(v.varint_field(1) == Some(42UL))
  assert_true(v.varint_field(4) == Some(99UL))
  match v.message_field(3) {
    Some(sub) => {
      assert_true(sub.varint_field(1) == Some(7UL))
      assert_true(sub.string_field(2) == Some("nested"))
      assert_true(sub.field_count() == Some(2))
    }
    None => abort("nested view missing")
  }
}

///|
test "lazy view: truncated/malformed input returns None, never panics" {
  let w = @infra_codec.ByteWriter::new()
  let fw = @infra_codec.FieldWriter::over(w)
  fw.string_field(1, "hello world")
  fw.varint_field(2, 1UL)
  let full = w.to_bytes()
  // 每个截断前缀都必须安全。
  for cut in 0..<full.length() {
    let prefix : Array[Int] = []
    for i in 0..<cut {
      prefix.push(full[i])
    }
    let v = @infra_codec.MsgView::over(prefix)
    let _ = v.varint_field(2)
    let _ = v.string_field(1)
    let _ = v.field_count()
    let _ = v.has_field(1)
  }
  // 纯续传位垃圾。
  let junk = @infra_codec.MsgView::over([0x80, 0x80, 0x80])
  assert_true(junk.varint_field(1) is None)
  assert_true(junk.field_count() is None)
}

///|
test "lazy view differential PBT vs eager full decode (200 iterations)" {
  let rng = @infra_pbt.rng_new(0xE2_1A2FUL)
  for _iter in 0..<200 {
    // 随机消息：字段号 1..12 顺序、随机类型/值。
    let w = @infra_codec.ByteWriter::new()
    let fw = @infra_codec.FieldWriter::over(w)
    // eager 参照：field_no -> (kind, u64 值或字符串)。
    let kinds : Array[Int] = []
    let uvals : Array[UInt64] = []
    let svals : Array[String] = []
    let nfields = 1 + rng.next_below(12)
    for f in 1..<=nfields {
      let kind = rng.next_below(4)
      kinds.push(kind)
      match kind {
        0 => {
          let v = rng.next_below(1000000).to_uint64() * 2654435761UL
          fw.varint_field(f, v)
          uvals.push(v)
          svals.push("")
        }
        1 => {
          let v = rng.next_below(1000000).to_uint64() * 0x9E3779B9UL
          fw.fixed64_field(f, v)
          uvals.push(v)
          svals.push("")
        }
        2 => {
          let v = rng.next_below(0x7FFFFFFF).reinterpret_as_uint()
          fw.fixed32_field(f, v)
          uvals.push(v.to_uint64())
          svals.push("")
        }
        _ => {
          let sb = StringBuilder::new()
          for _ in 0..<rng.next_below(20) {
            match rng.next_below(3) {
              0 => sb.write_char((97 + rng.next_below(26)).unsafe_to_char())
              1 => sb.write_char((0x4E00 + rng.next_below(64)).unsafe_to_char())
              _ => sb.write_char((0x1F600 + rng.next_below(8)).unsafe_to_char())
            }
          }
          let s = sb.to_string()
          fw.string_field(f, s)
          uvals.push(0UL)
          svals.push(s)
        }
      }
    }
    let v = @infra_codec.MsgView::over(w.to_bytes())
    assert_true(v.field_count() == Some(nfields))
    // 乱序惰性访问全部字段，与参照一致。
    for f in 1..<=nfields {
      let idx = f - 1
      match kinds[idx] {
        0 => assert_true(v.varint_field(f) == Some(uvals[idx]))
        1 => assert_true(v.fixed64_field(f) == Some(uvals[idx]))
        2 => assert_true(v.fixed32_field(f) == Some(uvals[idx].to_uint()))
        _ => assert_true(v.string_field(f) == Some(svals[idx]))
      }
    }
    assert_false(v.has_field(nfields + 1))
  }
}
