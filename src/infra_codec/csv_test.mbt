// csv_test.mbt —— RFC 4180 CSV 测试：已知向量 + 畸形拒绝 + roundtrip PBT。

///|
test "csv encode quotes only when needed" {
  assert_eq(@infra_codec.csv_encode_row(["a", "b", "c"]), "a,b,c")
  assert_eq(@infra_codec.csv_encode_row(["a,b"]), "\"a,b\"")
  assert_eq(@infra_codec.csv_encode_row(["say \"hi\""]), "\"say \"\"hi\"\"\"")
  assert_eq(@infra_codec.csv_encode_row(["line1\nline2"]), "\"line1\nline2\"")
  assert_eq(@infra_codec.csv_encode_row(["", ""]), ",")
}

///|
test "csv decode rfc4180 vectors" {
  // 基本行。
  assert_true(@infra_codec.csv_decode("a,b,c\n") == Some([["a", "b", "c"]]))
  // 末尾无换行。
  assert_true(@infra_codec.csv_decode("a,b") == Some([["a", "b"]]))
  // CRLF 行终止（RFC 4180 §2 规则 1）。
  assert_true(
    @infra_codec.csv_decode("a,b\r\nc,d\r\n") == Some([["a", "b"], ["c", "d"]]),
  )
  // 引号字段内嵌逗号 / 换行 / 转义双引号（规则 6-7）。
  assert_true(@infra_codec.csv_decode("\"a,b\",c\n") == Some([["a,b", "c"]]))
  assert_true(
    @infra_codec.csv_decode("\"l1\nl2\",x\n") == Some([["l1\nl2", "x"]]),
  )
  assert_true(
    @infra_codec.csv_decode("\"say \"\"hi\"\"\"\n") == Some([["say \"hi\""]]),
  )
  // 空字段。
  assert_true(@infra_codec.csv_decode(",\n") == Some([["", ""]]))
  // 空输入 → 空表。
  assert_true(@infra_codec.csv_decode("") == Some([]))
  // UTF-8 内容。
  assert_true(
    @infra_codec.csv_decode("路径,规划\n") == Some([["路径", "规划"]]),
  )
}

///|
test "csv decode rejects malformed input" {
  // 未闭合引号。
  assert_true(@infra_codec.csv_decode("\"abc") == None)
  // 引号闭合后有杂字符。
  assert_true(@infra_codec.csv_decode("\"a\"x,b\n") == None)
  // 字段中途出现引号。
  assert_true(@infra_codec.csv_decode("ab\"c\",d\n") == None)
}

///|
test "csv roundtrip (pbt)" {
  let rng = @infra_pbt.rng_new(20260707UL)
  for _ in 0..<200 {
    let rows : Array[Array[String]] = []
    for _ in 0..<(1 + rng.next_below(5)) {
      let row : Array[String] = []
      for _ in 0..<(1 + rng.next_below(5)) {
        let sb = StringBuilder::new()
        for _ in 0..<rng.next_below(8) {
          let c = match rng.next_below(7) {
            0 => ','
            1 => '"'
            2 => '\n'
            3 => '\r'
            4 => '路'
            _ => ('a'.to_int() + rng.next_below(26)).to_char().unwrap()
          }
          sb.write_char(c)
        }
        row.push(sb.to_string())
      }
      rows.push(row)
    }
    let encoded = @infra_codec.csv_encode(rows)
    assert_true(@infra_codec.csv_decode(encoded) == Some(rows))
  }
}
