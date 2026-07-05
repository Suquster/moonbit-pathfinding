// schema_evolution_test.mbt —— E2 模式演化兼容测试（protobuf 语义）：
// 旧读者读新消息（未知字段跳过）、新读者读旧消息（缺失字段 None）、
// 字段重排等价、嵌套消息演化、int32→int64 拓宽——差分 PBT 守卫。

///|
test "schema evolution: old reader skips unknown fields (forward compat)" {
  // v2 消息：在 v1 字段（1=id varint, 2=name string）之间插入未知
  // 字段（10=fixed64, 11=string, 12=嵌套消息, 13=fixed32）。
  let inner = @infra_codec.ByteWriter::new()
  let ifw = @infra_codec.FieldWriter::over(inner)
  ifw.varint_field(1, 5UL)
  let w = @infra_codec.ByteWriter::new()
  let fw = @infra_codec.FieldWriter::over(w)
  fw.fixed64_field(10, 0xAAAA_BBBB_CCCC_DDDDUL)
  fw.varint_field(1, 42UL)
  fw.string_field(11, "future-field")
  fw.message_field(12, inner.to_bytes())
  fw.string_field(2, "alice")
  fw.fixed32_field(13, 7U)
  // 旧读者只认识字段 1/2：未知字段全部被键扫描跳过。
  let v = @infra_codec.MsgView::over(w.to_bytes())
  assert_true(v.varint_field(1) == Some(42UL))
  assert_true(v.string_field(2) == Some("alice"))
  assert_true(v.field_count() == Some(6))
}

///|
test "schema evolution: new reader on old message (backward compat)" {
  // 旧消息只有字段 1；新 schema 增加字段 2（string）/3（varint），
  // 读缺失字段必须得 None（由应用层给默认值），不得 panic/错读。
  let w = @infra_codec.ByteWriter::new()
  let fw = @infra_codec.FieldWriter::over(w)
  fw.varint_field(1, 1UL)
  let v = @infra_codec.MsgView::over(w.to_bytes())
  assert_true(v.varint_field(1) == Some(1UL))
  assert_true(v.string_field(2) is None)
  assert_true(v.varint_field(3) is None)
  assert_false(v.has_field(2))
}

///|
test "schema evolution: varint widening keeps value (int32 -> int64)" {
  // 写端按 32 位语义写小值，读端按 64 位读——LEB128 值域兼容。
  let w = @infra_codec.ByteWriter::new()
  let fw = @infra_codec.FieldWriter::over(w)
  fw.varint_field(1, 0xFFFF_FFFFUL) // u32 上界
  fw.zigzag_field(2, -2147483648L) // i32 下界
  let v = @infra_codec.MsgView::over(w.to_bytes())
  assert_true(v.varint_field(1) == Some(0xFFFF_FFFFUL))
  assert_true(v.zigzag_field(2) == Some(-2147483648L))
}

///|
test "schema evolution differential PBT: field reorder + unknown injection (200 iterations)" {
  // 性质：已知字段集合的读取结果与 (a) 字段写入顺序、(b) 注入的未知
  // 字段无关——protobuf 前后兼容语义核心。
  let rng = @infra_pbt.rng_new(0xE2_5C4E_A0UL)
  for _iter in 0..<200 {
    // 已知字段 1..6：随机类型与值。
    let kinds : Array[Int] = []
    let uvals : Array[UInt64] = []
    let svals : Array[String] = []
    for _f in 1..<=6 {
      let kind = rng.next_below(3)
      kinds.push(kind)
      match kind {
        0 => {
          uvals.push(rng.next_below(1000000).to_uint64() * 2654435761UL)
          svals.push("")
        }
        1 => {
          uvals.push(rng.next_below(1000000).to_uint64() * 0x9E3779B9UL)
          svals.push("")
        }
        _ => {
          let sb = StringBuilder::new()
          for _ in 0..<rng.next_below(12) {
            sb.write_char((97 + rng.next_below(26)).unsafe_to_char())
          }
          uvals.push(0UL)
          svals.push(sb.to_string())
        }
      }
    }
    // 随机写入顺序（Fisher-Yates）+ 随机位置注入未知字段 100..104。
    let order : Array[Int] = [1, 2, 3, 4, 5, 6]
    for i = order.length() - 1; i > 0; i = i - 1 {
      let j = rng.next_below(i + 1)
      let t = order[i]
      order[i] = order[j]
      order[j] = t
    }
    let w = @infra_codec.ByteWriter::new()
    let fw = @infra_codec.FieldWriter::over(w)
    fn maybe_unknown() {
      if rng.next_below(3) == 0 {
        match rng.next_below(3) {
          0 => fw.varint_field(100 + rng.next_below(5), 777UL)
          1 => fw.fixed64_field(100 + rng.next_below(5), 0xDEADUL)
          _ => fw.string_field(100 + rng.next_below(5), "unknown")
        }
      }
    }
    for f in order {
      maybe_unknown()
      let idx = f - 1
      match kinds[idx] {
        0 => fw.varint_field(f, uvals[idx])
        1 => fw.fixed64_field(f, uvals[idx])
        _ => fw.string_field(f, svals[idx])
      }
    }
    maybe_unknown()
    // 读取与顺序/未知字段无关。
    let v = @infra_codec.MsgView::over(w.to_bytes())
    for f in 1..<=6 {
      let idx = f - 1
      match kinds[idx] {
        0 => assert_true(v.varint_field(f) == Some(uvals[idx]))
        1 => assert_true(v.fixed64_field(f) == Some(uvals[idx]))
        _ => assert_true(v.string_field(f) == Some(svals[idx]))
      }
    }
  }
}

///|
test "schema evolution: nested message evolves independently" {
  // 内层 v2 加了未知字段，外层旧读者仍能取到内层已知字段。
  let inner = @infra_codec.ByteWriter::new()
  let ifw = @infra_codec.FieldWriter::over(inner)
  ifw.string_field(9, "inner-future")
  ifw.varint_field(1, 314UL)
  let w = @infra_codec.ByteWriter::new()
  let fw = @infra_codec.FieldWriter::over(w)
  fw.message_field(1, inner.to_bytes())
  fw.varint_field(2, 1UL)
  let v = @infra_codec.MsgView::over(w.to_bytes())
  match v.message_field(1) {
    Some(sub) => {
      assert_true(sub.varint_field(1) == Some(314UL))
      assert_true(sub.varint_field(5) is None)
    }
    None => abort("nested view missing")
  }
  assert_true(v.varint_field(2) == Some(1UL))
}
