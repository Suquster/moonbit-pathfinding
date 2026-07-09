// report_gaps_test.mbt —— BenchReport JSON 解析器错误分支覆盖收口
// （INFRA 第十七批）：结构缺字段 / 类型不符 / 语法破坏的确定性反例。

///|
/// 组装一份最小合法报告 JSON（单 case），供逐字段破坏。
fn rg_valid() -> String {
  "{\"moon_version\":\"v\",\"backend\":\"native\"," +
  "\"machine\":{\"os\":\"linux\",\"cpu\":\"x\"}," +
  "\"generator\":\"g\",\"warmup_count\":1," +
  "\"cases\":[{\"algorithm\":\"a\",\"graph_size\":1,\"edge_count\":1," +
  "\"query_count\":1,\"seed\":7," +
  "\"raw_ns\":[1.5]," +
  "\"stats\":{\"min\":1,\"max\":1,\"median\":1,\"mean\":1,\"p95\":1," +
  "\"stddev\":0,\"sample_count\":1}}]}"
}

///|
test "report JSON：最小合法报告可解析且往返" {
  match parse_report(rg_valid()) {
    Ok(r) => {
      assert_true(r.cases.length() == 1)
      assert_true(r.cases[0].seed == 7UL)
      assert_true(parse_report(r.to_json()) is Ok(_))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "report JSON：顶层与 machine 结构错误" {
  // 语法非法 / 顶层非对象。
  assert_true(parse_report("!") is Err(_))
  assert_true(parse_report("[1]") is Err(_))
  // machine 缺失 / 非对象 / os、cpu 缺失。
  assert_true(
    parse_report("{\"moon_version\":\"v\",\"backend\":\"b\"}") is Err(_),
  )
  assert_true(
    parse_report("{\"moon_version\":\"v\",\"backend\":\"b\",\"machine\":1}")
    is Err(_),
  )
  assert_true(
    parse_report("{\"moon_version\":\"v\",\"backend\":\"b\",\"machine\":{}}")
    is Err(_),
  )
  assert_true(
    parse_report(
      "{\"moon_version\":\"v\",\"backend\":\"b\"," +
      "\"machine\":{\"os\":\"l\"}}",
    )
    is Err(_),
  )
  // generator / warmup_count / cases 缺失或类型不符。
  let head = "{\"moon_version\":\"v\",\"backend\":\"b\"," +
    "\"machine\":{\"os\":\"l\",\"cpu\":\"c\"}"
  assert_true(parse_report(head + "}") is Err(_))
  assert_true(parse_report(head + ",\"generator\":\"g\"}") is Err(_))
  assert_true(
    parse_report(head + ",\"generator\":\"g\",\"warmup_count\":1}") is Err(_),
  )
  assert_true(
    parse_report(head + ",\"generator\":\"g\",\"warmup_count\":1,\"cases\":1}")
    is Err(_),
  )
  // moon_version 类型不符（字符串字段收到数值）。
  assert_true(parse_report("{\"moon_version\":1}") is Err(_))
}

///|
test "report JSON：case 与 stats 逐字段破坏" {
  // case 非对象。
  let head = "{\"moon_version\":\"v\",\"backend\":\"b\"," +
    "\"machine\":{\"os\":\"l\",\"cpu\":\"c\"}," +
    "\"generator\":\"g\",\"warmup_count\":1,\"cases\":["
  assert_true(parse_report(head + "1]}") is Err(_))
  // algorithm / graph_size / edge_count / query_count / seed 缺失。
  assert_true(parse_report(head + "{}]}") is Err(_))
  assert_true(parse_report(head + "{\"algorithm\":\"a\"}]}") is Err(_))
  assert_true(
    parse_report(head + "{\"algorithm\":\"a\",\"graph_size\":1}]}") is Err(_),
  )
  assert_true(
    parse_report(
      head + "{\"algorithm\":\"a\",\"graph_size\":1,\"edge_count\":1}]}",
    )
    is Err(_),
  )
  let c4 = "{\"algorithm\":\"a\",\"graph_size\":1,\"edge_count\":1," +
    "\"query_count\":1"
  assert_true(parse_report(head + c4 + "}]}") is Err(_))
  // seed 非法 / raw_ns 缺失 / 非数组 / 含非法浮点。
  assert_true(parse_report(head + c4 + ",\"seed\":\"x\"}]}") is Err(_))
  assert_true(parse_report(head + c4 + ",\"seed\":7}]}") is Err(_))
  assert_true(parse_report(head + c4 + ",\"seed\":7,\"raw_ns\":1}]}") is Err(_))
  assert_true(
    parse_report(head + c4 + ",\"seed\":7,\"raw_ns\":[true]}]}") is Err(_),
  )
  // stats 缺失 / 非对象 / 逐字段缺失。
  let c5 = c4 + ",\"seed\":7,\"raw_ns\":[1.5]"
  assert_true(parse_report(head + c5 + "}]}") is Err(_))
  assert_true(parse_report(head + c5 + ",\"stats\":1}]}") is Err(_))
  assert_true(parse_report(head + c5 + ",\"stats\":{}}]}") is Err(_))
  assert_true(parse_report(head + c5 + ",\"stats\":{\"min\":1}}]}") is Err(_))
  assert_true(
    parse_report(head + c5 + ",\"stats\":{\"min\":1,\"max\":1}}]}") is Err(_),
  )
  assert_true(
    parse_report(head + c5 + ",\"stats\":{\"min\":1,\"max\":1,\"median\":1}}]}")
    is Err(_),
  )
  assert_true(
    parse_report(
      head + c5 + ",\"stats\":{\"min\":1,\"max\":1,\"median\":1,\"mean\":1}}]}",
    )
    is Err(_),
  )
  assert_true(
    parse_report(
      head +
      c5 +
      ",\"stats\":{\"min\":1,\"max\":1,\"median\":1,\"mean\":1,\"p95\":1}}]}",
    )
    is Err(_),
  )
  assert_true(
    parse_report(
      head +
      c5 +
      ",\"stats\":{\"min\":1,\"max\":1,\"median\":1,\"mean\":1,\"p95\":1," +
      "\"stddev\":0}}]}",
    )
    is Err(_),
  )
}

///|
test "report JSON：底层解析器结构破坏" {
  // 对象：键非字符串 / 缺冒号 / 值缺失 / 缺逗号或闭括号。
  assert_true(parse_report("{1:2}") is Err(_))
  assert_true(parse_report("{\"a\" 1}") is Err(_))
  assert_true(parse_report("{\"a\":}") is Err(_))
  assert_true(parse_report("{\"a\":1 \"b\":2}") is Err(_))
  assert_true(parse_report("{\"a\":1") is Err(_))
  // 数组：值缺失 / 缺逗号或闭括号。
  assert_true(parse_report("[") is Err(_))
  assert_true(parse_report("[1 2]") is Err(_))
  assert_true(parse_report("[1,") is Err(_))
  // 字符串未闭合。
  assert_true(parse_report("{\"a") is Err(_))
}
