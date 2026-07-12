// 黑盒测试：覆盖率审计收口（INFRA 第八十批）——
// 大绳（Concat 结构）上的行定位/行列换算与孤立高代理项前缀计长。

///|
fn rg3_big_text() -> String {
  let sb = StringBuilder::new()
  for i in 0..<200 {
    sb.write_string("line-\{i} padded to be reasonably long 0123456789\n")
  }
  sb.to_string()
}

///|
test "Rope::offset_of_line：跨 Concat 结点定位行首" {
  let text = rg3_big_text()
  let r = @infra_text.Rope::from_string(text)
  // 与朴素扫描对照若干行首偏移。
  let mut expected = 0
  let mut line = 0
  for j in 0..<text.length() {
    if line % 37 == 0 {
      assert_eq(r.offset_of_line(line), expected)
    }
    if text.at(j).to_int() == 10 {
      line = line + 1
      expected = j + 1
    }
  }
  assert_eq(r.offset_of_line(line), expected)
}

///|
test "Rope::line_col_at：跨 Concat 结点行列换算" {
  let text = rg3_big_text()
  let r = @infra_text.Rope::from_string(text)
  // 中部与尾部偏移的 (行, 列) 与朴素计数一致。
  for off in [1000, 5000, text.length() - 1] {
    let mut line = 0
    let mut col = 0
    for j in 0..<off {
      if text.at(j).to_int() == 10 {
        line = line + 1
        col = 0
      } else {
        col = col + 1
      }
    }
    assert_eq(r.line_col_at(off), (line, col))
  }
}

///|
test "Rope::utf16_to_utf8：孤立高代理项按 3 字节计长" {
  let sb = StringBuilder::new()
  sb.write_char((0xD800).unsafe_to_char())
  sb.write_char('a')
  let r = @infra_text.Rope::from_string(sb.to_string())
  assert_eq(r.utf16_to_utf8(2), 4)
}
