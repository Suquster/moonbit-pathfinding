// codec_gaps_test.mbt —— 字节编解码与惰性视图错误分支覆盖收口
// （INFRA 第二十批）：varint 截断/超长、字符串载荷畸形码点、
// LEN 越界、字段定位跳过各线型与保留线型拒绝的确定性见证。

///|
test "ByteReader 截断与畸形拒绝" {
  // varint：尾字节续传位悬空 / 超过 10 字节仍续传。
  assert_true(ByteReader::new([0x80]).read_varint() is None)
  assert_true(
    ByteReader::new([
      0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x01,
    ]).read_varint()
    is None,
  )
  // zigzag：底层 varint 截断传播。
  assert_true(ByteReader::new([0x80]).read_zigzag() is None)
  // u32 / u64 剩余不足。
  assert_true(ByteReader::new([1, 2, 3]).read_u32() is None)
  assert_true(ByteReader::new([1, 2, 3, 4, 5, 6, 7]).read_u64() is None)
  // bytes：长度前缀越界。
  assert_true(ByteReader::new([5, 1, 2]).read_bytes() is None)
  assert_true(ByteReader::new([0x80]).read_bytes() is None)
  // read_string：长度前缀截断 / 码点缺失 / 非法码点。
  assert_true(ByteReader::new([0x80]).read_string() is None)
  assert_true(ByteReader::new([2, 65]).read_string() is None)
  assert_true(
    ByteReader::new([1, 0x80, 0x80, 0x80, 0x80, 0x08]).read_string() is None,
  )
}

///|
test "ByteReader 字符串载荷畸形与往返" {
  // read_string_payload：字节长度前缀越界 / 码点 varint 跨界 / 代理区码点。
  assert_true(ByteReader::new([9, 65]).read_string_payload() is None)
  assert_true(ByteReader::new([0x80]).read_string_payload() is None)
  // 载荷区间内 varint 续传位延伸出界（pos > stop）。
  assert_true(ByteReader::new([1, 0x80, 0x01]).read_string_payload() is None)
  // 代理区码点 0xD800 → to_char 失败。
  assert_true(
    ByteReader::new([3, 0x80, 0xB0, 0x03]).read_string_payload() is None,
  )
  // 合法往返：writer.write_string 与 read_string 对偶。
  let w = ByteWriter::new()
  w.write_string("中𐍈a")
  assert_true(ByteReader::new(w.to_bytes()).read_string() == Some("中𐍈a"))
  // FieldWriter::string_field 与 read_string_payload 对偶。
  let w2 = ByteWriter::new()
  let fw = FieldWriter::over(w2)
  fw.string_field(1, "héllo")
  let r = ByteReader::new(w2.to_bytes())
  let _ = r.read_varint() // 跳过字段 key
  assert_true(r.read_string_payload() == Some("héllo"))
}

///|
test "MsgView 字段定位跳过各线型与畸形拒绝" {
  // 组装：f1 varint、f2 fixed64、f3 fixed32、f4 string、f5 zigzag。
  let w = ByteWriter::new()
  let fw = FieldWriter::over(w)
  fw.varint_field(1, 300UL)
  fw.fixed64_field(2, 0x1122334455667788UL)
  fw.fixed32_field(3, 0xAABBCCDDU)
  fw.string_field(4, "ok")
  fw.zigzag_field(5, -7L)
  let v = MsgView::over(w.to_bytes())
  // 后位字段命中须跳过前面全部线型。
  assert_true(v.zigzag_field(5) == Some(-7L))
  assert_true(v.string_field(4) == Some("ok"))
  assert_true(v.fixed32_field(3) == Some(0xAABBCCDDU))
  assert_true(v.fixed64_field(2) == Some(0x1122334455667788UL))
  assert_true(v.varint_field(1) == Some(300UL))
  assert_true(v.field_count() == Some(5))
  // 未命中与线型不匹配。
  assert_true(v.varint_field(9) is None)
  assert_true(v.fixed64_field(1) is None)
  assert_true(v.fixed32_field(1) is None)
  assert_true(v.string_field(1) is None)
  assert_true(v.bytes_field(1) is None)
  assert_true(v.message_field(1) is None)
  // 保留线型（wire=3）：定位与计数均拒绝。
  let bad = MsgView::over([0x0B])
  // 命中位线型不匹配：定位命中但取值拒绝；跳过位保留线型则整体拒绝。
  assert_true(bad.varint_field(1) is None)
  assert_true(bad.has_field(2) == false)
  assert_true(bad.field_count() is None)
  // key varint 截断 / varint 值截断 / LEN 长度越界。
  assert_true(MsgView::over([0x80]).field_count() is None)
  assert_true(MsgView::over([0x08, 0x80]).varint_field(1) is None)
  assert_true(MsgView::over([0x08, 0x80]).field_count() is None)
  assert_true(MsgView::over([0x0A, 0x05, 0x01]).string_field(1) is None)
  assert_true(MsgView::over([0x0A, 0x80]).field_count() is None)
  // fixed64/fixed32 载荷越界（p > end 防护）。
  assert_true(MsgView::over([0x09, 1, 2]).fixed64_field(1) is None)
  assert_true(MsgView::over([0x0D, 1, 2]).fixed32_field(1) is None)
  // 跳过路径的越界：首字段 fixed64 载荷不足时定位后续字段失败。
  assert_true(MsgView::over([0x09, 1, 2]).varint_field(2) is None)
}

///|
test "MsgView 嵌套消息与字符串载荷畸形" {
  // 嵌套消息：外层 f1 为消息，内层 f2 varint。
  let inner = ByteWriter::new()
  let ifw = FieldWriter::over(inner)
  ifw.varint_field(2, 42UL)
  let outer = ByteWriter::new()
  let ofw = FieldWriter::over(outer)
  ofw.message_field(1, inner.to_bytes())
  let v = MsgView::over(outer.to_bytes())
  match v.message_field(1) {
    Some(sub) => assert_true(sub.varint_field(2) == Some(42UL))
    None => assert_true(false)
  }
  // string 载荷：码点 varint 跨界 / 代理区码点。
  assert_true(MsgView::over([0x0A, 0x01, 0x80]).string_field(1) is None)
  assert_true(
    MsgView::over([0x0A, 0x03, 0x80, 0xB0, 0x03]).string_field(1) is None,
  )
  // bytes 载荷正常物化。
  assert_true(MsgView::over([0x0A, 0x02, 7, 8]).bytes_field(1) == Some([7, 8]))
}
