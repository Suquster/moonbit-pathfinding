// 黑盒测试：覆盖率审计收口（INFRA 第七十九批）——
// 基准报告 JSON 解析的类型不符与 \u 截断拒绝。

///|
fn rg2_report(warmup : String, min_val : String) -> String {
  "{\"moon_version\":\"m\",\"backend\":\"wasm\"," +
  "\"machine\":{\"os\":\"linux\",\"cpu\":\"x\"}," +
  "\"generator\":\"g\",\"warmup_count\":" +
  warmup +
  ",\"cases\":[{\"algorithm\":\"dij\",\"graph_size\":2," +
  "\"edge_count\":1,\"query_count\":1,\"seed\":7," +
  "\"raw_ns\":[1.5],\"stats\":{\"min\":" +
  min_val +
  ",\"max\":2.0,\"median\":1.5,\"mean\":1.5,\"p95\":2.0,\"stddev\":0.1,\"sample_count\":1}}]}"
}

///|
test "parse_report：整型/浮点字段类型不符定位报错" {
  assert_true(@infra_bench.parse_report(rg2_report("\"x\"", "1.0")) is Err(_))
  assert_true(@infra_bench.parse_report(rg2_report("3", "true")) is Err(_))
  // 合法基线：同一构造在字段正确时可解析成功。
  guard @infra_bench.parse_report(rg2_report("3", "1.0")) is Ok(r)
  assert_eq(r.cases.length(), 1)
}

///|
test "parse_report：字符串 \\u 转义截断拒绝" {
  assert_true(@infra_bench.parse_report("{\"moon_version\":\"\\u12") is Err(_))
}
