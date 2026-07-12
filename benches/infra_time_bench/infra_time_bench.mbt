// infra_time_bench.mbt —— 时间方向基准：解析 / 格式化 / 历法换算 /
// 时区求解在确定性输入上的吞吐对比。

///|
fn tb_datetimes(n : Int) -> Array[@time.DateTime] {
  let out : Array[@time.DateTime] = []
  for i in 0..<n {
    out.push(
      @time.datetime_from_epoch_seconds(1_783_000_000L + i.to_int64() * 86_461L),
    )
  }
  out
}

///|
test "smoke: iso8601 round-trip and civil conversion agree" {
  let dts = tb_datetimes(64)
  for dt in dts {
    let s = @time.format_iso8601(dt)
    match @time.parse_iso8601(s) {
      Some(back) => assert_eq(@time.format_iso8601(back), s)
      None => assert_true(false)
    }
  }
  let days = @time.days_from_civil(2026, 7, 12)
  let (y, m, d) = @time.civil_from_days(days)
  assert_eq(y, 2026)
  assert_eq(m, 7)
  assert_eq(d, 12)
}

///|
test "bench: parse / format / civil / tz throughput" (b : @bench.T) {
  let dts = tb_datetimes(256)
  let strs : Array[String] = []
  for dt in dts {
    strs.push(@time.format_iso8601(dt))
  }
  b.bench(name="parse_iso8601_256", fn() {
    let mut ok = 0
    for s in strs {
      match @time.parse_iso8601(s) {
        Some(_) => ok = ok + 1
        None => ()
      }
    }
    b.keep(ok)
  })
  b.bench(name="format_iso8601_256", fn() {
    let mut total = 0
    for dt in dts {
      total = total + @time.format_iso8601(dt).length()
    }
    b.keep(total)
  })
  b.bench(name="strftime_256", fn() {
    let mut total = 0
    for dt in dts {
      total = total + @time.strftime(dt, "%a %b %e, %Y %H:%M:%S").length()
    }
    b.keep(total)
  })
  b.bench(name="civil_roundtrip_256", fn() {
    let mut acc = 0L
    for dt in dts {
      let days = @time.days_from_civil(dt.year, dt.month, dt.day)
      let (y, _, _) = @time.civil_from_days(days)
      acc = acc + y.to_int64()
    }
    b.keep(acc)
  })
  match @time.parse_posix_tz("EST5EDT,M3.2.0/2,M11.1.0/2") {
    Some(rule) =>
      b.bench(name="tz_offset_at_256", fn() {
        let mut acc = 0
        for dt in dts {
          let (offset, _) = @time.tz_offset_at(rule, dt)
          acc = acc + offset
        }
        b.keep(acc)
      })
    None => ()
  }
}
