// toml_datetime_test.mbt —— 日期时间语义校验收口（INFRA 第四十九批）：
// RFC 3339 全形态合法接受 + 越界/畸形拒绝（月/日/闰年/时分秒/偏移）。

///|
fn tdt_ok(src : String, expect : String) -> Bool {
  match @infra_config.toml_parse("v = " + src) {
    Some(doc) =>
      @infra_config.toml_get(doc, "v") ==
      Some(@infra_config.TomlDatetime(expect))
    None => false
  }
}

///|
fn tdt_rejects(src : String) -> Bool {
  @infra_config.toml_parse("v = " + src) is None
}

///|
test "toml datetime：全形态合法接受" {
  assert_true(tdt_ok("1979-05-27", "1979-05-27"))
  assert_true(tdt_ok("1979-05-27T07:32:00", "1979-05-27T07:32:00"))
  assert_true(tdt_ok("1979-05-27 07:32:00", "1979-05-27 07:32:00"))
  assert_true(tdt_ok("1979-05-27T07:32:00Z", "1979-05-27T07:32:00Z"))
  assert_true(tdt_ok("1979-05-27t07:32:00z", "1979-05-27t07:32:00z"))
  assert_true(
    tdt_ok(
      "1979-05-27T00:32:00.999999-07:00", "1979-05-27T00:32:00.999999-07:00",
    ),
  )
  assert_true(tdt_ok("1979-05-27T07:32:00+13:45", "1979-05-27T07:32:00+13:45"))
  // 闰年 2 月 29 与闰秒。
  assert_true(tdt_ok("2000-02-29", "2000-02-29"))
  assert_true(tdt_ok("2024-02-29", "2024-02-29"))
  assert_true(tdt_ok("1990-12-31T23:59:60Z", "1990-12-31T23:59:60Z"))
  // 纯时刻。
  assert_true(tdt_ok("07:32:00", "07:32:00"))
  assert_true(tdt_ok("00:32:00.999", "00:32:00.999"))
}

///|
test "toml datetime：越界与畸形拒绝" {
  // 月/日越界。
  assert_true(tdt_rejects("1979-13-01"))
  assert_true(tdt_rejects("1979-00-01"))
  assert_true(tdt_rejects("1979-05-32"))
  assert_true(tdt_rejects("1979-05-00"))
  assert_true(tdt_rejects("1979-04-31")) // 4 月只有 30 天
  // 非闰年 2 月 29（1900 年可被 100 整除但不可被 400 整除）。
  assert_true(tdt_rejects("2023-02-29"))
  assert_true(tdt_rejects("1900-02-29"))
  // 时分秒越界。
  assert_true(tdt_rejects("1979-05-27T24:00:00"))
  assert_true(tdt_rejects("1979-05-27T07:60:00"))
  assert_true(tdt_rejects("1979-05-27T07:32:61"))
  // 分隔符/尾巴畸形。
  assert_true(tdt_rejects("1979-05-27X07:32:00"))
  assert_true(tdt_rejects("1979-05-27T07:32:00Zx"))
  assert_true(tdt_rejects("1979-05-27T07:32:00.")) // 小数点后无数字
  // 偏移越界/畸形。
  assert_true(tdt_rejects("1979-05-27T07:32:00+24:00"))
  assert_true(tdt_rejects("1979-05-27T07:32:00+07:60"))
  assert_true(tdt_rejects("1979-05-27T07:32:00+0700"))
  // 纯时刻越界与带偏移（纯时刻不允许偏移）。
  assert_true(tdt_rejects("25:00:00"))
  assert_true(tdt_rejects("07:32:00Z"))
}
