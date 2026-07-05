// prop_high_cardinality_test.mbt —— T7.4 高基数性能 guard（纲领方向七）。
//
// 目标：大量字段/大量 span 下，结构化输出对**总长度线性**——每项的边际
// 字节成本恒定（仿射增长），杜绝隐藏的二次膨胀（重复拼接 / 重复转义等）。
// 方法：构造逐项等宽的均匀字段集，在 n 倍增序列上断言边际成本稳定
// （容差 ≤1 字节/项，吸收外层 varint 长度前缀的位宽漂移），并以
// 10_000 字段的高基数样本做「格式化→解析」无损往返冒烟。

///|
/// 生成 n 个等宽键（k0000…k9999）、等宽值的均匀字段表。
fn uniform_fields(n : Int) -> Map[String, Value] {
  let m : Map[String, Value] = Map([])
  for i in 0..<n {
    let mut s = i.to_string()
    while s.length() < 4 {
      s = "0" + s
    }
    m["k" + s] = VStr("v")
  }
  m
}

///|
/// n 项输出的每项边际字节成本 ×1000（整数化避免浮点）：
/// `(len(2n) - len(n)) * 1000 / n`。
fn marginal_cost_x1000(len_n : Int, len_2n : Int, n : Int) -> Int {
  (len_2n - len_n) * 1000 / n
}

///|
test "Feature: logging, Guard: format_json / format_logfmt output is affine in field count" {
  for fmt_id in [0, 1] {
    let lens : Array[Int] = []
    for n in [256, 512, 1024, 2048] {
      let e : Event = { ts: 1L, level: Info, fields: uniform_fields(n) }
      let out = if fmt_id == 0 { format_json(e) } else { format_logfmt(e) }
      lens.push(out.length())
    }
    let d1 = marginal_cost_x1000(lens[0], lens[1], 256)
    let d2 = marginal_cost_x1000(lens[1], lens[2], 512)
    let d3 = marginal_cost_x1000(lens[2], lens[3], 1024)
    // 边际成本恒定（±1000 即 ≤1 字节/项容差）：仿射，无二次膨胀。
    assert_true(d1 - d2 <= 1000 && d2 - d1 <= 1000)
    assert_true(d2 - d3 <= 1000 && d3 - d2 <= 1000)
  }
}

///|
test "Feature: logging, Guard: OTLP export bytes are affine in span count" {
  let lens : Array[Int] = []
  for n in [64, 128, 256, 512] {
    let spans : Array[(String, SpanData)] = []
    for i in 0..<n {
      let sd = SpanData::new({
        id: { value: (i + 1).to_int64() },
        parent: None,
        start: 1L,
        end: Some(2L),
      })
      sd.set_attribute("k", VStr("v"))
      spans.push(("op", sd))
    }
    lens.push(otlp_export_traces("svc", { value: 9L }, spans).length())
  }
  let d1 = marginal_cost_x1000(lens[0], lens[1], 64)
  let d2 = marginal_cost_x1000(lens[1], lens[2], 128)
  let d3 = marginal_cost_x1000(lens[2], lens[3], 256)
  // span 定长编码下边际成本恒定（±1000 容差吸收外层 varint 位宽漂移）。
  assert_true(d1 - d2 <= 1000 && d2 - d1 <= 1000)
  assert_true(d2 - d3 <= 1000 && d3 - d2 <= 1000)
}

///|
test "Feature: logging, Smoke: 10k-field event round-trips losslessly" {
  let n = 10_000
  let m : Map[String, Value] = Map([])
  for i in 0..<n {
    m["key_" + i.to_string()] = VInt(i.to_int64())
  }
  let e : Event = { ts: 7L, level: Warn, fields: m }
  match parse_json_log(format_json(e)) {
    Some(back) => {
      assert_eq(back.fields.length(), n)
      assert_true(back.fields.get("key_9999") == Some(Value::VInt(9999L)))
    }
    None => fail("高基数事件应可无损往返")
  }
}
